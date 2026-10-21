#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Sound-board traces from MAME (scripts/mame/sndtrace.lua), and the comparison with sim/sound_tb.

    python scripts/mame_sndtrace.py capture <set> [--frames 600] [--coin 0]
        -> debug/<set>-snd/mame.txt
    python scripts/mame_sndtrace.py compare <set>
        debug/<set>-snd/mame.txt against debug/<set>-snd/rtl.txt (the bench's)

compare checks the chip writes (YM register selects and data, M6295 commands) in order, over the
writes the RTL trace covers, and reports where each first differs and how far the RTL's times
have drifted from MAME's. The latch writes in the RTL trace are the replayed ones.
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


def load(p):
    rows = []
    for ln in Path(p).read_text().splitlines():
        f = ln.split()
        if len(f) >= 3 and f[1] in "YO":
            rows.append((int(f[0]), f[1], tuple(int(x, 16) for x in f[2:])))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["capture", "compare"])
    ap.add_argument("set")
    ap.add_argument("--frames", type=int, default=600)
    ap.add_argument("--coin", type=int, default=0)
    a = ap.parse_args()
    out = REPO / "debug" / f"{a.set}-snd"
    if a.cmd == "capture":
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        mame_dir, exe = mame_paths()
        env = dict(os.environ, **lua_runner_env("sndtrace.lua"), SN_OUT=(out / "mame.txt").as_posix(),
                   SN_FRAMES=str(a.frames), SN_COIN=str(a.coin),
                   SN_BOARD="toaplan" if a.set in TOAPLAN else "yutnori" if a.set == "yutnori" else "semicom")
        subprocess.run(mame_cmd(exe, a.set, "sndtrace.lua", mame_dir), cwd=str(mame_dir), env=env,
                       capture_output=True, timeout=3600, **NO_WINDOW)
        txt = (out / "mame.txt").read_text().splitlines()
        print(f"{a.set}: {sum(' L ' in l for l in txt)} latch writes, {sum(' Y ' in l for l in txt)} YM writes, "
              f"{sum(' O ' in l for l in txt)} M6295 writes -> {out / 'mame.txt'}")
        return 0
    m, r = load(out / "mame.txt"), load(out / "rtl.txt")
    k = min(len(m), len(r))
    bad = next((i for i in range(k) if m[i][1:] != r[i][1:]), None)
    drift = [r[i][0] - m[i][0] for i in range(k if bad is None else bad)]
    worst = max((abs(d) for d in drift), default=0)
    if bad is None:
        print(f"CHIP WRITES  {k} of {k} match MAME in order (MAME {len(m)}, RTL {len(r)}); "
              f"time drift at most {worst / 1e6:.3f} ms, at the end {drift[-1] / 1e6 if drift else 0:.3f} ms")
        return 0
    print(f"CHIP WRITES  MISMATCH at write {bad + 1} of {k}; {bad} matched, drift up to {worst / 1e6:.3f} ms")
    for i in range(max(0, bad - 3), min(k, bad + 4)):
        print(f"   #{i + 1:<6} MAME {m[i][0] / 1e6:10.3f} ms {m[i][1]} {m[i][2]}   RTL {r[i][0] / 1e6:10.3f} ms {r[i][1]} {r[i][2]}"
              + ("   <--" if i == bad else ""))
    return 1


if __name__ == "__main__":
    sys.exit(main())
