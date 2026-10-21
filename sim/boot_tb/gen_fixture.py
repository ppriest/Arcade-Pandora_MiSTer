#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Program ROM fixture for sim/boot_tb, built from the driver's ROM_START and the set's zip.

    python sim/boot_tb/gen_fixture.py <set>    # from the repository root
    -> sim/boot_tb/maincpu.hex   512K 16-bit words, big-endian (the 68000's view); not committed

Files are found by CRC across the set's zip and its parent's. Handles ROM_LOAD16_BYTE, the
form every in-scope set's maincpu uses. toto's and 4in1boot's bit swaps are applied as
init_toto and init_4in1boot do (4in1boot's `i & 1` is the high byte here: MAME's region is
byte-swapped onto a little-endian host), and sutjarod's and gwasu's ROM patches.
"""
import sys
import zipfile
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import extract_romstart as er  # noqa: E402
from coretools import setting  # noqa: E402


def zip_files(game):
    files = {}
    for root in (setting("MAME_ROMPATH") or "").split(";"):
        z = Path(root) / f"{game}.zip"
        if z.exists():
            with zipfile.ZipFile(z) as zf:
                for n in zf.namelist():
                    d = zf.read(n)
                    files[zlib.crc32(d)] = d
    return files


def main():
    game = sys.argv[1]
    text = Path(er.SRC).read_text(encoding="utf-8", errors="replace")
    recs, unknown = er.region_records(er.blocks(text)[game], "maincpu")
    if unknown:
        sys.exit(f"unparsed maincpu records: {unknown}")
    files = zip_files(game)
    img = bytearray(0x100000)
    for kind, name, dest, length, crc in (r[:5] for r in recs):
        if kind != "load16_byte":
            sys.exit(f"{name}: {kind} not handled")
        d = files.get(crc)
        if d is None:
            sys.exit(f"{name} (CRC {crc:08x}) not in {game}.zip")
        img[dest:dest + 2 * length:2] = d[:length]
    # init_sutjarod's and init_gwasu's ROM patches, as the .mra applies them (scripts/build_mra.py)
    import build_mra
    init = build_mra.game_info(text, game)["init"]
    for addr, v in build_mra.rom_patches(text, init):
        img[addr:addr + 2] = bytes((v >> 8, v & 0xFF))
    if game == "toto":
        img = bytearray((b & 0xE7) | (b >> 1 & 0x08) | (b << 1 & 0x10) for b in img)
    if game == "4in1boot":
        img[0::2] = bytes((b & 0x3F) | (b >> 1 & 0x40) | (b << 1 & 0x80) for b in img[0::2])
    out = REPO / "sim" / "boot_tb" / "maincpu.hex"
    out.write_text("".join(f"{img[i]:02x}{img[i + 1]:02x}\n" for i in range(0, len(img), 2)))
    print(f"{game}: {len(recs)} files -> {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
