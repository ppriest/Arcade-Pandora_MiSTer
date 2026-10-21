#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# sim/video_tb over MAME captures: fixture, one frame, comparison. From the repository root:
#     scripts/video_frames.sh debug/snowbros-v/00700 debug/hyperpac-v_play/*
set -uo pipefail
fail=0
for d in "$@"; do
  python sim/video_tb/gen_fixture.py "$d" >/dev/null || { echo "$d: fixture failed"; fail=1; continue; }
  bash scripts/run_sim.sh video_tb +OUT="$d/rtl.txt" 2>&1 | grep -E "Fatal|Error:|overruns" | grep -v " 0 overruns" | sed "s|^|$d: |"
  python scripts/video_check.py "$d" | grep reference || fail=1
done
exit $fail
