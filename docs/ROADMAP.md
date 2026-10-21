# Snow Bros / SemiCom (Kaneko Pandora) — MiSTer Core Roadmap

**Approved by the user as proposed: Pandora sets in scope, 48 MHz with a 5.333 MHz pixel clock,
per-line sprite engine. A phase whose scope changes goes back for approval.**

## Context

Goal: a DE10-nano MiSTer core for the Toaplan Snow Bros board and the SemiCom boards that copy
it, emulated by MAME's `kaneko/snowbros.cpp` with `kan_pand.cpp` — one `.rbf`, a `.mra` per set.

Almost every chip already exists in open RTL proven in a sibling core: the 68000 (TG68K.C), the
Z80 (T80), the YM3812 (jtopl2), the YM2151 (jt51), the M6295 (jt6295) and the SemiCom 87C52
(jt8052, already running SemiCom protection in Arcade-DreamWorld). The board has no tilemap: the
Pandora sprite chip is the whole picture. Two open Pandora implementations exist (DJ Boy, Heavy
Unit), both frame-buffer engines. New work:

1. The Pandora engine at this core's clock, from MAME's model and those two modules.
2. Two graphics layouts (Toaplan and SemiCom) served from one SDRAM path.
3. The SemiCom protection: the real MCU for the three dumped sets, MAME's `protdata` copy for the
   rest.

A closed-source Snow Bros core exists (Coin-Op Collection, `snowbros_mister_20260611.rbf`, six
sets, from `E:/MiSTer-MAME-Coverage/docs/data/coverage.json`). None covers the SemiCom games.

Cross-cutting findings from the previous cores are in **[`LESSONS_LEARNED.md`](LESSONS_LEARNED.md)**.
Working practice is in **[`WORKFLOW.md`](WORKFLOW.md)**. The board as MAME models it, with line
citations, is **[`HARDWARE_NOTES.md`](HARDWARE_NOTES.md)**.

## Progress

**Phase 2 in progress.** First build `7f5d639`+1 (work RAM `no_rw_check`): fits, setup slack
+6.966 ns on clk_sys, 217 of 553 RAM blocks, 37% of the ALMs (`build/q_staged.log`). Deployed as
`Pandora_30000001.rbf` with five `.mra` files; on the board all five sets run into attract mode: snowbros, hyperpac (the
user's eye), cookbib3, cookbib2 (the real MCU) and toto (the download's bit swap)
(`debug/hw/*_first.png`, `debug/hw/cookbib3_fix.png`; build of the protdata fix, slack +5.780 ns). cookbib3 was
black until the protdata copy's write address was fixed (it wrote every word one place low). The
MiSTer rebooted once around a hyperpac launch, cause not established; later launches were clean.
Not yet played: inputs, DIPs and flip are untested on the board; SemiCom sound is Phase 3. Whole-core bench
(`sim/top_tb`): download samples of every region equal to the Python transforms, and the
68000 booting from the SDRAM model matches MAME (12702 of 12702 writes). Phase 1's criteria met;
Phase 0's too. State files move between MAME and the simulator in
both directions (`docs/STATE.md`); the board side waits for the top level. Repository bootstrapped from Template_MiSTer.
Measured in MAME 0.289: the video-write sweep (`write_timing_mame.txt`) and the Pandora line load
(`sprite_load_mame.txt`). No RTL.

## Game scope

From `-listxml`; the full table with ROM sizes is in `HARDWARE_NOTES.md`, "Sets".

| Family | Sets | Largest | Sound | Protection |
|---|---|---|---|---|
| Toaplan | snowbros, snowbrosa/b/c/j/d, toto | 800 KB | Z80 6 MHz, YM3812 | none (toto: one constant read) |
| SemiCom, real MCU | hyperpac, cookbib2, cookbib2a | 2.0 MB | Z80 4 MHz, YM2151, M6295 | 87C52 dumped |
| SemiCom, protdata | hyperpacb, cookbib2b/c, finalttr, toppyrap, cookbib3, pzlbreak/a, suhosong, twinkle/a, 3in1semi/a, mcheonru, moremore, moremorp, 4in1boot | 3.3 MB | as above | 512-byte RAM image at reset; some read a constant |
| SemiCom, not working in MAME | sutjarod, gwasu | 1.5 MB | as above | protdata plus ROM patches marked `HACK` |
| yutnori | yutnori | 2.1 MB | two M6295, `NO_SOUND` | `UNEMULATED_PROTECTION` |
| Bootleg video | wintbob, snowbroswb, honeydol, twinadv/k, multi96, snowbro3, ballboy, ballboy3p | 5.3 MB | varies | snowbro3: sound MCU undumped, HLE |

### Scope decision

- **In scope:** the Toaplan and SemiCom Pandora sets — one memory map with small variants, one
  screen, one sprite chip, two sound boards, 3.3 MB at most against a 32 MB SDRAM.
- **Out of the first scope:** yutnori (no sound and unemulated protection in MAME); sutjarod and
  gwasu (`MACHINE_NOT_WORKING`, and their MAME support is a ROM patch); the bootleg video boards
  (four further sprite formats, an 8bpp background layer, snowbro3's sound is MAME HLE of an
  undumped MCU). The bootleg boards are Phase 5, a decision with evidence.
- **First-target set:** snowbros — no protection, 8 MHz 68000, YM3812.
- **Second target:** hyperpac — exercises the SemiCom map, YM2151 + M6295, the real MCU and the
  second graphics layout.

ROMs missing from `MAME_ROMPATH` on this machine: snowbrosa/b/c/j/d, hyperpacb, cookbib2a/b/c,
pzlbreaka, twinklea, 3in1semia (and out-of-scope clones). Their `.mra` files can be generated from
the driver, but not checked against a loaded image until the ROMs are here.

## Hardware reality (from the driver, not assumption)

### Chips

`HARDWARE_NOTES.md`, "CPUs and chips": 68000 at 8 MHz (Toaplan) or 12 MHz (SemiCom); Z80 at
6 MHz or 4 MHz; YM3812 3 MHz or YM2151 4 MHz; M6295 1 MHz pin 7 high on SemiCom; AT89C52 /
87C52 16 MHz on SemiCom; Pandora PX79C480FP-3.

### Clocks

Board clocks: 16 MHz and 12 MHz crystals (snowbros.cpp 22, 24). Every derived clock is cited in
`HARDWARE_NOTES.md`, "Clocks".

**`clk_sys` = 48.000 MHz, SDRAM on `clk_sys` (multiple 1).** 48 MHz divides every in-scope board
clock exactly:

| Clock | Enable from 48 MHz |
|---|---|
| 68000, Toaplan, 8 MHz | 1/6 |
| 68000, SemiCom, 12 MHz | 1/4 |
| Z80 6 MHz / 4 MHz | 1/8 / 1/12 |
| YM3812 3 MHz | 1/16 |
| YM2151 4 MHz | 1/12 |
| M6295 1 MHz | 1/48 |
| 87C52 16 MHz | 1/3 (jt8052 needs an idle clock between enables: met) |
| finalttr Z80 and YM2151, 3.579545 MHz | Bresenham 3579545/48000000, exact as a ratio |

**Pixel clock: an open item.** MAME has no `set_raw`: 57.5 Hz, 262 lines, 256 visible. The PCB
notes give HSync 15.68 kHz, which is 272.7 lines at 57.5 Hz, not 262. Proposed: **16 MHz / 3 =
5.333 MHz, 354 clocks a line, 262 lines** — 57.50 Hz with MAME's line count, so MAME's interrupt
lines (32, 128, 240) mean what they mean in the driver. `clk_sys` is 9x the pixel clock. The
alternative, 6 MHz (12 MHz / 2, 8x), gives 398 x 262 = 57.54 Hz. Either is an integer division of
48 MHz. MAME's 262 lines against the PCB's 15.68 kHz goes in `MAME_KLUDGES.md`. A PCB measurement
of the horizontal total, or a schematic, would settle it.

The 68000 runs at its board rate from BRAM-held RAM and SDRAM-held ROM; if ROM stalls cost cycles,
the enable runs ahead to repay them (`clocks.md`, rule 5), measured in Phase 0.

### Interrupts

Levels 4, 3, 2 at lines 32, 128, 240, `ASSERT_LINE`, each cleared by its own write
(snowbros.cpp 119-139). Toaplan Z80: NMI on sound latch, INT from YM3812. SemiCom Z80: INT from
YM2151, latch polled. The vectors are read from the program ROM in Phase 0.

### Memory map

`HARDWARE_NOTES.md`, "Memory map". The variants: work RAM 16 KB (snowbros, finalttr) or 64 KB
(SemiCom); ROM window 256 KB or 1 MB; a per-set constant at 0x200000 or 0x500006; watchdog and
flip only on the Toaplan map.

### Video

Pandora only: 512 entries, 16 x 16 x 4bpp, 16 banks, relative chaining, later entries on top
(kan_pand.cpp 130-201). MAME draws the whole list at vblank start into a double-buffered
256 x 256 x 8 bitmap and shows it the next frame (203-211); the board has the DRAM for exactly
that (four 4464, snowbros.cpp 16-17). Background fill 0xF0, or the `bg_pen` of pzlbreak (0xC0).
Palette 256 x xBGR_555. Visible 256 x 224.

### Sound

Toaplan: Z80 + YM3812, mono. SemiCom: Z80 + YM2151 (routes 0.10 each) + M6295 (1.0), mono
(snowbros.cpp 2011-2018). finalttr: 3.579545 MHz and 0.08 / 0.4 routes (2141-2151).

### Protection

hyperpac, cookbib2, cookbib2a: the MCU writes 68000 work RAM through its ports (218-237); run the
dumped program on jt8052. semiprot and finalttr sets: copy the 512-byte `protdata` region into
work RAM at reset, as MAME does (1915-1929); log as a MAME kludge. Constant reads at 0x200000 /
0x500006 per set: a mod-byte table.

### Per-game configuration

Mod byte: board (Toaplan / SemiCom / finalttr), 68000 clock, graphics layout, work RAM size,
protection mode (none, MCU, protdata at 0x10F000 or 0x102000), the constant-read address and
value, `bg_pen`, flip available.

## Component reuse map

| block | plan | source |
|---|---|---|
| 68000 | Keep | TG68K.C kernel, Arcade-DreamWorld `rtl/cpu/tg68k/` with its `PROVENANCE.md`, instantiated directly |
| Z80 | Keep | T80se, Arcade-Fuuki `rtl/cpu/t80/` (MiSTer-devel/T80 `830fd03`, BSD-style) |
| YM3812 | Keep | jtopl2, Arcade-Fuuki `rtl/sound/jtopl/` (jotego `7ac0c81`, GPL-3.0) |
| YM2151 | Keep | jt51, Arcade-Vamphalf `rtl/sound/jt51/` (jtcores `985a573`, GPL-3.0) |
| M6295 | Keep | jt6295 with `sample_cache.sv` / `oki_rom_bridge.sv`, Arcade-DreamWorld `rtl/sound/` |
| 87C52 | Keep | jt8052, Arcade-DreamWorld `rtl/mcu/jt8052/`, and `semicom_mcu.sv` adapted to P0/P1/P2 writes into work RAM |
| Toaplan sound board | Adapt | Fuuki `fg2_sound.sv` (Z80 + YM3812 + latch): map from snowbros.cpp 200-212 |
| SemiCom sound board | Adapt | Vamphalf `vh_ymoki.sv` (YM2151 + M6295) behind a T80 |
| Pandora | Written from the software model | MAME `kan_pand.cpp`. Read against `hvyunit_pandora.sv` (decoryah/Arcade-HeavyUnit_MiSTer, GPL-3.0-or-later, bit-exact against its own oracle per its README) and `djboy_pandora.sv` (rmonic79/Arcade-DJBoy_MiSTer, GPL-3.0-or-later in the file, GPL-2.0 in the repository licence). Both draw into a frame buffer; see "Design decisions" |
| per-line sprite draw | Port | `jtframe_objdraw` / `jtframe_obj_buffer`, Arcade-KonamiGX `rtl/jtframe/` (jtcores `e7958c8`, GPL-3.0) |
| SDRAM, download, DDR3 load | Keep | Arcade-DreamWorld `rtl/memory/` (Seta's `sdram.sv` with the `dq_in` fix) |
| video timing, CRT Adjust, rotation, pause (hiscore dropped: the user's call) | Keep | Arcade-DreamWorld `rtl/video/`, `hiscore.v`; Fuuki `pause_control.sv` |
| DIP/keys | Keep | `rtl/mame_keys.sv` (skill asset) |

Looked at and not used: Sand Scorpion's `pandora.sv`, cited in Heavy Unit's `ARCHITECTURE.md` as
68000-wired with 13-bit codes; its repository was not found by `gh search repos`.

## On-chip RAM budget

Framework baseline from Arcade-DreamWorld's fit: about 95 M10K for `sys/`, `ascal` and CRT
Adjust. Core, estimated:

| Block | M10K |
|---|---|
| 68000 work RAM, 64 KB (SemiCom) | 64 |
| Sprite RAM 4 KB, and its vblank snapshot 4 KB | 8 |
| Z80 RAM, 2 KB | 2 |
| Palette 512 B, MCU ROM 8 KB and RAM 256 B | ~10 |
| Sprite line buffers, 2 x 256 x 8 | 2 |
| M6295 cache | ~2 |

About 180 of 553 with the line engine. A double frame buffer of 256 x 224 x 8 would add 112.

## Memory plan

SDRAM, 32 MB, at `clk_sys`. Largest in-scope set 3.3 MB (4in1boot), so one copy of every region:

| Region | Size | Client |
|---|---|---|
| maincpu | 1 MB window, up to 1 MB loaded (4in1boot) | 68000 bridge |
| gfx1 | up to 2 MB | Pandora fetch, dedicated port |
| soundcpu | up to 64 KB | Z80 (or BRAM: 64 KB = 64 M10K; decide in Phase 0) |
| oki1 | up to 256 KB | M6295 cache |

MCU ROM in BRAM. DDR3 at load time, and during play for HDMI rotation only: the user asked for
Orientation CW/CCW to run these horizontal sets on a vertical monitor, which needs the HPS
framebuffer (`screen_rotate_two`). The ROM copy and the rotator never hold DDR3 together: the
copy runs with the board in reset.

**Sprite fetch budget** (`sprite_load_mame.txt`). A line at 48 MHz and 354 x 262 x 9 clocks is
3186 clocks. One 16-pixel tile row at 4bpp is 8 bytes, one burst-4 granule. The worst line
measured is 73 entries (twinkle, pzlbreak, moremore, in play; blank tiles counted): 73 granules
at about 11 clocks each on a dedicated port is 803 clocks, and 1168 pixels at one a clock, so the
fetch and draw overlap in under 1200 clocks of the 3186. Resolving the chain (512 entries x 5
bytes from the snapshot) is once a frame, about 2600 clocks, in vblank.

## Design decisions

**Follow MAME, including where MAME is wrong, and write down every place that is.** Each goes in
`docs/MAME_KLUDGES.md` when it is implemented. Known now: 262 lines against the PCB's 15.68 kHz;
`protdata` copied at reset in place of an undumped MCU.

**Where a vendored module and MAME disagree, record it and keep the module.**

**Every approximation of this core's own goes in `docs/HACKS.md`** in the commit it lands.

**Transcribe the reference literally first, then look for the chip.**

**One `.rbf` for all games.** Per-set differences are `.mra` mod-byte configuration.

**Two Quartus revisions, `Pandora_stp` and `Pandora`,** differing only by `DEBUG_ISSP`.

**Licence: GPL-3.0-or-later**, following jtopl, jt51, jt6295 and jt8052.

**Sprites per scanline from a list copied at vblank start — for approval.** The board had a frame
buffer (four 4464 beside the Pandora; MAME's double-buffered bitmap), so a frame buffer is
permitted by the standing rule. The line engine is proposed instead because:

- the output is the same: MAME draws the list as it stands at vblank start and shows it for the
  next frame; a copy at vblank start drawn line by line over that frame shows the same pixels;
- the sweep shows the list complete by line 89 in every run, so the copy at line 240 is never
  half-written;
- the worst measured line fits in under 40% of the line;
- it saves about 112 M10K and needs no frame swap.

The cost: a list that puts more than about 190 entries on one line would overrun, where the chip
would not. MAME's sets never came near (73). The engine drops the entries it has not reached,
which MAME draws on top; an overrun counter on the debug page reports it. If a set is found
overrunning, the frame buffer is the fallback, with the Heavy Unit module as its model.
Trails (`set_clear_bitmap`) need the frame buffer; no in-scope set uses them.

**Two graphics layouts by address permutation.** Toaplan's and SemiCom's tile layouts differ in
pixel and row order within a 128-byte tile (snowbros.cpp 1823, 1869-1880). Proposed: reorder
SemiCom's graphics at download into the Toaplan order, so the engine has one decode. Proved
offline against MAME's decoded tiles before any build.

**No multiplies, no divides, in 2D pipelines.**

## Pitfalls that already bind decisions here

| Entry | What it binds here |
|---|---|
| "[Seta] A snapshot is a race with whoever writes the thing being copied" | the vblank copy of sprite RAM; the sweep says the 68000 is idle there, check in play on every SemiCom set |
| "[Seta] A back-to-front line buffer cannot drop the right sprites" | overrun drops the last entries, which are on top; counter required |
| "[GX] A per-line object scan that runs out of time drops sprites without an error" | the overrun counter |
| "Instantiate `TG68KdotC_Kernel` directly and own the bus interface" | 68000 wrapper |
| "[MS32] A T80 waiting on SDRAM is a slow Z80: repay the lost clock enables" | both sound boards |
| "[Seta] Back the RAM a power-on test walks at the size the map declares" | 16 KB vs 64 KB work RAM per board |
| "[Seta] In a `gfx_layout`, the first plane listed is the MSB of the pen" | the two layouts |
| "Prove the interleave against MAME's disassembly offline, before building" | `ROM_LOAD16_BYTE` pairs, cookbib3's `ROM_CONTINUE`, toto and 4in1boot bit swaps |

## Phased roadmap

**Phase 0 — Vendoring and the measurements. The gate.**

Vendor the modules in the reuse map with `PROVENANCE.md`; run each one's existing bench
unchanged. Exit criteria:

1. Every vendored module's own tests pass unchanged. — Met for TG68K, jt8052, jt6295 and the
   SDRAM controller (`rtl/PROVENANCE.md`); jt51, jtopl, T80 have no bench anywhere, checked in Phase 3.
2. The 68000 runs snowbros and its bus trace matches MAME's. — Met from a restored state
   rather than from reset: the boot's RAM test is 3.9 million accesses before the first I/O
   (about 45 minutes of ModelSim). Restored from MAME at frame 600 and run 5 frames
   (`sim/state_tb`, `docs/STATE.md`): snowbros 13790 of 13790 writes in order, 35 of 35 I/O
   reads, every MAME ROM read, 15 of 15 interrupt entries; hyperpac 16415 of 16415, 25 of 25,
   15 of 15. Registers, work RAM, palette and sprite RAM equal to MAME's at the end, both sets.
   From reset, the first 200000 accesses of snowbros match (12702 of 12702 writes, `sim/boot_tb`).
3. The interrupt vectors and the 0x200000 / 0x500006 reads confirmed from each set's ROM. — Met:
   levels 2-4 autovectored in all 15 local in-scope sets, several into protection code in work
   RAM; constants read as the driver says (toto 0x0700, 4in1boot 0x0202, cookbib3 0x2A2A,
   3in1semi/mcheonru/moremore/moremorp 0x000A), read-tapped over 1500 frames in MAME.
4. ~~The pixel clock chosen with the user.~~ Met: 5.333 MHz, 354 x 262.
5. The SemiCom layout permutation proved offline. — Met against MAME's two layout definitions
   (`scripts/gfx_layout_check.py`): a nibble swap plus a fixed byte-address-bit permutation;
   6144 of 6144 hyperpac and 10240 of 10240 cookbib2 tiles decode identically. Not yet
   compared with MAME's rendered pixels (Phase 1).

**Phase 1 — Video, against a software model.** `render_model.py` reproducing `kan_pand.cpp` and
pixel-exact against MAME captures; then the RTL against the model in Verilator: snapshot,
resolver, line engine, palette. Exit: snowbros and hyperpac frames pixel-identical to MAME for a
captured set of scenes, attract and play, silent, in simulation. — Met: `scripts/render_model.py`
pixel-exact against MAME on 35 of 35 frames, and `sim/video_tb` (`scripts/video_frames.sh`)
pixel-exact against MAME's screenshots on the same 35 with no overruns: snowbros (attract, play,
Flip Screen on in both), hyperpac, pzlbreak (bg_pen 0xC0), and the most-loaded frame of twinkle,
pzlbreak, moremore and cookbib2 in `docs/sprite_load_mame.txt`. MAME's frame N is drawn from the
list of vblank N-1. Graphics are stored row-linear, one 64-bit granule a tile row
(`scripts/gfx_layout_check.py`).

**Phase 2 — Hardware bring-up and the first games.** SDRAM clients, ROM download, `.mra`
generation, inputs and DIPs, the MCU (hyperpac), `protdata` (cookbib3), the ISSP probe and debug
page, and the standard features (hiscore excepted, by the user's decision): CRT Adjust, fast DDR ROM loading, HDMI scaling and
crop, rotation, audio mix, Pause, flip from the OSD or the DIP (a fake DIP on SemiCom, which has
none) through the Pandora's flip, checked against the unflipped frame rotated 180 degrees. Exit:
snowbros, hyperpac and cookbib3 boot and play on a DE10-nano, silent.

**Phase 3 — Sound.** Toaplan Z80 + YM3812; SemiCom Z80 + YM2151 + M6295. Exit: register-write
traces from MAME reproduce, and judged by ear on the board. — In progress. `scripts/mame_sndtrace.py`
captures the latch, YM and M6295 writes from MAME; `sim/sound_tb` replays the latch at MAME's
times into the RTL board. Toaplan (snowbros): 29127 of 29127 chip writes match MAME in order
over 2.85 s, timing within 0.046 ms. SemiCom (hyperpac): 1541 of 1541 over 900 ms, within 0.037 ms,
the 68000's commands from 614 ms included. A second of game time takes about 30 minutes in
ModelSim. Built (slack +4.139 ns, 233 of 553 RAM blocks, 44% of the ALMs) and deployed as
`Pandora_30000003.rbf`. On the board: snowbros sounds right to the user; hyperpac not yet heard.

**Phase 4 — The rest of the list, and accuracy.** Every in-scope set and clone `.mra`, per-set
constants, `bg_pen`, toto and 4in1boot ROM transforms. `MAME_KLUDGES.md` and `HACKS.md` current. — In progress. `.mra` files for finalttr, toppyrap, pzlbreak,
suhosong, twinkle, 3in1semi, mcheonru, moremore, moremorp and 4in1boot (pzlbreaka, twinklea,
3in1semia: no zip here). Three input layouts (mod 1 bits 4 and 5) and finalttr's 3.579545 MHz
sound clock (bit 6). Checked: the Pandora model on 33 MAME frames of these sets, 0 pixels differ;
the download into the SDRAM model, 0 words differ for all ten, the protdata copy 0 of 256 words;
the 68000 from a MAME state: I/O reads and writes match MAME until an interrupt lands a few
instructions apart (TG68K's timing), and five frames on toppyrap, pzlbreak, moremore, moremorp and
4in1boot hold MAME's state but for one counter word; finalttr, twinkle, 3in1semi and mcheonru
drift further (`debug/<set>-state`). 4in1boot's bit swap was on the wrong byte of each word
until this check (`docs/LESSONS_LEARNED.md`). finalttr's sound board at its own clocks: 2561 of 2561 chip writes match MAME over 700 ms, drift at most 0.223 ms (`debug/finalttr-snd`). Built from `b7eb104` (slack +3.714 ns, 233 of 553 RAM blocks) and deployed as `Pandora_30000004.rbf` with fifteen `.mra` files. On the board: finalttr reaches attract mode (`debug/hw/finalttr_zip.png`; black until its zip, missing from the device with the nine other new sets', was copied: `scripts/deploy.py` now lists missing zips); hyperpac still runs on this build (`debug/hw/hyperpac_b4.png`). toppyrap and pzlbreak look and sound right to the user (`debug/hw/toppyrap_first.png`, `debug/hw/pzlbreak_first.png`; pzlbreak's coin input took the user's coin); suhosong, twinkle, 3in1semi, mcheonru, moremore and moremorp too (`debug/hw/<set>_first.png`; 3in1semi's mirrored title is MAME's too, frame 1900). 4in1boot too (`debug/hw/4in1boot_first.png`). Released as `releases/Arcade-Pandora_20261020.rbf` (the `81a53e3` build, with HDMI rotation) with the fifteen `.mra` files. Not yet played on the board: inputs beyond a coin, DIPs, flip.

**Phase 5 — The rest of the driver.** Proposed, awaiting approval. From MAME master's
`snowbros.cpp` and `snowbros_v.cpp`; ROM sets here: yutnori, sutjarod, gwasu, honeydol, twinadv,
snowbro3 (wintbob, snowbroswb, twinadvk, multi96, ballboy, ballboy3p missing).

- **5a. Pandora boards, no new chips.**
  - yutnori: mamedev/mame#16478 (merged) replaces the old stub with high-level emulation of the
    undumped PIC: the protection reply is the request byte inverted, nibbles swapped; the sound
    is two M6295s at 2 MHz, driven from a one-byte command at 0x400001 (a sample table, music
    banking and looping, a two-part sentence). In RTL: a small command sequencer in front of two
    jt6295, no Z80. Its own map (palette 0x500000, work RAM 0x700000), 8 MHz 68000, 1.1 MB of
    graphics. The reference needs a MAME built from master; `E:\mame` predates the PR.
    `MACHINE_IMPERFECT_SOUND` in MAME, so the sound is MAME's guess (`MAME_KLUDGES.md`).
  - sutjarod, gwasu: the semiprot board as is; MAME gets them playable by patching the ROM
    (`init_sutjarod`, `init_gwasu`, both marked `HACK`) and marks them `MACHINE_NOT_WORKING`.
    The patches go in the `.mra` as `<patch>`, logged as MAME kludges.
- **5b. Bootleg sprite boards, 4bpp.** twinadv (and twinadvk, multi96): an 8-word sprite entry
  with no chaining, Z80 + M6295, 12 MHz 68000; wintbob (and snowbroswb): its own entry format and
  `gfx_wb` layout, the Toaplan sound board, 10 MHz 68000. Each is a new list front end ahead of
  the existing line engine; neither needs a frame buffer (MAME draws the list whole at update,
  as for the Pandora).
- **5c. 8bpp boards.** honeydol: two lists interleaved, one 8bpp (2 MB `gfx2`) and one 4bpp,
  1024 palette entries, Z80 + YM3812 + M6295. snowbro3 (and ballboy, ballboy3p): 256 entries
  with relative positioning, the first 256 drawn 8bpp from a 4 MB `gfx2`, 60 Hz with 256 lines
  (`set_size(32*8, 32*8)`), and sound that MAME emulates at a high level for an undumped MCU
  (`MACHINE_IMPERFECT_SOUND`). The line engine needs an 8bpp path (16 bytes, two granules, a
  tile row); the SDRAM's graphics window grows past 2 MB, so the `.mra` layout changes with a
  new core.

Each sub-phase: references from MAME captures, the model first, benches, then the board, as in
Phases 1-4.

5a done. The references come from MAME master built as a `snowbros.cpp` subtarget
(`E:\mame-pandora\pandora.exe`, 0.289-1676). yutnori: the Pandora model pixel-exact on 3 of 3
frames; its sound against MAME's voice states, 44 of 44 starts and 42 of 42 stops over 41 s
(`sim/yut_tb`); the 68000 from a MAME state matches to an interrupt-timing point, five frames on
3 work-RAM words differ; the download, 0 SDRAM words differ. sutjarod, gwasu: the model 3 of 3
frames each; the download with MAME's ROM patches, 0 SDRAM words differ, protdata 0 of 256; from
a MAME state, gwasu five frames on holds MAME's state but for the raster clock, sutjarod's
diverges from an interrupt taken at a different instruction (1850 work-RAM words five frames
on; cause past that not established). On the board (release revision of `459c954`) all three run, per the user. Buttons for all three are
A, B, C until named from play in MAME.

**Phase 6 — Savestates, state dumps and cheats.** The state file and the 68000's register
capture exist from Phase 0 (`docs/STATE.md`); every RAM is BRAM behind a borrowable port, and
the board's DDR3 slots and dump path come with the top level. This phase is the shipped
savestate menu and cheats.

## Verification strategy

- MAME drives every reference from scripts: boot traces, sprite RAM and palette dumps at known
  frames, register-write logs.
- The software model is checked against MAME first, the RTL against the model.
- Graphics layouts checked before ROMs: every bit of a tile exactly once.
- `.mra` files generated from the driver and re-read against an image built from `ROM_START`.
- The line engine's overrun counter and the worst line are measured in the RTL.

## Repository setup

Seeded from MiSTer-devel/Template_MiSTer, `Template.*` renamed to `Pandora.*`, `Pandora_stp`
added, Quartus 13 project dropped. Quartus 17.0.2.

## Open items

~~**The pixel clock and horizontal total.**~~ Closed: 5.333 MHz x 354 x 262, the user's choice.
A PCB measurement of the horizontal total would still settle MAME's 262 lines.

~~**Frame buffer or line engine.**~~ Closed: line engine, the user's choice.

~~**Scope.**~~ Closed as proposed.

**Sound ROM in BRAM or SDRAM.** 32-64 KB; decided on the M10K count after Phase 0.

**Palette writes mid-frame on snowbros** (lines 138-153, under one a frame). MAME renders the
frame at its end with the palette then in force; a live palette in the RTL can differ for the
lines below the write. Checked against MAME captures in Phase 1.

## Next steps

1. ~~User approves the scope, the clock and the sprite shape.~~
2. Phase 0.
