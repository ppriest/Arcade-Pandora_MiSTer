# Vendored modules in this core

This index records vendored RTL, its source revision and any local changes. Component
`PROVENANCE.md` files add upstream history where available; licence obligations are in
`THIRD-PARTY.md`.

| Path here | Copied from | Source revision | Own provenance | Licence |
|---|---|---|---|---|
| `cpu/tg68k/` | Arcade-KonamiGX `rtl/cpu/tg68k/` | `89124d4f29e1` | `cpu/tg68k/PROVENANCE.md`: upstream `ade33e3` with zero initialisers, `stop_out`, `FlagsSR_out`, the 68020 `MOVEC ISP` fix and `DIVL_Wait` (default 0) | LGPL-3.0-or-later |
| `cpu/gx_ss_m68k.sv` | Arcade-KonamiGX `rtl/cpu/gx_ss_m68k.sv` | `89124d4f29e1` | modified here, `[SB]`: `M020` became `MODE`, and MODE 2 (TG68K.C as a 68000) added | GPL-3.0-or-later |
| `cpu/t80/` | Arcade-Fuuki `rtl/cpu/t80/` | `5a810122afb7` | `cpu/t80/PROVENANCE.md` | BSD-style |
| `sound/jtopl/` | Arcade-Fuuki `rtl/sound/jtopl/` | `5a810122afb7` | `sound/jtopl/PROVENANCE.md` | GPL-3.0 |
| `sound/jt51/` | Arcade-Vamphalf `rtl/sound/jt51/` | `03f6a39d79b8` | Vamphalf `rtl/sound/PROVENANCE.md`: jtcores `modules/jt51` at `985a573`, `hdl/` without `hdl/filter/`, unchanged | GPL-3.0-or-later |
| `sound/jt6295/`, `sound/sample_cache.sv`, `sound/oki_rom_bridge.sv` | Arcade-DreamWorld `rtl/sound/` | `233d1f299192` | `sound/jt6295/PROVENANCE.md`; DreamWorld `rtl/sound/PROVENANCE.md` | GPL-3.0 |
| `mcu/jt8052/` | Arcade-DreamWorld `rtl/mcu/jt8052/` | `233d1f299192` | `mcu/jt8052/PROVENANCE.md` | GPL-3.0-or-later |
| `jtframe/` (`jtframe_objdraw`, `_objdraw_gate`, `_draw`, `_obj_buffer`, `_dual_ram`, `_sh`, `LICENSE`) | jotego's jtcores `modules/jtframe/hdl/video/` and `hdl/ram/`, upstream, unchanged | jtcores `451c630da78a` | none | GPL-3.0-or-later |
| `video/screen_rotate_two.sv` | Arcade-DreamWorld `rtl/video/` | `233d1f299192` | Sorgelig's MiSTer rotator, unchanged | GPL-2.0-or-later |
| `video/crt_adjust.sv` | Arcade-Raiden_MiSTer | see source header | one local fix marked `LOCAL FIX` | GPL-3.0-or-later |
| `video/crt_vsize.sv` | MiSTer-CRT-Adjust | `c682de9` | unchanged | GPL-3.0-or-later |
| `memory/` (without `dl_xform.sv` and `snowbros_sdram_top.sv`) | Arcade-DreamWorld `rtl/memory/` | `233d1f299192` | the Psikyo lineage; `sdram.sv` is Seta's with the `dq_in` fix (DreamWorld roadmap, reuse map) | GPL-3.0-or-later as adapted |

Benches copied with them, run here unchanged (`scripts/run_sim.sh`):

| Bench | From | Result here |
|---|---|---|
| `sim/mcu_tb` | DreamWorld | PASS: 1737 bytes match MAME's C00030 stream (jt8052 running dreamwld's MCU program) |
| `sim/oki_tb` | DreamWorld | PASS: phrase 28 played and stopped |
| `sim/sdram_tb` | DreamWorld | PASS: cases 1-6 |
| `sim/tg68k_spike` | DreamWorld (VHDL; vcom/vsim by hand), run against DreamWorld's TG68K copy before the switch to KonamiGX's | end condition reached: the BFEXTU result write observed |
| `sim/gx_ss_cpu_tb` | KonamiGX, the parameter renamed | ALL PASS (MODE 1, TG68K.C as a 68020) |
| `sim/ss_m68k_tb` | written here from `gx_ss_cpu_tb` | ALL PASS (MODE 2, TG68K.C as a 68000): capture, load, STOP |

The copied benches keep the headers they were written with, so some still name DreamWorld's files
(`docs/boot_trace_mame.txt`, `rtl/dreamworld_top.sv`, `sim/dreamworld_top_tb`). They are left
unchanged so a diff against DreamWorld stays clean.

No sibling has a bench for jt51, jtopl or T80; they are checked against MAME register traces in
Phase 3. jtframe comes from upstream jtcores rather than KonamiGX: KonamiGX's modified
`jtframe_draw.v` uses `pair2` before declaring it, which ModelSim's vlog rejects (vlog-2730).
Upstream's own benches need jtframe's simulation scripts; the drawing modules are checked here by
`sim/video_tb` against MAME's frames.
