#!/usr/bin/env python3
"""Fixtures for sim/top_tb from a set's .mra image (scripts/build_mra.py --image).

    python sim/top_tb/gen_fixture.py snowbros       # from the repository root
    -> sim/top_tb/image.hex     the image, a byte a line
       sim/top_tb/segs.txt      "start length" of each region the bench downloads (the rest is 0)
       sim/top_tb/expect.hex    the SDRAM after the download, 16-bit words of the same regions,
                                with the core's transforms (rtl/memory/dl_xform.sv) applied here
                                independently: row-linear graphics (gfx_layout_check.to_linear),
                                toto's and 4in1boot's swaps
       sim/top_tb/cfg.txt       the mod bytes from the .mra, hex
    (not committed)
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import build_mra  # noqa: E402
import gfx_layout_check as gl  # noqa: E402


def swap34(b):
    return (b & 0xE7) | ((b >> 1) & 0x08) | ((b << 1) & 0x10)


def main():
    game = sys.argv[1]
    out = REPO / "sim" / "top_tb"
    sm = build_mra.sdram_map()
    img = bytearray(build_mra.build(game, sm, REPO / "releases" / "_dev", write=True))
    mra = next(p for p in (REPO / "releases" / "_dev").rglob("*.mra")
               if f"<setname>{game}</setname>" in p.read_text(encoding="utf-8"))
    mods = re.search(r'<rom index="1"><part>([0-9A-F ]+)</part>', mra.read_text(encoding="utf-8")).group(1).split()
    m0 = int(mods[0], 16)
    semi_gfx, toto, x4 = m0 >> 3 & 1, m0 >> 4 & 1, m0 >> 5 & 1

    regions = [(sm["MAINCPU_BASE"], 0x100000), (sm["GFX_BASE"], 0x200000), (sm["SOUND_BASE"], 0x10000),
               (sm["OKI_BASE"], 0x40000), (sm["MCU_BASE"], 0x2000), (sm["PROT_BASE"], 0x200),
               (sm["OKIM_BASE"], 0x80000)]
    img += bytes(sm["YUT_END"] - len(img))      # every image as long as yutnori's
    segs = []
    for base, cap in regions:
        used = max((i for i in range(cap) if img[base + i]), default=-1) + 1
        if used:
            segs.append((base, (used + 1) & ~1))
    exp = bytearray(img)
    b, n = sm["MAINCPU_BASE"], 0x100000
    for i in range(n):
        v = exp[b + i]
        if toto: v = swap34(v)
        if x4 and not i & 1: v = (v & 0x3F) | (v >> 1 & 0x40) | (v << 1 & 0x80)
        exp[b + i] = v
    g = bytes(swap34(x) for x in img[sm["GFX_BASE"]:sm["GFX_BASE"] + 0x200000]) if toto else \
        bytes(img[sm["GFX_BASE"]:sm["GFX_BASE"] + 0x200000])
    exp[sm["GFX_BASE"]:sm["GFX_BASE"] + 0x200000] = gl.to_linear(g, gl.SEMICOM if semi_gfx else gl.TOAPLAN)
    s = bytes(img[sm["SOUND_BASE"]:sm["SOUND_BASE"] + 0x10000])
    if toto: s = bytes(swap34(x) for x in s)
    if x4: s = bytes(s[i ^ 0x4000] for i in range(len(s)))
    exp[sm["SOUND_BASE"]:sm["SOUND_BASE"] + 0x10000] = s

    with open(out / "image.hex", "w") as f:
        f.write("".join(f"{x:02x}\n" for x in img))
    with open(out / "expect.hex", "w") as f:
        f.write("".join(f"{exp[i] | exp[i + 1] << 8:04x}\n" for i in range(0, len(exp), 2)))
    (out / "segs.txt").write_text("".join(f"{a:x} {l:x}\n" for a, l in segs))
    (out / "cfg.txt").write_text(" ".join(mods) + "\n")
    print(f"{game}: {len(segs)} segments, {sum(l for _, l in segs)} bytes; mods {' '.join(mods)}")


if __name__ == "__main__":
    main()
