#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixtures for sim/yut_tb: yutnori's two sample ROMs and MAME's command bytes.

    python sim/yut_tb/gen_fixture.py      # from the repository root
    -> sim/yut_tb/music.hex  oki1, 512 KB (two banks)    sim/yut_tb/voice.hex  oki2, 256 KB
       sim/yut_tb/cmds.txt   "<ns> <byte>" per command in debug/yutnori-snd/mame.txt
    (not committed)
"""
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
from coretools import setting  # noqa: E402

FILES = {"music.hex": ("sound rom", 0x80000), "voice.hex": ("voice_rom", 0x40000)}


def roms():
    for root in setting("MAME_ROMPATH").split(";"):
        z = Path(root) / "yutnori.zip"
        if z.exists():
            with zipfile.ZipFile(z) as zf:
                return {n: zf.read(n) for n in zf.namelist()}
    sys.exit("yutnori.zip not found")


def main():
    out, files = REPO / "sim" / "yut_tb", roms()
    for hexname, (name, size) in FILES.items():
        d = files[name]
        assert len(d) == size, (name, len(d))
        (out / hexname).write_text("".join(f"{b:02x}\n" for b in d))
    cmds = [l.split() for l in (REPO / "debug" / "yutnori-snd" / "mame.txt").read_text().splitlines()]
    cmds = [f"{c[0]} {c[2]}\n" for c in cmds if c[1] == "C"]
    (out / "cmds.txt").write_text("".join(cmds))
    print(f"yutnori: {len(cmds)} commands, ROMs -> {out}")


if __name__ == "__main__":
    main()
