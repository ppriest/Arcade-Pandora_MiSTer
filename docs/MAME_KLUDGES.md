# MAME kludges this core reproduces

This project follows MAME, including where MAME is wrong (ROADMAP, "Design decisions"), so the
software model and the RTL reproduce MAME's guesses on purpose. This file lists each one that
touches an in-scope set: where it is in MAME, what the core does, and what would settle the real
behaviour.

It also records where a vendored, silicon-derived module disagrees with MAME and the module was
kept (ROADMAP, "Where a vendored module and MAME disagree").

This core's own approximations are not here; they are in `HACKS.md`.

Source references are to `src/mame/kaneko/snowbros.cpp` unless named. MAME commit:
`dedb5227403` (`mame0289-1527`; the driver differs from the `mame0289` tag in API and comments only).

**Core column:** *copies* MAME; *differs* (and why); *n/a* (not in the core's scope);
*not checked*.

The in-scope sets are `MACHINE_SUPPORTS_SAVE` with no imperfection flags (`GAME` lines 3341-3375).

## CPU and timing

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| 262 lines at 57.5 Hz | 1945-1948: `set_refresh_hz(57.5)`, `set_size(32*8, 262)`; the PCB notes give HSync 15.68 kHz (35-36), which is about 273 lines | copies: 262 lines, `rtl/video/video_timing.sv`; interrupts at lines 32, 128, 240 as `scanline` (127-139) | A PCB measurement of line count and interrupt lines |

## Video

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| Sprite code wrapped at the tile count | drawgfx takes `code % elements()`; the Pandora's 14-bit code exceeds every set's tile count (4096 for snowbros) | copies: `rtl/video/pandora_resolve.sv` subtracts the tile count; on the board the ROM decode would mirror at a power of two instead, which differs for sets with 6144, 10240 or 13312 tiles | A capture of a code beyond the tile count in a real game, or the board's ROM decoding |
| The Pandora's bitmap as MAME's double buffer | `kan_pand.cpp` 82: "4 64x4 DRAMs - 256x256 8 bit, double buffered"; drawn whole at vblank start, shown the next frame | the same frame, drawn a line at a time from the list fixed at vblank start (`rtl/video/pandora_line.sv`); identical pixels, 35 of 35 frames | — (trails, `set_clear_bitmap`, are never used by this driver) |

## Protection

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| `protdata` copied at reset | `MACHINE_RESET semiprot` (1915-1921), `finalttr` (1923-1929): 512 bytes extracted from shared RAM stand in for the undumped 87C52 | to copy, Phase 2 | A dump of the MCUs |
| sutjarod's and gwasu's program ROM patched | `init_sutjarod`, `init_gwasu` (marked `HACK`): the RAM decrypt key replaced with cookbib3's, and a word at 0x54 set so the ROM checksum stays 0; both sets `MACHINE_NOT_WORKING`, "playable, but left as not working until protection data is extracted" | copies: the `.mra`'s `<patch>` elements, read from the driver by `scripts/build_mra.py` (`rom_patches`) | Their own `protdata`, extracted from a PCB |
| yutnori's PIC | `yutnori_prot_r` (the request byte inverted, nibbles swapped) and the sound: `yutnori_sound_hle_w`, `yutnori_scanline`, `yutnori_voice_update` (mamedev/mame#16478), a sample table, music on channel 0 restarted at line 0, a two-part sentence; both M6295 at 2 MHz, "not verified"; the set is `MACHINE_IMPERFECT_SOUND` | copies: `rtl/cpu/maincpu.sv` (`prot_q`), `rtl/sound/yutnori_sound.sv`; 44 of 44 voice starts match MAME's (`sim/yut_tb`) | A dump of the PIC16C64A, or recordings of the PCB |

## Vendored modules that disagree with MAME

| Module | MAME says | The module does | Kept because | Would settle it |
|---|---|---|---|---|
None so far.
