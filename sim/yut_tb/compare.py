#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""sim/yut_tb's starts and stops against MAME's (debug/yutnori-snd/{mame,rtl}.txt).

    python sim/yut_tb/compare.py

MAME's lines are its voices' state read at each frame end (scripts/mame/sndtrace.lua), so a
start or stop there is reported up to a frame after it happened; the bench's are the instant.
Each RTL start's phrase becomes a start address through the ROM's phrase table (8 bytes a
phrase, an 18-bit start first), the address MAME reports. Compared in order per chip: chip,
channel, address; and the RTL's time less than two frames before MAME's report and at most
1 ms after it: a start at line 0 is reported by MAME at that same instant, and the RTL's comes
the sequencer's and the ROM fetch's few microseconds later.
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FRAME = 1e9 / 57.5


def rom(name):
    return bytes(int(l, 16) for l in (REPO / "sim" / "yut_tb" / name).read_text().split())


def main():
    tables = {0: rom("music.hex"), 1: rom("voice.hex")}
    m = [l.split() for l in (REPO / "debug" / "yutnori-snd" / "mame.txt").read_text().splitlines()]
    r = [l.split() for l in (REPO / "debug" / "yutnori-snd" / "rtl.txt").read_text().splitlines()]
    end = max(int(x[0]) for x in r) if r else 0
    bad = 0
    for kind in ("S", "E"):
        ms = [(int(x[0]), int(x[2]), int(x[3]), int(x[4], 16) if kind == "S" else 0)
              for x in m if x[1] == kind and int(x[0]) <= end + 2 * FRAME]
        rs = []
        for x in r:
            if x[1] != kind:
                continue
            chip, ch = int(x[2]), int(x[3])
            addr = 0
            if kind == "S":
                t, p = tables[chip], int(x[4]) * 8
                addr = ((t[p] & 3) << 16) | (t[p + 1] << 8) | t[p + 2]
            rs.append((int(x[0]), chip, ch, addr))
        ok = 0
        for i, (mt, rt) in enumerate(zip(ms, rs)):
            same = mt[1:] == rt[1:] and -1e6 <= mt[0] - rt[0] < 2 * FRAME
            if not same:
                print(f"{kind} #{i}: MAME {mt[0] / 1e6:.3f} ms chip {mt[1]} ch {mt[2]} {mt[3]:05x}   "
                      f"RTL {rt[0] / 1e6:.3f} ms chip {rt[1]} ch {rt[2]} {rt[3]:05x}")
                bad += 1
                break
            ok += 1
        name = "STARTS" if kind == "S" else "STOPS "
        print(f"{name} {ok} of {len(ms)} match MAME (RTL {len(rs)}) in the {end / 1e6:.0f} ms simulated")
        if len(ms) != len(rs):
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
