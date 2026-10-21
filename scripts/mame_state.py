#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Capture state files from MAME at level-4 interrupt entries (scripts/mame/state_capture.lua).

    python scripts/mame_state.py <set> [--arm 600] [--every 60] [--n 2] [--trace 200000] [--coin 0]
    python scripts/mame_state.py <set> --arm 605 --load <file.sbst> --out <dir>
    -> <dir>/mame_<k>.sbst, <dir>/mame.trace (default dir debug/<set>-state)

--load applies a state file (from the simulators, say) at the first entry counted; MAME
then runs on from it.

docs/STATE.md has the format; scripts/state.py reads it.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import NO_WINDOW, lua_runner_env, mame_cmd, mame_paths  # noqa: E402

TOAPLAN = {"snowbros", "snowbrosa", "snowbrosb", "snowbrosc", "snowbrosj", "snowbrosd", "toto"}
WRAM16 = TOAPLAN | {"finalttr"}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("--arm", type=int, default=600)
    ap.add_argument("--every", type=int, default=60)
    ap.add_argument("--n", type=int, default=2)
    ap.add_argument("--trace", type=int, default=0)
    ap.add_argument("--coin", type=int, default=0)
    ap.add_argument("--load", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    mame_dir, exe = mame_paths()
    out = Path(a.out).resolve() if a.out else REPO / "debug" / f"{a.set}-state"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    ver = subprocess.run([str(exe), "-version"], capture_output=True, text=True).stdout.split()[0]
    env = dict(os.environ, **lua_runner_env("state_capture.lua"),
               ST_PREFIX=(out / "mame").as_posix(), ST_ARM=str(a.arm), ST_EVERY=str(a.every),
               ST_N=str(a.n), ST_TRACE=str(a.trace), ST_COIN=str(a.coin), ST_SET=a.set,
               ST_SOURCE=f"mame {ver}", ST_WRAM=str(16384 if a.set in WRAM16 else 65536),
               ST_ZRAM="8000" if a.set in TOAPLAN else "d000",
               ST_LOAD=Path(a.load).resolve().as_posix() if a.load else "")
    r = subprocess.run(mame_cmd(exe, a.set, "state_capture.lua", mame_dir), cwd=str(mame_dir), env=env,
                       capture_output=True, text=True, timeout=3600, **NO_WINDOW)
    for ln in (r.stdout + r.stderr).splitlines():
        if ln.startswith(("STATE", "LOAD")) or "error" in ln.lower():
            print(ln)
    got = sorted(out.glob("mame_*.sbst"))
    print(f"{len(got)} states in {out}")
    return 0 if len(got) >= a.n else 1


if __name__ == "__main__":
    sys.exit(main())
