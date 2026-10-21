# jt8052 provenance

jotego's JT8051 (`jtcores`, `modules/jt8051`), as forked into an 8052 by the Vamphalf and Eolith
cores. Copied from Arcade-Eolith_MiSTer `rtl/qs1000/jt8052/` and `rtl/qs1000/jt8051/jt8051.uc` at
Eolith commit `717dbb7a2fc0ee5b0766c927989557989935bb42` (the last commit touching them). Their
own provenance, with the full list of changes against upstream JT8051, is Eolith's
`rtl/qs1000/PROVENANCE.md`; in short:

- 256 bytes of internal RAM (`ram_addr` 8 bits) and indirect access to 0x80-0xFF
- SFR writes from bit instructions write the merged byte, not the single bit (upstream
  `CLR ACC.7` with A = 3 leaves A = 0)
- Timer 2 (Eolith, marked `[EO]` in `jt8052_periph.v`)
- `p3_we`, `p3_latch`, `p1_we` outputs

**Licence: GPL-3.0-or-later** (`SPDX` lines in every file, Copyright Jose Tejada Gomez).

## Local changes

- `jt8052.vh`: the microcode path is `rtl/mcu/jt8052/jt8051.uc` (was `rtl/qs1000/jt8051/jt8051.uc`).
  Both Quartus and `scripts/run_sim.sh` run from the repository root.
- `jt8052.v`: output `p2_we`, marked `[DW]`, built like `p1_we` (`sfr_we && sfr_addr == 8'ha0`,
  registered on `cen`). dreamwld.cpp's `prot_p2_w` acts on every P2 write, including one of the
  value the port already holds, which `p2_o` alone cannot show.

## Use here

The board's protection MCU: an 87C52 / AT89C52 (dreamwld's die reads 87C51RA+, 8 KB ROM, 256 B
RAM) at 16 MHz. `cen` is one oscillator period (12 per machine cycle) and needs an idle `clk`
between pulses. The dumped program (`87c51rap.bin`) uses P0 (read, discarded), P1 (out), P2 bits
0-1 (out) and 2-3 (in), and `MOVC` from its own ROM; no interrupts, timers or serial
(`docs/boot_trace_mame.txt`).

## Tests

The upstream benches (`modules/jt8051/ver`) need jtframe's `simunit.sh` and Ruby, which are not
installed here, so they have not been run. `sim/mcu_tb` runs `87c51rap.bin` on this copy with
dreamwld.cpp's port model and checks its output stream against MAME.

## Changes in Arcade-Pandora_MiSTer

- `jt8052.v`: output `p0_we`, marked `[SB]`, built like `p1_we` and `p2_we` (`sfr_we && sfr_addr
  == 8'h80`, registered on `cen`). snowbros.cpp's `prot_p0_w` writes the low byte of a 68000 work
  RAM word on every P0 write.
