# Pandora state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## The state file

One format for MAME, the simulators and the board: `scripts/state.py` reads and writes it.

```
"SBST"  u16 version (1)  u32 manifest length          big-endian
manifest  JSON: set, source ("mame 0.289", "rtl <commit>"), event, sections [{name, width, depth}]
payload   each section in manifest order, depth big-endian words of width bits
```

A reader takes the sections it knows by name and ignores the rest. `event` says where the state
was taken: `{"kind": "irq4_entry", "index", "frame", "line", "hclk", ...}`.

**Restore point: the first fetch of the level-4 interrupt handler** (line 32). It is an
instruction boundary on MAME's 68000 and on TG68K.C. The registers are the interrupted
program's, SR and A7 are the exception's, PC is the handler, and level 4 is still asserted, because the
handler acknowledges it. MAME's own PC register still reads the vector address (0x70) there,
so the file's PC is the handler's address from the vector table.

| Section | Width x depth | Contents |
|---|---|---|
| `m68k_regs` | 32 x 23 | gx_ss_m68k's bank order: 0-7 D0-D7, 8-14 A0-A6, 15 USP, 16-17 0 (VBR, CACR), 18 A7 (supervisor, as the program has it), 19 SR, 20 PC, 21 0, 22 bit 0 stopped |
| `board` | 16 x 6 | 0 pending interrupts {4, 3, 2}; 1 flip (1 = not flipped, bit 7 of the 0x400000 write); 2 latch to the Z80; 3 latch from the Z80; 4 raster line; 5 raster clock within the line (48 MHz clocks, 0-3185) |
| `wram` | 16 x 8192 or 32768 | work RAM, 16 KB (Toaplan, finalttr) or 64 KB (SemiCom) |
| `palette` | 16 x 256 | 0x600000-0x6001FF |
| `spriteram` | 8 x 4096 | the Pandora's RAM |
| `z80_regs` | 16 x 18 | AF BC DE HL AF' BC' DE' HL' IX IY SP PC I R IFF1 IFF2 IM WZ; MAME only so far |
| `z80_ram` | 8 x 2048 | 0x8000 (Toaplan) or 0xD000 (SemiCom); MAME only so far |

The raster position is where the CPU entered the handler. TG68K.C is not cycle-exact, so that
clock differs from MAME's by a few tens of CPU cycles. `compare` reports it, and nothing
depends on it.

## Moving a state

```
python scripts/mame_state.py snowbros --arm 600 --every 5 --n 2 --trace 400000
    -> debug/snowbros-state/mame_<k>.sbst, mame.trace          MAME, from frame 600
python scripts/state.py to-sim debug/snowbros-state/mame_0.sbst debug/snowbros-state/in
scripts/run_sim.sh state_tb +IN=debug/snowbros-state/in +OUT=debug/snowbros-state/out \
    +EVERY=5 +IN1=7ffe +IN2=7fff +IN3=ff00 +MAXACC=400000
python scripts/state.py from-sim debug/snowbros-state/out debug/snowbros-state/rtl_1.sbst \
    --set snowbros --source rtl
python scripts/state.py compare debug/snowbros-state/mame_1.sbst debug/snowbros-state/rtl_1.sbst
python scripts/compare_boot_trace.py compare snowbros --mame debug/snowbros-state/mame.trace \
    --rtl debug/snowbros-state/out/rtl.trace
python scripts/mame_state.py snowbros --arm 605 --every 5 --n 2 \
    --load debug/snowbros-state/rtl_1.sbst --out debug/snowbros-state/load   sim -> MAME
```

The bench restores RAM with `$readmemh` while the CPU is held, and the registers and pending
interrupts through maincpu's state ports, the ports the board's engine will use. MAME's
interrupt lines cannot be set from Lua: a load into MAME checks that the file's pending levels
are MAME's at that point and reports a difference.

The board side (DDR3 slots, `SS` in CONF_STR, a dump over the debug path) waits for the top
level (Phase 2). Its image is these sections, written by an engine on KonamiGX's
`gx_savestate.sv` pattern.

## RAMs

| Region | RTL | Width x depth | Bytes | Save? |
|---|---|---|---|---|
| work RAM | outside maincpu (bench model so far) | 16 x 8192 / 32768 | 16 / 64 KB | yes |
| palette | outside maincpu | 16 x 256 | 512 | yes |
| sprite RAM | `snowbros_video.spr_ram` | 8 x 4096 | 4 KB | yes |
| palette | `snowbros_video.pal_lo`, `pal_hi` | 2 x 8 x 256 | 512 | yes (the `palette` section) |
| resolved list | `snowbros_video.list_ram` | 41 x 512 | 2.6 KB | yes, section to add: the rest of the frame is drawn from it, and by line 32 the 68000 has started rewriting sprite RAM (sweep: lines 26-89). MAME's equivalent is the Pandora's drawn bitmap, which the MAME side can rebuild by resolving `spriteram` of the previous vblank |
| line buffers | `jtframe_obj_buffer` in `pandora_line` | 2 x 8 x 512 | 1 KB | no: refilled within two lines |

## Registers and FSMs

| What | RTL | Bits | Save? | MAME `save_item` equivalent |
|---|---|---|---|---|
| 68000 registers | TG68K.C through `gx_ss_m68k` (MODE 2) | 23 x 32 | yes | the CPU's own |
| pending interrupts | `maincpu.irq_pend` | 3 | yes, `ss_irq_*` | the CPU's input lines |
| flip | top level (Phase 2) | 1 | yes | `m_flip_screen` (kan_pand.cpp) |
| sound latches | top level (Phase 3) | 2 x 8 | yes | `generic_latch_8` |
| raster position | `video_timing` | line 9, pixel 9, divider 4 | yes, `ss_line`/`ss_hcnt`/`ss_div`; the file's clock is pixel * 9 + divider | the screen |

## Chip state

| Chip | Module | Addressable? | Tier | Note |
|---|---|---|---|---|
| Z80 | T80 (Phase 3) | yes: `REG` out, `DIR`/`DIRSet` in | exact | MAME's section is already in the file |
| YM3812 | jtopl2 | no | 1: register replay | MAME's internals are not reachable from Lua either |
| YM2151 | jt51 | no | 1: register replay | |
| M6295 | jt6295 | partly | 1 | |
| 87C52 | jt8052 | to be checked | | hyperpac, cookbib2: its RAM and ports |

## Deliberately skipped

| What | Why it need not be saved |
|---|---|
| program, sprite, sample ROMs | from the `.mra` |
| protdata image | copied at reset; the copy is in work RAM |

## Frame alignment

The restore point is the level-4 entry at line 32, inside the visible area (16-239). The
sprite list copy happens at vblank start (line 240), so no copy is in progress at the restore;
the copy itself must be in the image, since the rest of the frame is drawn from it. The line
engine's two buffered lines are not state: the lines after a restore are drawn afresh.
