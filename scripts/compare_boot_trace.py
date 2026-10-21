#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Diff the RTL CPU's boot against MAME's. Phase 0.

    python scripts/compare_boot_trace.py replay  <set>   # MAME's I/O reads -> replay file
    python scripts/compare_boot_trace.py compare <set>   # RTL trace vs MAME trace
    python scripts/compare_boot_trace.py compare <set> --mame <file> --rtl <file>
                                                     # e.g. traces from a restored state

Inputs: debug/<set>-boot/<set>_boot.trace (scripts/mame_boot_trace.py) and
<set>_rtl.trace, written by the boot bench in the same "seq rw addr mask data"
format: bus-aligned address, byte-lane mask. ROM and work-RAM ranges come from
regions.json "trace" "rom"/"ram"; everything else is I/O and is replayed.
Written for a 32-bit bus; merge_halves() handles a CPU that splits accesses in two.

WHAT IS COMPARED, AND WHAT IS NOT

  * WRITES, strictly, in order: address, lanes, and data under the mask. This
    is the strong check. A CPU that executes the same program correctly makes
    the same writes with the same data in the same order, whatever it does
    with the bus in between.
  * NON-ROM READS, in order: these are the replayed I/O reads. A mismatch means
    the RTL asked a peripheral a different question from MAME's CPU.
  * ROM FETCHES, as a superset only. A prefetching CPU core and MAME's do
    not, so two correct CPUs read the same words in different orders and the
    RTL reads words MAME never asks for (LESSONS_LEARNED, "[Seta] Two cores
    that both boot correctly still fetch different words, so compare as a
    subsequence with duplicates collapsed"). What is checked is that every ROM
    word MAME read inside the RTL's window, the RTL also read.

The RTL trace is shorter than MAME's by design; it is compared up to the
number of writes it reached.
"""
import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import regions  # noqa: E402

# regions.json "trace": "rom" and "ram" are lists of [lo, hi] hex strings, inclusive.
_T = regions().get("trace", {})
ROM = [(int(lo, 16), int(hi, 16)) for lo, hi in _T.get("rom", [])]
RAM = [(int(lo, 16), int(hi, 16)) for lo, hi in _T.get("ram", [])]


def load(path):
    rows = []
    for ln in open(path, encoding="utf8"):
        if ln.startswith("#") or not ln.strip():
            continue
        seq, rw, a, m, d = ln.split()
        m = int(m, 16)
        rows.append((int(seq), rw, int(a, 16), m, int(d, 16) & m))
    return rows


def merge_halves(rows):
    """Join two consecutive accesses to the same dword into one.

    A CPU narrower than the bus splits a wide access in two, and MAME's tap may
    report one side split and the other whole (on KonamiGX: instruction fetches
    split, data accesses whole). Unmerged, the traces fall one entry out of step
    at every such access, which also skews the write-count comparison window.
    Both sides are normalised the same way: an adjacent pair with the same
    direction, the same aligned address and disjoint lanes becomes one access.
    """
    out = []
    for r in rows:
        if out:
            s0, rw0, a0, m0, d0 = out[-1]
            _, rw1, a1, m1, d1 = r
            if rw0 == rw1 and a0 == a1 and not (m0 & m1):
                out[-1] = (s0, rw0, a0, m0 | m1, d0 | d1)
                continue
        out.append(r)
    return out


def long_order(ws):
    """A long write's two word halves in ascending address order.

    The two halves of a long write are adjacent accesses to a and a + 2; a 68000 writing
    -(An) puts the low word first, TG68K.C the high word. The memory is the same either
    way, so both traces are put in one order before the in-order comparison.
    """
    ws = list(ws)
    i = 0
    while i + 1 < len(ws):
        (a0, m0, d0), (a1, m1, d1) = ws[i], ws[i + 1]
        if a0 == a1 + 2 and m0 == m1 == 0xFFFF and not is_rom(a0):
            ws[i], ws[i + 1] = ws[i + 1], ws[i]
            i += 2
        else:
            i += 1
    return ws


VEC_LO, VEC_HI = 0x60, 0x7F       # the 68000's autovectors (spurious and levels 1-7)


def split_frames(rows):
    """(rows without exception frames, frames). A frame is the three writes before an
    autovector read: PC and SR of an interrupt entry. Their PC is the instruction the
    interrupt landed on, which a CPU with other instruction timings reaches at another
    point of a wait loop, so frames are checked apart from the in-order writes."""
    drop, frames = set(), []
    for i, (_, rw, a, m, d) in enumerate(rows):
        if rw == "r" and VEC_LO <= a <= VEC_HI and not (a & 3):
            ws = [j for j in range(i - 1, max(-1, i - 8), -1) if rows[j][1] == "w"][:3]
            if len(ws) == 3:
                drop.update(ws)
                f = sorted((rows[j][2], rows[j][4]) for j in ws)   # by address: SR, PC high, PC low
                frames.append((a, f[0][0], f[0][1], (f[1][1] << 16) | f[2][1]))
    return [r for i, r in enumerate(rows) if i not in drop], frames


def is_rom(a):
    return any(lo <= a <= hi for lo, hi in ROM)


def is_ram(a):
    return any(lo <= a <= hi for lo, hi in RAM)


def cmd_replay(game):
    mame = REPO / "debug" / f"{game}-boot" / f"{game}_boot.trace"
    out = REPO / "debug" / f"{game}-boot" / f"{game}_replay.txt"
    n = 0
    with open(out, "w", encoding="utf8") as f:
        for seq, rw, a, m, d in load(mame):
            if rw == "r" and not is_rom(a) and not is_ram(a):
                f.write(f"{a:06X} {m:08X} {d:08X}\n")
                n += 1
    print(f"{n} I/O reads -> {out}")
    return 0


def cmd_compare(game, mame_path=None, rtl_path=None):
    base = REPO / "debug" / f"{game}-boot"
    raw_mame = load(mame_path or base / f"{game}_boot.trace")
    raw_rtl = load(rtl_path or base / f"{game}_rtl.trace")
    if not raw_rtl:
        sys.exit("the RTL trace is empty -- did the bench run?")
    mame = merge_halves(raw_mame)
    rtl = merge_halves(raw_rtl)
    print(f"merged split halves: MAME {len(raw_mame)} -> {len(mame)} accesses, "
          f"RTL {len(raw_rtl)} -> {len(rtl)}")

    mame, mframes = split_frames(mame)
    rtl, rframes = split_frames(rtl)
    mw = long_order((a, m, d) for _, rw, a, m, d in mame if rw == "w")
    rw_ = long_order((a, m, d) for _, rw, a, m, d in rtl if rw == "w")
    rc = 0

    # --- writes, strictly in order
    n = len(rw_)
    first = next((i for i in range(min(n, len(mw))) if rw_[i] != mw[i]), None)
    if first is None and n <= len(mw):
        print(f"WRITES    {n} of {n} match MAME in address, lanes, data and order")
    else:
        rc = 1
        if first is None:
            print(f"WRITES    the RTL made {n} writes, MAME only {len(mw)} in its trace")
        else:
            print(f"WRITES    MISMATCH at write {first + 1} of {n}:")
            for i in range(max(0, first - 3), min(first + 4, n, len(mw))):
                flag = "  <--" if i == first else ""
                a1, m1, d1 = mw[i]
                a2, m2, d2 = rw_[i]
                print(f"    #{i + 1:<6} MAME {a1:06X} {m1:08X} {d1:08X}   "
                      f"RTL {a2:06X} {m2:08X} {d2:08X}{flag}")

    # How far into MAME's trace does the RTL's progress reach? Up to the
    # MAME access that made the RTL's last write.
    wseen = 0
    mame_cut = len(mame)
    for i, (_, rw, *_rest) in enumerate(mame):
        if rw == "w":
            wseen += 1
            if wseen == n:
                mame_cut = i + 1
                break
    window = mame[:mame_cut]

    # --- I/O reads, in order. RAM reads are not compared: a loop polling a RAM flag that an
    # interrupt sets spins as many times as the CPU's timing gives it, and RAM contents are
    # what a state comparison checks.
    mio = [(a, m, d) for _, rw, a, m, d in window if rw == "r" and not is_rom(a) and not is_ram(a)]
    rio = [(a, m, d) for _, rw, a, m, d in rtl if rw == "r" and not is_rom(a) and not is_ram(a)]
    k = min(len(mio), len(rio))
    bad = next((i for i in range(k) if mio[i] != rio[i]), None)
    if bad is None and len(mio) == len(rio):
        print(f"I/O READS {len(rio)} of {len(rio)} match MAME in order")
    else:
        rc = 1
        print(f"I/O READS MAME {len(mio)}, RTL {len(rio)}; first difference at "
              f"{bad + 1 if bad is not None else k + 1}")
        i0 = bad if bad is not None else k
        for i in range(max(0, i0 - 2), min(i0 + 3, max(len(mio), len(rio)))):
            mm = f"{mio[i][0]:06X} {mio[i][1]:04X} {mio[i][2]:04X}" if i < len(mio) else "-"
            rr = f"{rio[i][0]:06X} {rio[i][1]:04X} {rio[i][2]:04X}" if i < len(rio) else "-"
            print(f"    #{i + 1:<6} MAME {mm:20} RTL {rr}")

    # --- ROM fetches, superset
    mrom = {(a, m) for _, rw, a, m, d in window if rw == "r" and is_rom(a)}
    # Coverage is per BYTE LANE, not per (address, mask) pair: the RTL may have
    # read a whole dword where MAME read one half, or two halves where MAME
    # read the dword, and either way the lanes MAME asked for were read.
    rlanes = {}
    for _, rw, a, m, d in rtl:
        if rw == "r" and is_rom(a):
            rlanes[a] = rlanes.get(a, 0) | m
    def covered(a, m):
        return (m & ~rlanes.get(a, 0)) == 0
    missing = [x for x in mrom if not covered(*x)]
    if missing:
        rc = 1
        missing.sort()
        print(f"ROM       {len(mrom) - len(missing)} of {len(mrom)} MAME ROM reads were also "
              f"made by the RTL; first missing: {missing[0][0]:06X} {missing[0][1]:08X}")
    else:
        print(f"ROM       every one of MAME's {len(mrom)} distinct ROM reads in the window "
              f"was also made by the RTL")

    # --- interrupt frames: vector, stack address and SR in order; PC reported
    mf = mframes
    k = min(len(mf), len(rframes))
    bad = next((i for i in range(k) if mf[i][:3] != rframes[i][:3]), None)
    pcs = sum(1 for i in range(k) if mf[i][3] == rframes[i][3])
    if bad is None and len(rframes) <= len(mf):
        print(f"FRAMES    {len(rframes)} of {len(rframes)} interrupt entries match MAME in vector, "
              f"stack address and SR; {pcs} also in the interrupted PC")
    else:
        rc = 1
        i = bad if bad is not None else k
        print(f"FRAMES    MISMATCH at interrupt entry {i + 1}: "
              f"MAME {mf[i] if i < len(mf) else '-'}, RTL {rframes[i] if i < len(rframes) else '-'}")

    print(f"\nwindow: RTL {len(rtl)} accesses, MAME {mame_cut} accesses to the same "
          f"write ({n} writes)")
    return rc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["replay", "compare"])
    ap.add_argument("game")
    ap.add_argument("--mame")
    ap.add_argument("--rtl")
    a = ap.parse_args()
    return cmd_replay(a.game) if a.cmd == "replay" else cmd_compare(a.game, a.mame, a.rtl)


if __name__ == "__main__":
    sys.exit(main())
