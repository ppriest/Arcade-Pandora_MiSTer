#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare sim/video_tb's frame with MAME's screenshot and the software model.

    python scripts/video_check.py <capture dir>        reads <dir>/rtl.txt, writes rtl.png

Both comparisons are printed; the reference is MAME's reference.png, the model's model.png
(scripts/render_model.py) shows whether a difference is the model's too.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    rc = 0
    for d in map(Path, sys.argv[1:]):
        px = [int(x, 16) for x in (d / "rtl.txt").read_text().split()]
        if len(px) != 256 * 224:
            print(f"{d}: {len(px)} pixels, wanted {256 * 224}")
            rc = 1
            continue
        a = np.array(px, dtype=np.uint32).reshape(224, 256)
        rtl = np.stack([a >> 16 & 255, a >> 8 & 255, a & 255], axis=2).astype(np.uint8)
        Image.fromarray(rtl, "RGB").save(d / "rtl.png")
        for name in ("reference.png", "model.png"):
            if not (d / name).exists():
                continue
            ref = np.asarray(Image.open(d / name).convert("RGB"))
            bad = np.argwhere(np.any(ref != rtl, axis=2))
            print(f"{d}: RTL vs {name}: {len(bad)} of {224 * 256} pixels differ" +
                  (f", first at y={bad[0][0]} x={bad[0][1]}" if len(bad) else ""))
            if name == "reference.png" and len(bad):
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
