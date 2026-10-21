#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prove the SemiCom-to-Toaplan graphics reorder against MAME's two gfx_layouts.

    python scripts/gfx_layout_check.py [--set hyperpac]

Both layouts are transcribed from MAME: gfx_8x8x4_row_2x2_group_packed_msb
(src/emu/video/generic.cpp:150-159) and hyperpac_tilelayout (snowbros.cpp:1869-1880).
Checks, in order:

  1. every bit of a 128-byte tile is used exactly once by each layout;
  2. each pixel's four plane bits are one nibble, MSB first, in both, so the reorder is a
     nibble permutation;
  3. the permutation, printed as a function of the nibble index's bits;
  4. every tile of the set's gfx1, reordered by the permutation, decodes through the Toaplan
     layout to the same pixels as the original through the SemiCom layout.

The core stores every set's graphics row-linear (to_linear): tile t, row r at byte
t*128 + r*8, eight bytes of two pixels, the left pixel in the high nibble, so one 64-bit
granule is one tile row (rtl/video/pandora_rom.sv). The download reorders with the
permutation to_linear computes; sim/video_tb takes its fixture from it.
"""
import argparse
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coretools import setting  # noqa: E402


def step(start, inc, n):
    return [start + inc * i for i in range(n)]


TOAPLAN = {
    "planes": step(0, 1, 4),
    "x": step(0, 4, 8) + step(4 * 8 * 8, 4, 8),
    "y": step(0, 4 * 8, 8) + step(4 * 8 * 8 * 2, 4 * 8, 8),
}
SEMICOM = {
    "planes": [0, 1, 2, 3],
    "x": [4, 0, 8*32+4, 8*32+0, 20, 16, 8*32+20, 8*32+16,
          12, 8, 8*32+12, 8*32+8, 28, 24, 8*32+28, 8*32+24],
    "y": [0*32, 2*32, 1*32, 3*32, 16*32+0*32, 16*32+2*32, 16*32+1*32, 16*32+3*32,
          4*32, 6*32, 5*32, 7*32, 16*32+4*32, 16*32+6*32, 16*32+5*32, 16*32+7*32],
}
TILE_BITS = 1024

# gfx1 files of each set, in load order (snowbros.cpp ROM_START blocks)
GFX1 = {
    "hyperpac": ["hyperpac.a4", "hyperpac.a5", "hyperpac.a6"],
    "cookbib2": ["unico_05.ua4", "unico_04.ua5", "unico_03.ua6"],
}


def bit_offsets(lay, x, y):
    return [lay["planes"][p] + lay["x"][x] + lay["y"][y] for p in range(4)]


def nibble_of(lay, x, y):
    offs = bit_offsets(lay, x, y)
    if offs[0] % 4 or offs != step(offs[0], 1, 4):
        sys.exit(f"pixel ({x},{y}) is not one MSB-first nibble: {offs}")
    return offs[0] // 4


def check_coverage(name, lay):
    seen = [0] * TILE_BITS
    for y in range(16):
        for x in range(16):
            for b in bit_offsets(lay, x, y):
                seen[b] += 1
    if any(c != 1 for c in seen):
        sys.exit(f"{name}: bits not used exactly once")
    print(f"1. {name}: all {TILE_BITS} bits used exactly once")


def decode(data, base, lay):
    px = []
    for y in range(16):
        for x in range(16):
            pen = 0
            for b in bit_offsets(lay, x, y):
                bit = (data[base + (b >> 3)] >> (7 - (b & 7))) & 1
                pen = (pen << 1) | bit
            px.append(pen)
    return px


def to_linear(gfx, lay):
    """gfx in layout `lay` -> row-linear bytes."""
    import numpy as np
    perm = [0] * 256                   # perm[source nibble] = row-linear nibble
    for y in range(16):
        for x in range(16):
            perm[nibble_of(lay, x, y)] = y * 16 + x
    n = len(gfx) // 128
    raw = np.frombuffer(gfx[:n * 128], dtype=np.uint8).reshape(n, 128)
    src = np.empty((n, 256), dtype=np.uint8)
    src[:, 0::2] = raw >> 4
    src[:, 1::2] = raw & 0xF
    dst = np.empty_like(src)
    dst[:, perm] = src
    return ((dst[:, 0::2] << 4) | dst[:, 1::2]).astype(np.uint8).tobytes()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", default="hyperpac", choices=sorted(GFX1))
    a = ap.parse_args()

    check_coverage("Toaplan", TOAPLAN)
    check_coverage("SemiCom", SEMICOM)

    # perm[semicom nibble] = toaplan nibble, for the same pixel
    perm = [None] * 256
    for y in range(16):
        for x in range(16):
            perm[nibble_of(SEMICOM, x, y)] = nibble_of(TOAPLAN, x, y)
    print("2. both layouts: one MSB-first nibble per pixel")

    # Express the permutation as a mapping of nibble-index bits, if it is one.
    bitmap = {}
    for sb in range(8):
        img = perm[1 << sb] ^ perm[0]
        if bin(img).count("1") != 1:
            sys.exit(f"permutation is not a bit permutation (SemiCom bit {sb} -> {img:08b})")
        bitmap[sb] = img.bit_length() - 1
    for n in range(256):
        t = perm[0]
        for sb in range(8):
            if n >> sb & 1:
                t ^= 1 << bitmap[sb]
        if t != perm[n]:
            sys.exit("permutation is not linear in the nibble-index bits")
    print(f"3. Toaplan nibble index = SemiCom nibble index with bits permuted, constant {perm[0]:#04x}:")
    print("   " + ", ".join(f"S{sb}->T{bitmap[sb]}" for sb in range(8)))
    print("   (nibble index bit 0 selects the high (0) or low (1) nibble of a byte)")

    roms = [Path(p) for p in (setting("MAME_ROMPATH") or "").split(";") if p]
    data = None
    for root in roms:
        z = root / f"{a.set}.zip"
        if z.exists():
            with zipfile.ZipFile(z) as zf:
                names = {Path(n).name.lower(): n for n in zf.namelist()}
                data = b"".join(zf.read(names[f]) for f in GFX1[a.set])
            break
    if data is None:
        sys.exit(f"{a.set}.zip not found in MAME_ROMPATH")
    ntiles = len(data) // 128
    out = bytearray(len(data))
    for t in range(ntiles):
        base = t * 128
        for n in range(256):
            src = data[base + (n >> 1)] >> (0 if n & 1 else 4) & 0xF
            d = perm[n]
            out[base + (d >> 1)] |= src << (0 if d & 1 else 4)
    bad = sum(decode(data, t * 128, SEMICOM) != decode(out, t * 128, TOAPLAN) for t in range(ntiles))
    print(f"4. {a.set}: {ntiles - bad} of {ntiles} tiles decode identically after the reorder")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
