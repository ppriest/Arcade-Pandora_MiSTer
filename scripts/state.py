#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The core's state file: one format for MAME, the simulators and (later) the board.

    python scripts/state.py show    <file>
    python scripts/state.py to-sim  <file> <dir>          one .hex per section, for $readmemh
    python scripts/state.py from-sim <dir> <file> --set snowbros --source rtl:<commit>
    python scripts/state.py compare <a> <b> [--skip z80_regs,z80_ram]

File layout (docs/STATE.md):

    "SBST"  u16 version  u32 manifest length   (big-endian)
    manifest: JSON {"set", "source", "event", "sections": [{"name", "width", "depth"}, ...]}
    payload: each section in manifest order, `depth` big-endian words of `width` bits

Sections are those of docs/STATE.md. A reader takes what it knows by name and ignores the
rest, so a state from MAME that carries sections the RTL does not have yet still loads.

to-sim writes <dir>/<name>.hex (one word a line, hex, width/4 digits) and <dir>/state.txt
(name width depth per line); from-sim reads the same layout back, so a bench writes its dump
with $fwriteh in that form.
"""
import argparse
import json
import struct
import sys
from pathlib import Path

MAGIC = b"SBST"
VERSION = 1


def read(path):
    b = Path(path).read_bytes()
    if b[:4] != MAGIC:
        sys.exit(f"{path}: not a state file")
    ver, mlen = struct.unpack(">HI", b[4:10])
    if ver != VERSION:
        sys.exit(f"{path}: version {ver}, this reads {VERSION}")
    man = json.loads(b[10:10 + mlen])
    off = 10 + mlen
    data = {}
    for s in man["sections"]:
        nb = s["width"] // 8
        n = s["depth"] * nb
        raw = b[off:off + n]
        off += n
        data[s["name"]] = [int.from_bytes(raw[i:i + nb], "big") for i in range(0, n, nb)]
    return man, data


def write(path, man, data):
    payload = b""
    for s in man["sections"]:
        nb = s["width"] // 8
        words = data[s["name"]]
        if len(words) != s["depth"]:
            sys.exit(f"section {s['name']}: {len(words)} words, manifest says {s['depth']}")
        payload += b"".join(w.to_bytes(nb, "big") for w in words)
    m = json.dumps(man, separators=(",", ":")).encode()
    Path(path).write_bytes(MAGIC + struct.pack(">HI", VERSION, len(m)) + m + payload)


def cmd_show(a):
    man, data = read(a.file)
    print({k: v for k, v in man.items() if k != "sections"})
    for s in man["sections"]:
        w = data[s["name"]]
        nz = sum(1 for x in w if x)
        head = " ".join(f"{x:0{s['width'] // 4}x}" for x in w[:8])
        print(f"  {s['name']:10} {s['width']:2}b x {s['depth']:6}  {nz:6} non-zero  {head}")


def cmd_to_sim(a):
    man, data = read(a.file)
    d = Path(a.dir)
    d.mkdir(parents=True, exist_ok=True)
    lines = []
    for s in man["sections"]:
        dig = s["width"] // 4
        (d / f"{s['name']}.hex").write_text("".join(f"{x:0{dig}x}\n" for x in data[s["name"]]))
        lines.append(f"{s['name']} {s['width']} {s['depth']}")
    (d / "state.txt").write_text("\n".join(lines) + "\n")
    (d / "manifest.json").write_text(json.dumps(man, indent=1))
    print(f"{len(lines)} sections -> {d}")


def cmd_from_sim(a):
    d = Path(a.dir)
    secs, data = [], {}
    for ln in (d / "state.txt").read_text().split("\n"):
        if not ln.strip():
            continue
        name, width, depth = ln.split()
        words = [int(x, 16) for x in (d / f"{name}.hex").read_text().split()]
        secs.append({"name": name, "width": int(width), "depth": len(words)})
        data[name] = words
    ev = {}
    if (d / "event.txt").exists():
        ev = json.loads((d / "event.txt").read_text())
    man = {"set": a.set, "source": a.source, "event": ev, "sections": secs}
    write(a.file, man, data)
    print(f"{len(secs)} sections -> {a.file}")


def cmd_compare(a):
    ma, da = read(a.a)
    mb, db = read(a.b)
    skip = set(a.skip.split(",")) if a.skip else set()
    rc = 0
    for s in ma["sections"]:
        n = s["name"]
        if n in skip:
            continue
        if n not in db:
            print(f"  {n:10} only in {a.a}")
            continue
        x, y = da[n], db[n]
        k = min(len(x), len(y))
        diff = [i for i in range(k) if x[i] != y[i]]
        if not diff and len(x) == len(y):
            print(f"  {n:10} {len(x)} of {len(x)} words equal")
            continue
        rc = 1
        dig = s["width"] // 4
        first = ", ".join(f"[{i:#x}] {x[i]:0{dig}x}/{y[i]:0{dig}x}" for i in diff[:6])
        print(f"  {n:10} {len(diff)} of {k} words differ" +
              (f" (depth {len(x)} vs {len(y)})" if len(x) != len(y) else "") + f": {first}")
    for n in db:
        if n not in da and n not in skip:
            print(f"  {n:10} only in {a.b}")
    return rc


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("show"); p.add_argument("file")
    p = sp.add_parser("to-sim"); p.add_argument("file"); p.add_argument("dir")
    p = sp.add_parser("from-sim"); p.add_argument("dir"); p.add_argument("file")
    p.add_argument("--set", required=True); p.add_argument("--source", required=True)
    p = sp.add_parser("compare"); p.add_argument("a"); p.add_argument("b"); p.add_argument("--skip", default="")
    a = ap.parse_args()
    return {"show": cmd_show, "to-sim": cmd_to_sim, "from-sim": cmd_from_sim,
            "compare": cmd_compare}[a.cmd](a) or 0


if __name__ == "__main__":
    sys.exit(main())
