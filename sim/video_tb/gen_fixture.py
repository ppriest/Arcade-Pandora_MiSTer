#!/usr/bin/env python3
"""Fixtures for sim/video_tb from a MAME capture (scripts/mame_vcapture.py).

    python sim/video_tb/gen_fixture.py debug/snowbros-v/00700      # from the repository root
    -> sim/video_tb/{spr,pal,cfg,gfx}.hex (not committed)

spr.hex is spriteram_prev.bin: the list MAME drew the captured frame from
(scripts/render_model.py). gfx.hex is gfx1 row-linear, one 64-bit granule a line, byte k of
the granule in bits 8k+7:8k. cfg.hex: flip, bg_pen, tile count.
"""
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import gfx_layout_check as gl  # noqa: E402
import render_model as rm  # noqa: E402

cache = {}


def main():
    d = Path(sys.argv[1])
    game = d.parent.name.split("-v")[0]
    out = REPO / "sim" / "video_tb"
    spr = (d / "spriteram_prev.bin").read_bytes()
    (out / "spr.hex").write_text("".join(f"{x:02x}\n" for x in spr))
    pal = np.frombuffer((d / "palette.bin").read_bytes(), dtype=">u2")
    (out / "pal.hex").write_text("".join(f"{int(x):04x}\n" for x in pal))
    flip = 0 if game not in rm.FLIP_SETS or int((d / "flip.txt").read_text()) & 0x80 else 1
    gfx = rm.load_gfx(game)
    lay = gl.TOAPLAN if game in rm.TOAPLAN_LAYOUT_SETS else gl.SEMICOM
    lin = gl.to_linear(gfx, lay)
    ntiles = len(lin) // 128
    (out / "cfg.hex").write_text(f"{flip:04x}\n{rm.BG_PEN.get(game, 0):04x}\n{ntiles:04x}\n")
    g = np.frombuffer(lin, dtype="<u8")
    (out / "gfx.hex").write_text("".join(f"{int(x):016x}\n" for x in g))
    print(f"{d}: flip {flip}, bg_pen {rm.BG_PEN.get(game, 0):#x}, {ntiles} tiles")


if __name__ == "__main__":
    main()
