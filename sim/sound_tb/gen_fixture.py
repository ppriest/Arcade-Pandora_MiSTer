#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixtures for sim/sound_tb from a set's .mra image and its MAME sound trace.

    python sim/sound_tb/gen_fixture.py snowbros     # from the repository root
    -> sim/sound_tb/z80.hex (64 KB), oki.hex (256 KB), latch.txt ("<ns> <byte>" a line)
    (not committed)
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import build_mra  # noqa: E402


def main():
    game = sys.argv[1]
    out = REPO / "sim" / "sound_tb"
    sm = build_mra.sdram_map()
    img = build_mra.build(game, sm, REPO / "releases" / "_dev", write=False)
    z = img[sm["SOUND_BASE"]:sm["SOUND_BASE"] + 0x10000]
    o = img[sm["OKI_BASE"]:sm["OKI_BASE"] + 0x40000]
    (out / "z80.hex").write_text("".join(f"{x:02x}\n" for x in z))
    (out / "oki.hex").write_text("".join(f"{x:02x}\n" for x in o))
    lat = [l.split() for l in (REPO / "debug" / f"{game}-snd" / "mame.txt").read_text().splitlines()]
    (out / "latch.txt").write_text("".join(f"{f[0]} {f[2]}\n" for f in lat if len(f) == 3 and f[1] == "L"))
    print(f"{game}: z80.hex, oki.hex, latch.txt in {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
