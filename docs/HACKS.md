# Hacks, approximations and workarounds in this core

Everything in this core's own RTL, scripts or `.mra` layout that is known not to be what the
hardware does: a stand-in, a shortcut, a value chosen to make something work, a workaround for a
tool. Each entry is added in the commit that introduces the hack and removed in the commit that
removes it.

This is not `MAME_KLUDGES.md`. That file lists MAME's own guesses that the core reproduces on
purpose because MAME is the reference. This file lists what is ours.

Rules:

- An entry cites `file:line` (or a module and signal name if the line moves often), and the
  evidence column says what was measured, or "unverified".
- "What would make it correct" names the work, not "fix later".
- A hack whose entry is missing is a bug. A hack whose entry is stale is worse: update it in the
  same commit as the code.
- Severity is what a player or a verifier would see: **visible** (wrong pixels, wrong sound, wrong
  timing a game can hit), **latent** (wrong only for input no in-scope set produces), **tooling**
  (affects the build or the bench, not the bitstream).

| What | Where | Why it is a hack | What would make it correct | Evidence | Severity |
|---|---|---|---|---|---|
| Sync positions and widths | `rtl/video/video_timing.sv` (`HSYNC0`/`HSYNC1`, `VSYNC0`/`VSYNC1`) | MAME gives no horizontal timing or sync; hsync is pixels 276-303 and vsync lines 248-250, chosen to sit inside the blanking | A PCB measurement of sync position and width | unverified | visible (picture position on a CRT; CRT Adjust moves it) |
| Horizontal total 354 | `rtl/video/video_timing.sv` (`HTOTAL`) | Chosen with the user so 16 MHz / 3 and MAME's 262 lines give 57.50 Hz; the PCB's 15.68 kHz would be about 340 x 273 | A PCB measurement of the horizontal total | snowbros.cpp 35-36 against 1945-1948 | visible (line rate 15.07 kHz) |
| Bench stands in for the Z80 | `sim/state_tb/tb_state.sv`, `sim/boot_tb/tb_boot.sv` | 0x300000 reads a constant (the captured latch, or 0x03) | The sound board in the benches (Phase 3) | MAME read 0x03 once in the first 15 million accesses of snowbros | tooling |
| SDRAM_CLK at 317 degrees, 48 MHz | `rtl/pll/pll_0002.v` `phase_shift1` | Scaled from two sibling cores' estimates with the same controller, not measured here | A phase sweep on hardware: read margin at several shifts | unverified | visible if wrong |
| finalttr's M6295 at 1 MHz | `rtl/snowbros_core.sv` (`s_oki`) | MAME sets 999900 Hz (snowbros.cpp 2150); the 1 MHz enable is 100 ppm fast | A phase accumulator for that set | unverified by ear | latent (pitch 0.01% high) |
| HBlank replayed through vertical blank | `rtl/video/crt_chain.sv` (`hb_vz`, `hb_adj`) | crt_vsize and the vendored crt_adjust both hold HBlank high through vertical blank, and the framework's scandoubler needs a falling edge every line (issue #1). With V-Size off the core's own HBlank is used; with CRT Adjust on, the last active line's window is replayed on VBlank lines | crt_vsize and crt_adjust emitting a per-line HBlank upstream | `sim/sd_tb`: every Fx 448 lines, R 0-255, each line twice; Fx None unchanged byte for byte | visible: with CRT Adjust on and a Scandoubler Fx, line 239 shows once and HQ2x's first line is half-blended (line 16 is dropped with CRT Adjust on, scandoubler or not) |

## Removed

Entries move here when the hack is gone, with the commit that removed it, so a later reader can
tell "never had it" from "had it and fixed it". Delete a row once nothing else refers to it.

| What | Removed by | Replaced with |
|---|---|---|
