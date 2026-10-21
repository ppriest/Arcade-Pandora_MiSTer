#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Capture frames from MAME for the Pandora model (scripts/mame/vcapture.lua).

    python scripts/mame_vcapture.py <set> --frames 700,900,1100 [--coin 600] [--tag _play]
    python scripts/mame_vcapture.py snowbros --frames 700 --dip 'Flip Screen=On' --tag _flip
    -> debug/<set>-v<tag>/<frame>/{spriteram_prev,spriteram}.bin, palette.bin, flip.txt,
       reference.png
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import NO_WINDOW, lua_runner_env, mame_cmd, mame_paths, seed_dips  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("--frames", required=True)
    ap.add_argument("--coin", type=int, default=0)
    ap.add_argument("--tag", default="")
    ap.add_argument("--dip", action="append", default=[], metavar="NAME=SETTING")
    a = ap.parse_args()
    mame_dir, exe = mame_paths()
    out = REPO / "debug" / f"{a.set}-v{a.tag}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    env = dict(os.environ, **lua_runner_env("vcapture.lua"), VC_OUT=out.as_posix(),
               VC_FRAMES=a.frames, VC_COIN=str(a.coin))
    extra = ["-snapview", "native"]
    if a.dip:
        extra += ["-cfg_directory", seed_dips(exe, mame_dir, a.set, a.dip, out).as_posix()]
    cmd = mame_cmd(exe, a.set, "vcapture.lua", mame_dir, extra)
    r = subprocess.run(cmd, cwd=str(mame_dir), env=env, capture_output=True, text=True,
                       timeout=3600, **NO_WINDOW)
    got = [ln for ln in (r.stdout + r.stderr).splitlines() if ln.startswith("VCAP")]
    for ln in got:
        if "ERROR" in ln:
            print(ln)
    n = sum(1 for d in out.iterdir() if d.is_dir() and (d / "reference.png").exists())
    print(f"{n} frames in {out.relative_to(REPO)}")
    return 0 if n == len(a.frames.split(",")) else 1


if __name__ == "__main__":
    sys.exit(main())
