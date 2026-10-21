#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Software model of the Pandora board's picture, checked against MAME's screenshots.

    python scripts/render_model.py <capture dir> [...]       e.g. debug/snowbros-v/00700
    python scripts/render_model.py debug/snowbros-v*/*        every capture of a set
    python scripts/render_model.py <dir> --list prev          draw spriteram_prev.bin instead
    python scripts/render_model.py <dir> --toaplan-gfx        SemiCom graphics reordered first

Transcribed from MAME: kan_pand.cpp draw() (130-201) and eof() (203-211), snowbros.cpp
screen_update (102-108), the xBGR_555 palette, the visible area rows 16-239 (1948). Writes
model.png beside reference.png and prints the pixels that differ.

The model is the reference the RTL is checked against (sim/video_tb): render() returns the
256 x 224 picture as palette indices, so the RTL's line buffer output compares before colour.
"""
import argparse
import sys
import zipfile
import zlib
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import extract_romstart as er  # noqa: E402
import gfx_layout_check as gl  # noqa: E402
from coretools import setting  # noqa: E402

# snowbros_map is the only map with the flip register (0x400000, snowbros.cpp 189); a write
# there on the other maps is unmapped and leaves the Pandora unflipped.
FLIP_SETS = {"snowbros", "snowbrosa", "snowbrosb", "snowbrosc", "snowbrosj", "snowbrosd", "toto"}
TOAPLAN_LAYOUT_SETS = {"snowbros", "snowbrosa", "snowbrosb", "snowbrosc", "snowbrosj",
                       "snowbrosd", "toto", "4in1boot"}
BG_PEN = {"pzlbreak": 0xC0, "pzlbreaka": 0xC0,     # init_pzlbreak (3290)
          "yutnori": 0xF0}                          # yutnori_state::machine_start
VIS_Y0, VIS_H = 16, 224


def nibble_table(lay):
    """(y, x) -> nibble index within a 128-byte tile."""
    t = np.zeros((16, 16), dtype=np.int32)
    for y in range(16):
        for x in range(16):
            t[y, x] = gl.nibble_of(lay, x, y)
    return t


def load_gfx(game):
    text = Path(er.SRC).read_text(encoding="utf-8", errors="replace")
    recs, unknown = er.region_records(er.blocks(text)[game], "gfx1")
    if unknown:
        sys.exit(f"{game}: unparsed gfx1 records {unknown}")
    files = {}
    for root in (setting("MAME_ROMPATH") or "").split(";"):
        for z in (Path(root) / f"{game}.zip",):
            if z.exists():
                with zipfile.ZipFile(z) as zf:
                    for n in zf.namelist():
                        d = zf.read(n)
                        files[zlib.crc32(d)] = d
    size = max(r[2] + r[3] for r in recs)
    img = bytearray(size)
    for kind, name, dest, length, crc in (r[:5] for r in recs):
        if kind != "load":
            sys.exit(f"{game}: gfx1 {name} is {kind}")
        img[dest:dest + length] = files[crc][:length]
    return bytes(img)


def decode_tiles(gfx, lay):
    """(ntiles, 16, 16) pens."""
    n = len(gfx) // 128
    raw = np.frombuffer(gfx[:n * 128], dtype=np.uint8).reshape(n, 128)
    nib = np.empty((n, 256), dtype=np.uint8)
    nib[:, 0::2] = raw >> 4
    nib[:, 1::2] = raw & 0xF
    return nib[:, nibble_table(lay)]


def sext9(v):
    v &= 0x1FF
    return v - 0x200 if v & 0x100 else v


def render(spr, tiles, flip, bg_pen=0):
    """The 256 x 224 visible picture as 8-bit palette indices."""
    bm = np.full((256, 256), bg_pen, dtype=np.int32)     # eof(): the cleared bitmap
    x = y = 0
    ntiles = tiles.shape[0]
    for offs in range(0, 0x1000, 8):
        dx, dy, col, attr = spr[offs + 4], spr[offs + 5], spr[offs + 3], spr[offs + 7]
        fx, fy = attr >> 7 & 1, attr >> 6 & 1
        tile = ((attr & 0x3F) << 8) + spr[offs + 6]
        if col & 1:
            dx |= 0x100
        if col & 2:
            dy |= 0x100
        if col & 4:
            x += dx
            y += dy
        else:
            x, y = dx, dy
        sx, sy = x, y
        if flip:
            sx, sy = 240 - sx, 240 - sy
            fx, fy = fx ^ 1, fy ^ 1
        sx, sy = sext9(sx), sext9(sy)
        t = tiles[tile % ntiles]            # gfx_element wraps the code at the element count
        if fx:
            t = t[:, ::-1]
        if fy:
            t = t[::-1, :]
        x0, x1 = max(0, sx), min(256, sx + 16)
        y0, y1 = max(0, sy), min(256, sy + 16)
        if x0 >= x1 or y0 >= y1:
            continue
        src = t[y0 - sy:y1 - sy, x0 - sx:x1 - sx].astype(np.int32)
        dst = bm[y0:y1, x0:x1]
        np.copyto(dst, ((col >> 4) << 4) | src, where=src != 0)
    vis = bm[VIS_Y0:VIS_Y0 + VIS_H]
    return np.where(vis != 0, vis, 0xF0)               # screen_update: fill 0xF0, copy pen != 0


def palette_rgb(pal_words):
    w = np.array(pal_words, dtype=np.int32)
    def ex(v): return (v << 3) | (v >> 2)
    return np.stack([ex(w & 31), ex(w >> 5 & 31), ex(w >> 10 & 31)], axis=1).astype(np.uint8)


def check(d, which, toaplan_gfx, cache):
    d = Path(d)
    game = d.parent.name.split("-v")[0]
    if game not in cache:
        gfx = load_gfx(game)
        lay = gl.TOAPLAN if game in TOAPLAN_LAYOUT_SETS else gl.SEMICOM
        if toaplan_gfx and lay is gl.SEMICOM:
            gfx = reorder_semicom(gfx)
            lay = gl.TOAPLAN
        cache[game] = decode_tiles(gfx, lay)
    tiles = cache[game]
    spr = (d / ("spriteram_prev.bin" if which == "prev" else "spriteram.bin")).read_bytes()
    pal = np.frombuffer((d / "palette.bin").read_bytes(), dtype=">u2")
    flip = 0 if game not in FLIP_SETS or int((d / "flip.txt").read_text()) & 0x80 else 1
    idx = render(spr, tiles, flip, BG_PEN.get(game, 0))
    rgb = palette_rgb(pal)[idx]
    Image.fromarray(rgb, "RGB").save(d / "model.png")
    ref = np.asarray(Image.open(d / "reference.png").convert("RGB"))
    if ref.shape != rgb.shape:
        print(f"{d}: reference {ref.shape}, model {rgb.shape}")
        return 1
    bad = np.argwhere(np.any(ref != rgb, axis=2))
    print(f"{d}: {len(bad)} of {224 * 256} pixels differ" +
          (f", first at y={bad[0][0]} x={bad[0][1]}" if len(bad) else ""))
    return 1 if len(bad) else 0


def reorder_semicom(gfx):
    """The download's reorder (gfx_layout_check.py): SemiCom nibble order to Toaplan's."""
    perm = [0] * 256
    for y in range(16):
        for x in range(16):
            perm[gl.nibble_of(gl.SEMICOM, x, y)] = gl.nibble_of(gl.TOAPLAN, x, y)
    n = len(gfx) // 128
    raw = np.frombuffer(gfx[:n * 128], dtype=np.uint8).reshape(n, 128)
    src = np.empty((n, 256), dtype=np.uint8)
    src[:, 0::2] = raw >> 4
    src[:, 1::2] = raw & 0xF
    dst = np.empty_like(src)
    dst[:, perm] = src
    out = (dst[:, 0::2] << 4) | dst[:, 1::2]
    return out.astype(np.uint8).tobytes() + gfx[n * 128:]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--list", choices=["prev", "cur"], default="prev")
    ap.add_argument("--toaplan-gfx", action="store_true")
    a = ap.parse_args()
    cache, rc = {}, 0
    for d in a.dirs:
        rc |= check(d, a.list, a.toaplan_gfx, cache)
    return rc


if __name__ == "__main__":
    sys.exit(main())
