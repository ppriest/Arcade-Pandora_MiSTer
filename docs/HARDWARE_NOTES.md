# Pandora: hardware notes

The Toaplan Snow Bros board and the boards that copy it, as MAME models them. Each fact cites its
source.

Source: MAME `src/mame/kaneko/snowbros.cpp`, `snowbros.h`, `snowbros_v.cpp`, `kan_pand.cpp` (line
numbers below), checkout at `mame0289-1527`. Since the `mame0289` tag `snowbros.cpp` has changed
only in the `SCREEN()` constructor (API), the yutnori MCU region declaration and two comments
(`git diff mame0289`); the other four files are unchanged. MAME 0.289 (`mame.exe -version`) is the
matching binary, and `-listxml` comes from it.

## Sets

39 sets in five board families (`GAME` lines 3341-3393). Bytes are loaded bytes, the sum of
the file sizes in `-listxml`; `NO_DUMP` regions are not counted.
"Local" is whether the set is in `MAME_ROMPATH` on this machine.

**Pandora boards.** The Kaneko Pandora sprite chip (`kan_pand.cpp`) is the only video.

| Set | Parent | Game | Config | maincpu | sound | gfx1 | oki1 | MCU | Flags | Local |
|---|---|---|---|---|---|---|---|---|---|---|
| snowbros | - | Snow Bros. (set 1), Toaplan 1990 | snowbros | 256 KB | 32 KB | 512 KB | - | - | good | yes |
| snowbrosa/b/c/j/d | snowbros | sets 2-4, Japan, Dooyong | snowbros | 256 KB | 32 KB | 512 KB | - | - | good | no |
| toto | - | Come Back Toto, SoftClub 1996 | snowbros | 256 KB | 32 KB | 512 KB | - | - | good | yes |
| 4in1boot | - | Puzzle King, K1 Soft 2002 | _4in1 | 1 MB | 64 KB | 2 MB | 256 KB | - | good | yes |
| hyperpac | - | Hyper Pacman, SemiCom 1995 | semicom_mcu | 256 KB | 64 KB | 768 KB | 256 KB | AT89C52, 8 KB, decapped | good | yes |
| hyperpacb | hyperpac | bootleg | semicom | 256 KB | 64 KB | 768 KB | 256 KB | - | good | no |
| cookbib2, cookbib2a | - | Cookie & Bibi 2, SemiCom 1996 | semicom_mcu | 512 KB | 64 KB | 1.25 MB | 128 KB | 87C52, 8 KB, laser-glitched | good | cookbib2 |
| cookbib2b, cookbib2c | cookbib2 | | semiprot | 512 KB | 64 KB | 1.25-1.5 MB | 128 KB | protdata | good | no |
| finalttr | - | Final Tetris, Jeil 1993 | finalttr | 256 KB | 64 KB | 1 MB | 128 KB | protdata | good | yes |
| toppyrap | - | Toppy & Rappy, SemiCom 1996 | semiprot | 512 KB | 64 KB | 2 MB | 128 KB | protdata | good | yes |
| cookbib3 | - | Cookie & Bibi 3, SemiCom 1997 | semiprot | 512 KB | 64 KB | 1.5 MB | 128 KB | protdata | good | yes |
| pzlbreak, pzlbreaka | - | Puzzle Break, SemiCom 1997 | semiprot | 256 KB | 64 KB | 1 MB | 256/128 KB | protdata | good | pzlbreak |
| suhosong | - | Suhoseong, SemiCom 1997 | semiprot | 256 KB | 64 KB | 1.5 MB | 256 KB | protdata | good | yes |
| twinkle, twinklea | - | Twinkle, SemiCom 1997 | semiprot | 256 KB | 64 KB | 512 KB | 256 KB | protdata | good | twinkle |
| 3in1semi, 3in1semia | - | New HyperMan 3-in-1, 1998 | semiprot | 512 KB | 64 KB | 2 MB / 1.6 MB | 256 KB | protdata | good | 3in1semi |
| mcheonru | - | Macheonlu, 1999 | semiprot | 512 KB | 64 KB | 2 MB | 256 KB | protdata | good | yes |
| moremore, moremorp | - | Puzzle Express More More (Plus), 1999 | semiprot | 512 KB | 64 KB | 2 MB | 256 KB | protdata | good | yes |
| sutjarod | - | Sutjaro Haeyo Deluxe, 1996 | semiprot | 128 KB | 64 KB | 1 MB | 128 KB | protdata | NOT_WORKING | yes |
| gwasu | - | Gwasuwon, 1997 | semiprot | 256 KB | 64 KB | 1 MB | 128 KB | protdata | NOT_WORKING | yes |
| yutnori | - | Puzzle Yutnori, Nunal 1999 | yutnori | 256 KB | - | 1.1 MB | 512 KB + 256 KB | PIC, no code | UNEMULATED_PROTECTION, NO_SOUND | yes |

"protdata" is a 512-byte image of what the undumped MCU leaves in shared RAM, copied to 0x10F000
(0x102000 for finalttr) at reset (`MACHINE_RESET semiprot` 1915-1921, `finalttr` 1923-1929); the MCU itself is not emulated.
sutjarod and gwasu are additionally patched in ROM (`init_sutjarod` 3263-3273, `init_gwasu`
3275-3284, marked `HACK`). Largest Pandora set: 4in1boot, 3.3 MB.

**Bootleg video boards.** No Pandora; each has its own sprite format in `snowbros_v.cpp`.

| Set | Parent | Video | Sound | Total | Flags | Local |
|---|---|---|---|---|---|---|
| wintbob, snowbroswb | snowbros | `screen_update_wintbob` (151-198), 16-byte entries, own gfx layout | as snowbros | 832 KB | good | no |
| honeydol | - | `screen_update_honeydol` (8-80): two interleaved lists, 4bpp and 8bpp | Z80 + YM3812 + OKI | 3.0 MB | good | yes |
| twinadv, twinadvk, multi96 | - | `screen_update_twinadv` (83-125) | Z80 + OKI, banked | 2.3 MB | good | twinadv |
| snowbro3, ballboy, ballboy3p | - | `screen_update_snowbro3` (201-245): 8bpp background tiles, 4 MB | OKI driven by an undumped MCU, HLE (369-462) | 5.3 MB | IMPERFECT_SOUND | snowbro3 |

## CPUs and chips

| Tag | Part | Clock | Configs | Existing RTL |
|---|---|---|---|---|
| maincpu | 68000 | 16 MHz / 2 = 8 MHz, "confirmed" (1933) | snowbros, yutnori | TG68K.C (Psikyo, Fuuki, Seta, DreamWorld); fx68k (Seta) |
| | | 12 MHz, "confirmed" (1998) | semicom and children, honeydol, twinadv, snowbro3 | |
| | | 10 MHz, "confirmed" (1984) | wintbob | |
| soundcpu | Z80 | 12 MHz / 2 = 6 MHz, "confirmed" (1939) | snowbros | T80 (Psikyo, Fuuki, MS32) |
| | | 16 MHz / 4 = 4 MHz, "confirmed" (2001) | semicom | |
| | | 3.579545 MHz (2141) | finalttr | |
| ymsnd | YM3812 | 12 MHz / 4 = 3 MHz, "confirmed" (1961) | snowbros, honeydol | jtopl2 (Fuuki) |
| ymsnd | YM2151 | 16 MHz / 4 = 4 MHz, "confirmed" (2012) | semicom | jt51 (Vamphalf) |
| oki1 | M6295 | 16 MHz / 16 = 1 MHz, pin 7 high, "confirmed" (2017) | semicom, honeydol, twinadv, snowbro3, yutnori | jt6295 (Fuuki, DreamWorld, Vamphalf) |
| protection | AT89C52 / 87C52 | 16 MHz (2026) | semicom_mcu: hyperpac, cookbib2, cookbib2a | jt8052 (DreamWorld, from Eolith) |
| pandora | Kaneko PX79C480FP-3 | not given | every Pandora config | `djboy_pandora.sv` (rmonic79/Arcade-DJBoy_MiSTer), `hvyunit_pandora.sv` (decoryah/Arcade-HeavyUnit_MiSTer); both GPL-3.0-or-later in the file headers |

The 87C52 on the semiprot sets is undumped (`NO_DUMP`, e.g. 2945-2946).

## Clocks

| Clock | Source |
|---|---|
| 16 MHz, 12 MHz XTAL | snowbros PCB layout (22, 24); semicom and twinadv PCB notes (2431, 2790) |
| 68000 8 MHz, Z80 6 MHz, YM3812 3 MHz | snowbros PCB notes (32-34) |
| VSync 57.5 Hz, HSync 15.68 kHz | snowbros PCB notes (35-36); the same figures in djboy.cpp (66-67) |
| `set_refresh_hz(57.5)`, 262 lines, vblank time 0 | `snowbros_base` (1945-1948) |

MAME gives no pixel clock and no horizontal total (`set_refresh_hz`, not `set_raw`). Its 262 lines
at 57.5 Hz is a 15.07 kHz line, against the PCB's measured 15.68 kHz; 15.68 kHz at 57.5 Hz is
272.7 lines. Candidate pixel clocks from the crystals, unverified:

| Pixel clock | Total for 15.68 kHz | With MAME's 262 lines at 57.5 Hz |
|---|---|---|
| 16 MHz / 3 = 5.333 MHz | 340 | 354 clocks a line, 57.50 Hz |
| 12 MHz / 2 = 6 MHz | 383 | 398 clocks a line, 57.54 Hz |

48 MHz divides both, and every other board clock exactly: 68000 8 MHz (/6) and 12 MHz (/4), Z80
6 MHz (/8) and 4 MHz (/12), YM3812 3 MHz (/16), YM2151 4 MHz (/12), M6295 1 MHz (/48), MCU 16 MHz
(/3). The odd ones are wintbob's 10 MHz (5/24) and finalttr's 3.579545 MHz.

## Video

Display: 256 x 262 total in MAME, visible 256 x 224, rows 16-239 (`set_visarea`, 1948), ROT0 for
every set. Aspect 4:3.

**Pandora** (`kan_pand.cpp`). 4 KB of sprite RAM, 512 entries of 8 bytes; bytes 0-2 unused
(134-149):

```
byte 3  [7:4] palette bank   [2] relative   [1] Y bit 8   [0] X bit 8
byte 4  X low   5  Y low   6  code low   7  [7] flip X  [6] flip Y  [5:0] code high
```

A relative entry adds its 9-bit dx/dy to the running x/y; the drawn position is
`sext9(x & 0x1ff)` (155-192). Entries are drawn in order, later over earlier, pen 0 transparent,
16 x 16 tiles, 14-bit code, 16 colour banks of 16. The 68000 sees the RAM at 0x700000-0x701FFF,
one byte per word on both lanes (`spriteram_lsb_w`, 248-260).

At vblank start (`eof`, 203-211) the chip swaps two 256 x 256 x 8 bitmaps, clears the new one to
`bg_pen` and draws the whole list into it; `screen_update` fills 0xF0 and copies that bitmap with
pen 0 transparent (snowbros.cpp 102-108, kan_pand.cpp 124-127). So the frame on screen is the list
as it stood at the vblank before it. MAME notes the chip as "4 64x4 DRAMs - 256x256 8 bit, double
buffered" (kan_pand.cpp 82), and the snowbros PCB layout shows four 4464 (64K x 4) beside the
Pandora (16-17): 128 KB, two such bitmaps. The board had a frame buffer.

`set_clear_bitmap` (trails) is never called by snowbros.cpp. `set_bg_pen` is: 0xC0 for pzlbreak
(3290), 0xF0 for yutnori (3336); the fill is opaque, so those games show that pen where no sprite
draws.

Graphics layout: `gfx_8x8x4_row_2x2_group_packed_msb` for snowbros, toto and 4in1boot (1823,
2155-2161); `hyperpac_tilelayout` for every SemiCom config and yutnori (1869-1880, 2005, 2212).
The two differ in pixel and row order within the 128-byte tile.

Palette: 256 entries xBGR_555 at 0x600000-0x6001FF (193, 1951).

Flip: snowbros writes `!BIT(data, 7)` of 0x400000 to the Pandora's flip (89-93), from a DIP
(570). hyperpac_map has no flip register; the hyperpac notes say there is no way to flip the
screen (44-45).

**Measured in MAME** (`docs/write_timing_mame.txt`, `docs/sprite_load_mame.txt`):

- Sprite RAM is written from about line 26 to line 89 (IRQ 4 is at line 32), never in vblank, in
  attract and in play, snowbros and hyperpac. A copy of the list at vblank start (line 240) is
  complete.
- snowbros writes the palette rarely and mid-frame (mostly lines 138-153, 0.1-1 writes a frame);
  hyperpac writes it in vblank.
- The most entries overlapping one visible line, X on screen, over every frame counted: 73
  (twinkle, pzlbreak, moremore in play), 64 cookbib2, 44 snowbros, 35 hyperpac. Blank tiles are
  counted, so this is an upper bound on what draws.

## Interrupts

Three 68000 levels, `ASSERT_LINE`, from `scanline` (127-139): level 4 at line 32, level 3 at
line 128, level 2 at line 240. Each is cleared by a write to its acknowledge address
(0x800000, 0x900000, 0xA00000; `irq_ack_w`, 119-123). snowbros: the sound latch's data-pending
pulses the Z80 NMI (1957), and the YM3812 IRQ is the Z80 INT (1962). semicom: no NMI
(`set_nop`, 2007); the YM2151 IRQ is the Z80 INT (2013).

## Memory map

snowbros_map (182-198):

| Range | Contents |
|---|---|
| 000000-03FFFF | ROM |
| 100000-103FFF | work RAM, 16 KB |
| 200000 | watchdog |
| 300001 | w: sound latch to Z80; r: latch from Z80 |
| 400000 | flip, bit 7 inverted |
| 500000-500005 | DSW1, DSW2, SYSTEM (inputs share these words, 598-640) |
| 600000-6001FF | palette |
| 700000-701FFF | Pandora sprite RAM |
| 800000, 900000, A00000 | IRQ 4, 3, 2 acknowledge |

hyperpac_map (341-356): ROM to 0FFFFF, work RAM 100000-10FFFF (64 KB, shared with the MCU), sound
latch write only, no watchdog or flip; the rest as above. finalttr_map (491-507) has 16 KB of RAM.
3in1semi, mcheonru, moremore (3247-3250), cookbib3 (3253-3261) and 4in1boot (3218) return a
constant from 0x200000; toto returns 0x0700 from 0x500006 (3322-3323).

Sound, snowbros (200-212): ROM 0000-7FFF, RAM 8000-87FF; I/O 02-03 YM3812, 04 latch r/w.
Sound, semicom (358-365): ROM 0000-CFFF, RAM D000-D7FF, F000-F001 YM2151, F002 M6295, F008 latch.

The protection MCU on hyperpac and cookbib2 writes the 68000's work RAM through ports: P2 is the
word offset, P0 and P1 the low and high byte, from 0x10E000 (hyperpac, 3329) or 0x10F000
(cookbib2, 3184) (`prot_p0_w`-`prot_p2_w`, 218-237).

ROM transforms done at load in MAME: toto swaps bits 3 and 4 of every byte of maincpu, gfx1 and
soundcpu (3295-3320); 4in1boot swaps bits 6 and 7 of odd maincpu bytes (the 68000 high byte: MAME byte-swaps the region on a little-endian host) and XORs the sound ROM
address with 0x4000 (3193-3217); cookbib3 loads its sound ROM in reversed 16 KB quarters with
`ROM_CONTINUE` (2940-2943).
