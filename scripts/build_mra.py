#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the .mra files and prove each one byte for byte.

    python scripts/build_mra.py                      # every set with ROMs here -> releases/_dev/
    python scripts/build_mra.py snowbros hyperpac    # these
    python scripts/build_mra.py --check              # verify only, write nothing
    python scripts/build_mra.py --image snowbros out.bin   # the download image, for the benches
    python scripts/build_mra.py --release            # -> releases/ (only with a released .rbf)

The image is the SDRAM layout of rtl/memory/snowbros_sdram_top.sv, whose *_BASE localparams are
read here, before the core's download transforms (rtl/memory/dl_xform.sv). Each region is built
twice: from the driver's ROM_START records (scripts/extract_romstart.py) and by re-reading the
written .mra with scripts/mra.py; the two must be identical. Interleave maps are not reasoned
about: each candidate is tried against the ROM_START image. After the DreamWorld core's
build_mra.py.

protdata goes into the image as the file's bytes: MAME's 68000 sees them in that order at its
work RAM address in every in-scope set (checked at frame 1 in MAME 0.289, whatever the load
macro), and the core copies them in that order.
"""
import argparse
import itertools
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_dips as edips       # noqa: E402
import extract_romstart as ers     # noqa: E402
import mra as mra_lib              # noqa: E402
from coretools import setting      # noqa: E402

REPO = Path(__file__).resolve().parent.parent
DRIVER = Path(setting("MAME_SRC") or "E:/mame/src/mame/kaneko/snowbros.cpp")
ROMDIRS = [Path(p) for p in (setting("MAME_ROMPATH") or "").split(";") if p]

# set: parent or None (the in-scope Pandora sets, docs/ROADMAP.md)
SETS = {"snowbros": None, "snowbrosa": "snowbros", "snowbrosb": "snowbros", "snowbrosc": "snowbros",
        "snowbrosj": "snowbros", "snowbrosd": "snowbros", "toto": None,
        "hyperpac": None, "hyperpacb": "hyperpac", "cookbib2": None, "cookbib2a": "cookbib2",
        "cookbib2b": "cookbib2", "cookbib2c": "cookbib2", "cookbib3": None,
        "sutjarod": None, "gwasu": None, "yutnori": None,
        "finalttr": None, "toppyrap": None, "pzlbreak": None, "pzlbreaka": "pzlbreak",
        "suhosong": None, "twinkle": None, "twinklea": "twinkle", "3in1semi": None,
        "3in1semia": "3in1semi", "mcheonru": None, "moremore": None, "moremorp": None,
        "4in1boot": None}
# per game (parent): button names, button 1 first.
#   snowbros, toto  Snow Bros.: button 1 throws snow, 2 jumps
#   hyperpac  the driver's own comments (934-936, 995-997): 1 jump, 2 fire
#   twinkle  the same comments on its port (unverified: copied with the port)
#   cookbib2, cookbib3, toppyrap  from a player (issue #2), against the driver's comments
#   suhosong  its PORT_NAMEs: B1 High, B2 Low, B3 Hit / Double Up, B4 Stand / Take, B6 Bet /
#             Raise; B5 is its start (Pandora.sv maps them)
#   finalttr  B1 and B2 both act at player select in MAME; named for a Tetris game's two rotations
#   pzlbreak  B1 launches the stage in MAME; B2 and B3 did nothing seen
#   3in1semi, mcheonru, moremore, 4in1boot  compilations: B1 selects in MAME's menu; no name
#             for what each button does across their games, so A and B
BUTTONS = {"snowbros": ["Shoot", "Jump"], "toto": ["Shoot", "Jump"],
           "hyperpac": ["Jump", "Fire"], "cookbib2": ["Fire", "Special"], "cookbib3": ["Fire", "Special"],
           "toppyrap": ["Fire", "Jump"], "twinkle": ["Jump", "Fire"],
           "suhosong": ["High", "Low", "Hit / Double Up", "Stand / Take", "Bet / Raise"],
           "finalttr": ["Rotate", "Rotate Back"], "pzlbreak": ["Launch"],
           "3in1semi": ["A", "B"], "mcheonru": ["A", "B"], "moremore": ["A", "B"],
           "moremorp": ["A", "B"], "4in1boot": ["A", "B"],
           "sutjarod": ["A", "B", "C"], "gwasu": ["A", "B", "C"], "yutnori": ["A", "B", "C"]}
# catver's genres (MiSTer-MAME-Coverage)
CATEGORY = {"snowbros": "Platform", "toto": "Platform", "hyperpac": "Maze",
            "cookbib2": "Puzzle", "cookbib3": "Puzzle", "finalttr": "Puzzle", "toppyrap": "Platform",
            "pzlbreak": "Puzzle", "suhosong": "Casino", "twinkle": "Maze", "3in1semi": "Compilation",
            "mcheonru": "Mini-Games", "moremore": "Mini-Games", "moremorp": "Mini-Games",
            "4in1boot": "Compilation", "sutjarod": "Puzzle", "gwasu": "Puzzle", "yutnori": "Puzzle"}

TOAPLAN_MACHINES = {"snowbros"}
SEMICOM_MACHINES = {"semicom", "semicom_mcu", "semiprot", "finalttr", "_4in1"}
YUTNORI_MACHINES = {"yutnori"}
# init functions that install a constant read (3218, 3250, 3261, 3323): (address, value)
CONST_READ = {"init_3in1semi": (0x200000, 0x000A), "init_cookbib3": (0x200000, 0x2A2A),
              "init_4in1boot": (0x200000, 0x0202), "init_toto": (0x500006, 0x0700)}
BG_PEN = {"init_pzlbreak": 0xC0}
# init functions that patch the program ROM (sutjarod and gwasu, both marked HACK in MAME; see
# docs/MAME_KLUDGES.md): their `rom[addr / 2] = value;` lines are read from the driver
ROM_PATCHED = {"init_sutjarod", "init_gwasu"}


def rom_patches(text, init):
    """The (byte address, 16-bit value) pairs an init writes into maincpu, in source order."""
    if init not in ROM_PATCHED:
        return []
    body = re.search(r"::" + init + r"\(\)\s*\{(.*?)\n\}", text, re.S).group(1)
    out = [(int(a, 16), int(v, 16)) for a, v in
           re.findall(r"rom\[\s*0x([0-9a-fA-F]+)\s*/\s*2\s*\]\s*=\s*0x([0-9a-fA-F]+)\s*;", body)]
    if not out:
        sys.exit(f"{init}: no ROM patches found")
    return out
# OSD lines are 28 columns (validate_mra.py): shorter names and settings, same meaning
SHORT_NAME = {"Show All Rights Reserved": "Rights Reserved",
              "Mini Game Frequency": "Mini Game"}
SHORT_SETTING = {"America (Romstar license)": "America (Romstar)",
                 "100k and every 200k": "100k+every 200k"}


def sdram_map():
    text = (REPO / "rtl" / "memory" / "snowbros_sdram_top.sv").read_text(encoding="utf-8")
    m = {k: int(v, 16) for k, v in re.findall(r"localparam logic \[24:0\] (\w+)\s*=\s*25'h([0-9a-fA-F]+);", text)}
    for k in ("MAINCPU_BASE", "GFX_BASE", "SOUND_BASE", "OKI_BASE", "MCU_BASE", "PROT_BASE", "ROM_END"):
        if k not in m:
            sys.exit(f"{k} missing from rtl/memory/snowbros_sdram_top.sv")
    return m


# region -> (map key, capacity). The MCU program is "protection" where dumped.
REGIONS = (("maincpu", "MAINCPU_BASE", 0x100000), ("gfx1", "GFX_BASE", 0x200000),
           ("soundcpu", "SOUND_BASE", 0x10000), ("oki1", "OKI_BASE", 0x40000),
           ("protection", "MCU_BASE", 0x2000), ("protdata", "PROT_BASE", 0x200))
# yutnori: its voice ROM (oki2) where the others keep oki1, its two-bank music ROM (oki1) past
# every other set's image; the image runs to YUT_END
YUT_REGIONS = (("maincpu", "MAINCPU_BASE", 0x100000), ("gfx1", "GFX_BASE", 0x200000),
               ("oki2", "OKI_BASE", 0x40000), ("oki1", "OKIM_BASE", 0x80000))


def game_info(text, setname):
    m = re.search(r"GAME\(\s*(\d+)\s*,\s*" + setname + r"\s*,[^\n]*", text)
    if not m:
        sys.exit(f"no GAME line for {setname}")
    f = [x.strip() for x in m.group(0).split("(", 1)[1].split(",")]
    q = re.findall(r'"([^"]*)"', m.group(0))
    return {"year": f[0], "machine": f[3], "ports": f[4], "init": f[6], "rot": int(f[7][3:]),
            "manufacturer": q[0], "title": q[1]}


def zips_for(setname):
    names = [setname + ".zip"] + ([SETS[setname] + ".zip"] if SETS[setname] else [])
    found = []
    for n in names:
        for d in [REPO / "roms"] + ROMDIRS:
            if (d / n).exists():
                found.append(d / n)
                break
    return names, found


def region_size(body, region):
    m = re.search(r'ROM_REGION\w*\(\s*(0x[0-9a-fA-F]+)\s*,\s*"' + re.escape(region) + '"', body)
    return int(m.group(1), 16) if m else 0


def pieces(records):
    """ROM_START records -> (kind, name, crc, file offset, dest, length), ROM_CONTINUE resolved."""
    out, last, foff = [], None, 0
    for kind, name, dest, length, crc, *rest in records:
        if kind == "continue":
            out.append(("load", last[0], last[1], foff, dest, length))
            foff += length
        elif crc is None:
            continue                          # NO_DUMP
        else:
            k = "load" if kind == "load16_wswap" else kind
            out.append((k, name, crc, 0, dest, length))
            last, foff = (name, crc), length
    return out


def load_region(zs, ps, size):
    out = bytearray(size)
    for kind, name, crc, foff, dest, length in ps:
        data = mra_lib._zip_read(zs, name, crc)[foff:foff + length]
        assert len(data) == length, (name, len(data), length)
        if kind == "load":
            out[dest:dest + length] = data
        elif kind == "load16_byte":
            out[dest:dest + 2 * length:2] = data
        else:
            sys.exit(f"record kind {kind} not handled")
    return bytes(out)


def switches(ports, setname, fake_flip):
    """<dip> lines: DSW1 is byte 0 (bits 0-7), DSW2 byte 1 (bits 8-15)."""
    edips.SRC = str(DRIVER)
    blocks = edips.load()
    missing = set()
    parsed = edips.parse_ports(blocks[ports], blocks, missing)
    if missing:
        sys.exit(f"{setname}: DEF_STR missing: {', '.join(sorted(missing))}")
    default, out = 0, []
    q = {chr(34): "&quot;"}
    for port, shift in (("DSW1", 0), ("DSW2", 8)):
        for name, mask, dflt, settings in parsed.get(port, []):
            default |= (dflt & 0xFF) << shift
            if settings is None:
                continue
            name = re.sub(r"\s*\(.*\)$", "", name)   # a PORT_CONDITION's choices; the labels carry them
            name = SHORT_NAME.get(name, name)
            pos = [i for i in range(8) if mask & (1 << i)]
            ids = []
            for idx in range(1 << len(pos)):
                v = sum(1 << b for j, b in enumerate(pos) if idx & (1 << j))
                lab = settings.get(v, "-")
                lab = "|".join(SHORT_SETTING.get(x, x) for x in lab.split("|"))
                if "," in lab:
                    sys.exit(f"{setname}: dip {name!r}: label {lab!r} contains a comma")
                ids.append(lab)
            bits = [p + shift for p in pos]
            out.append(f'        <dip name="{escape(name, q)}" bits="{bits[0]},{bits[-1]}" '
                       f'ids="{escape(",".join(ids), q)}"/>')
    if fake_flip:
        out += ["        <!-- not on the board: read by the core, not the game (Pandora.sv flip_osd) -->",
                '        <dip name="Flip Screen" bits="16,16" ids="Off,On"/>']
    return out, default


def active_high_inputs(ports):
    """True when the set's ports (or the ones it PORT_INCLUDEs) read the joystick active high."""
    text = DRIVER.read_text(encoding="utf-8", errors="replace")
    while True:
        m = re.search(r"INPUT_PORTS_START\(\s*" + re.escape(ports) + r"\s*\)(.*?)INPUT_PORTS_END", text, re.S)
        blk = m.group(1)
        j = re.search(r"PORT_BIT\([^)]*IP_ACTIVE_(HIGH|LOW)\s*,\s*IPT_(JOYSTICK_UP|BUTTON1)\b", blk)
        if j:
            return j.group(1) == "HIGH"
        inc = re.search(r"PORT_INCLUDE\(\s*(\w+)\s*\)", blk)
        if not inc:
            sys.exit(f"{ports}: no joystick or button port to take the polarity from")
        ports = inc.group(1)


def mod_bytes(info, setname, body):
    mc, init = info["machine"], info["init"]
    semi, yut = mc in SEMICOM_MACHINES, mc in YUTNORI_MACHINES
    b0 = (int(semi) | int(semi and mc != "finalttr") << 1 | int(semi) << 2
          | int((semi and mc != "_4in1") or yut) << 3 | int(setname == "toto") << 4
          | int(setname == "4in1boot") << 5 | int(mc == "semicom_mcu") << 6
          | int(mc in ("semiprot", "finalttr")) << 7)
    addr, val = CONST_READ.get(init, (0, 0))
    act_hi = active_high_inputs(info["ports"])
    b1 = (int(mc == "finalttr") | int(init in CONST_READ) << 1 | int(addr == 0x500006) << 2
          | int(init == "init_cookbib2") << 3 | int(act_hi) << 4 | int(info["ports"] == "suhosong") << 5
          | int(mc == "finalttr") << 6 | int(yut) << 7)
    ntiles = region_size(body, "gfx1") // 128
    bg = 0xF0 if yut else BG_PEN.get(init, 0)    # yutnori_state::machine_start
    return [b0, b1, val >> 8, val & 0xFF, bg, ntiles >> 8, ntiles & 0xFF, 0]


def build(setname, sm, out_root, write=True):
    text = DRIVER.read_text(encoding="utf-8", errors="replace")
    body = ers.blocks(text)[setname]
    info = game_info(text, setname)
    if info["machine"] not in TOAPLAN_MACHINES | SEMICOM_MACHINES | YUTNORI_MACHINES:
        sys.exit(f"{setname}: machine {info['machine']} is not in scope")
    parent = SETS[setname]
    names, paths = zips_for(setname)
    # a clone loads from its own zip or from the parent's merged one
    if not paths or not any(p.name == (parent or setname) + ".zip" for p in paths):
        print(f"{setname}: no {(parent or setname)}.zip found; skipped")
        return False
    zs = [zipfile.ZipFile(p) for p in paths]

    yut = info["machine"] in YUTNORI_MACHINES
    regions = YUT_REGIONS if yut else REGIONS
    img = bytearray(sm["YUT_END"] if yut else sm["ROM_END"])
    ps, data = {}, {}
    for region, key, cap in regions:
        recs, unknown = ers.region_records(body, region)
        if unknown:
            sys.exit(f"{setname}: region {region}: unparsed {unknown}")
        ps[region] = pieces(recs)
        size = min(region_size(body, region), cap) if ps[region] else 0
        assert all(p[4] + (2 * p[5] - 1 if p[0] == "load16_byte" else p[5]) <= cap for p in ps[region]), (setname, region)
        data[region] = load_region(zs, ps[region], size)
        img[sm[key]:sm[key] + size] = data[region]
    # MAME's u16 region is the 68000's view, so a value is its high byte then its low byte
    patches = rom_patches(text, info["init"])
    for a, v in patches:
        img[sm["MAINCPU_BASE"] + a:sm["MAINCPU_BASE"] + a + 2] = bytes((v >> 8, v & 0xFF))
    img = bytes(img)

    L, pos = [], 0

    def pad_to(addr, why):
        nonlocal pos
        if addr > pos:
            L.append(f'        <part repeat="0x{addr - pos:X}">00</part>  <!-- {why} -->')
            pos = addr
        assert pos == addr, (why, hex(pos), hex(addr))

    for region, key, cap in regions:
        base, rp = sm[key], sorted(ps[region], key=lambda p: p[4])
        if not rp:
            continue
        pad_to(base, f"{region} at 0x{base:X}")
        L.append(f"        <!-- {region} -->")
        kinds = {p[0] for p in rp}
        if kinds == {"load"}:
            for kind, name, crc, foff, dest, length in rp:
                pad_to(base + dest, f"{region} 0x{dest:x}")
                whole = foff == 0 and length == len(mra_lib._zip_read(zs, name, crc))
                extra = "" if whole else f' offset="0x{foff:X}" length="0x{length:X}"'
                L.append(f'        <part name="{escape(name)}" crc="{crc:08x}"{extra}/>')
                pos += length
        elif kinds == {"load16_byte"}:
            for i in range(0, len(rp), 2):
                grp = rp[i:i + 2]
                start, length = grp[0][4] - grp[0][4] % 2, grp[0][5]
                assert all(p[5] == length for p in grp) and sorted(p[4] - start for p in grp) == [0, 1], grp
                pad_to(base + start, f"{region} 0x{start:x}")
                want = data[region][start:start + 2 * length]
                raws = [mra_lib._zip_read(zs, p[1], p[2]) for p in grp]
                maps = ["10", "01"]
                chosen = next((m for m in itertools.permutations(maps)
                               if mra_lib.interleave(list(zip(raws, m)), 16) == want), None)
                if not chosen:
                    sys.exit(f"{setname}: no interleave map reproduces {region} 0x{start:x}")
                L.append('        <interleave output="16">')
                for p, mp in zip(grp, chosen):
                    L.append(f'            <part name="{escape(p[1])}" crc="{p[2]:08x}" map="{mp}"/>')
                L.append("        </interleave>")
                pos += 2 * length
        else:
            sys.exit(f"{setname}: {region}: mixed record kinds {kinds}")
    pad_to(len(img), "image end")
    for a, v in patches:
        L.append(f'        <patch offset="0x{sm["MAINCPU_BASE"] + a:X}">{v >> 8:02X} {v & 0xFF:02X}</patch>  <!-- {info["init"]} -->')

    mods = mod_bytes(info, setname, body)
    game = BUTTONS[parent or setname]
    btn_names = ",".join(game + ["-"] * (6 - len(game)) + ["Start", "Coin", "Pause"])
    btn_default = ",".join(["A", "B", "X", "Y", "L"][:len(game)] + ["Start", "Select", "R"])
    sw, sw_def = switches(info["ports"], setname, fake_flip=info["machine"] in SEMICOM_MACHINES)
    q = {chr(34): "&quot;"}
    xml = [
        "<misterromdescription>",
        "    <!-- Generated by scripts/build_mra.py from MAME snowbros.cpp; the layout is",
        "         rtl/memory/snowbros_sdram_top.sv. Do not edit by hand. -->",
        '    <about author="Paul Priest" webpage="" source="MAME snowbros.cpp"/>',
        f"    <name>{escape(info['title'])}</name>",
        f"    <setname>{setname}</setname>",
        "    <rbf>Pandora</rbf>",   # not SnowBros: scripts/deploy.py RBF_STEM
        f"    <mameversion>{mame_version()}</mameversion>",
        f"    <year>{info['year']}</year>",
        f"    <manufacturer>{escape(info['manufacturer'])}</manufacturer>",
        f"    <category>{CATEGORY[parent or setname]}</category>",
        "    <rotation>horizontal</rotation>",
        "    <players>2</players>",
        "    <joystick>8-way</joystick>",
        f'    <buttons names="{escape(btn_names, q)}" default="{btn_default}" count="{len(game)}"/>',
        "",
        "    <!-- mod bytes (Pandora.sv) -->",
        f'    <rom index="1"><part>{" ".join(f"{b:02X}" for b in mods)}</part></rom>',
        "",
        "    <!-- address: the HPS puts the image in DDR3 and the core copies it to SDRAM (rtl/memory/rom_loader.sv) -->",
        f'    <rom index="0" zip="{"|".join(names)}" md5="none" address="0x30000000">',
        *L,
        "    </rom>",
        "",
        f'    <switches default="{sw_def & 0xff:02X},{sw_def >> 8:02X},00">',
        *sw,
        "    </switches>",
        "</misterromdescription>",
        "",
    ]

    def safe(t):
        return re.sub(r'[\\/:*?"<>|]', "-", t)
    odir = (out_root / "_alternatives" / ("_" + safe(game_info(text, parent)["title"]))) if parent else out_root
    fname = odir / (safe(info["title"]) + ".mra")
    odir.mkdir(parents=True, exist_ok=True)
    tmp = fname.with_suffix(".mra.tmp")
    tmp.write_text("\n".join(xml), encoding="utf-8", newline="\n")
    got = mra_lib.build_image(str(tmp), [str(p) for p in paths])
    for z in zs:
        z.close()
    if got != img:
        diff = next((i for i in range(min(len(got), len(img))) if got[i] != img[i]), min(len(got), len(img)))
        tmp.unlink()
        sys.exit(f"{setname}: the .mra image differs from the ROM_START image at 0x{diff:x} "
                 f"({len(got)} vs {len(img)} bytes)")
    if write:
        tmp.replace(fname)
        print(f"{setname}: {fname.relative_to(REPO)}, image {len(img)} bytes, identical to ROM_START")
    else:
        tmp.unlink()
        print(f"{setname}: image {len(img)} bytes, identical to ROM_START (not written)")
    return img


def mame_version():
    exe = Path(setting("MAME_DIR") or "C:/Emulation/Emulators/MAME") / (setting("MAME_EXE") or "mame.exe")
    out = subprocess.run([str(exe), "-version"], capture_output=True, text=True, timeout=30).stdout
    m = re.match(r"\s*0\.(\d+)", out)
    if not m:
        sys.exit(f"cannot read the MAME version from {exe}")
    return "%04d" % int(m.group(1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sets", nargs="*")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--release", action="store_true", help="write to releases/ instead of releases/_dev/")
    ap.add_argument("--image", nargs=2, metavar=("SET", "OUT"))
    a = ap.parse_args()
    sm = sdram_map()
    out_root = REPO / "releases" / ("" if a.release else "_dev")
    if a.image:
        img = build(a.image[0], sm, out_root, write=False)
        if img is False:
            return 1
        Path(a.image[1]).write_bytes(img)
        print(f"wrote {a.image[1]}")
        return 0
    for s in a.sets or list(SETS):
        if s not in SETS:
            sys.exit(f"unknown set {s}")
        build(s, sm, out_root, write=not a.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
