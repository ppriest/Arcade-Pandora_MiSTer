#!/usr/bin/env python3
"""Fixture for sim/mcu_tb: dreamwld's MCU ROM as $readmemh text.

    python sim/mcu_tb/gen_fixture.py      # from the repository root
    -> sim/mcu_tb/mcu.hex                 (8192 lines, not committed)

Read from dreamwld.zip in MAME_ROMPATH by CRC (87c51rap.bin, 987bbfe8).
"""
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
from coretools import load_env  # noqa: E402

CRC = 0x987BBFE8


def main():
    paths = load_env().get("MAME_ROMPATH", "").split(";")
    for d in paths:
        zp = Path(d.strip()) / "dreamwld.zip"
        if zp.exists():
            break
    else:
        sys.exit("dreamwld.zip not found in MAME_ROMPATH")
    z = zipfile.ZipFile(zp)
    info = next(i for i in z.infolist() if i.CRC == CRC)
    rom = z.read(info)
    out = REPO / "sim" / "mcu_tb" / "mcu.hex"
    out.write_text("".join(f"{b:02x}\n" for b in rom))
    print(f"wrote {len(rom)} bytes from {zp.name}:{info.filename} to {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
