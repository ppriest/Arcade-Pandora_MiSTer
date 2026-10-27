# Third-party code and licences

**This project is GPL-3.0-or-later.** `LICENSE` carries the GPLv3 text. jtopl, jt51, jt6295, jt8052,
jtframe, the SDRAM controller and CRT Adjust are GPL-3.0 or GPL-3.0-or-later, so the whole is GPL-3;
code can come in from GPL-2-or-later MiSTer cores, not go back out (Arcade-KonamiGX_MiSTer's
`THIRD-PARTY.md`, "Why GPL-3, and why it is one-way").

`rtl/PROVENANCE.md` lists every vendored module with the sibling core and commit it was copied from;
each vendored directory's own `PROVENANCE.md` names the upstream source and every local change. This
file records what each dependency obliges.

## Dependencies

### Sibling cores - GPL-3.0-or-later

The repository was seeded from Template_MiSTer; the top level (`Pandora.sv`), the memory modules
(`rtl/memory/`), the sound ROM path and the scripts follow Arcade-DreamWorld_MiSTer at `233d1f2`,
itself from Arcade-Psikyo_MiSTer. `rtl/cpu/gx_ss_m68k.sv` comes from Arcade-KonamiGX_MiSTer at
`89124d4` (modified, marked `[SB]`). Same author and licence as this project. Obligations: publish
the source.

### TG68K.C - LGPL-3.0-or-later

<https://github.com/TobiFlex/TG68K.C> at `ade33e396a1e647c2de9daf71ff9d5b3979639b2`, via
Arcade-KonamiGX_MiSTer: `rtl/cpu/tg68k/` (`rtl/cpu/tg68k/PROVENANCE.md`). LGPL-3.0 code in a GPL-3.0
work is direct. Obligations: publish the source, keep its headers and change notices.

### MiSTer-devel/T80 - BSD-style

<https://github.com/MiSTer-devel/T80> at `830fd0315f0af5cdbcb0e703f1cea3ce4e91f538`, via
Arcade-Fuuki_MiSTer: `rtl/cpu/t80/`, one change marked `[SB]` (`rtl/cpu/t80/PROVENANCE.md`).
Obligations: keep the copyright notices in each file.

### jotego/jtopl - GPL-3.0

<https://github.com/jotego/jtopl> at `7ac0c819ad274e208206f2acccbbde80aa06ed1a`, via
Arcade-Fuuki_MiSTer: `rtl/sound/jtopl/`, unmodified (`rtl/sound/jtopl/PROVENANCE.md`). Obligations:
publish the source.

### jotego/jt51 - GPL-3.0

jotego's JT51 (`jtcores`, `modules/jt51` at `985a573dcfc1ff135553a39f7eae21d18ba57cbe`), via
Arcade-Vamphalf_MiSTer: `rtl/sound/jt51/`, unmodified. Obligations: publish the source.

### jotego/jt6295 - GPL-3.0

<https://github.com/jotego/jt6295> at `7d76b0be8cd8f85f3ae741178c9830b20e2071a1`, via
Arcade-DreamWorld_MiSTer: `rtl/sound/jt6295/`, unmodified (`rtl/sound/jt6295/PROVENANCE.md`).
`oki_rom_bridge.sv` and `sample_cache.sv` (Fuuki's, after Psikyo's) feed its ROM bus. Obligations:
publish the source.

### jotego/JT8051 as jt8052 - GPL-3.0-or-later

jotego's JT8051 (`jtcores`, `modules/jt8051`), forked into an 8052 by the Eolith and Vamphalf cores,
via Arcade-DreamWorld_MiSTer: `rtl/mcu/jt8052/`, with local changes marked `[DW]` and `[SB]`
(`rtl/mcu/jt8052/PROVENANCE.md`). Obligations: publish the source, keep the change notices.

### jotego/jtframe - GPL-3.0-or-later

jtcores `modules/jtframe` at `451c630da78a`: the sprite line-drawing modules in `rtl/jtframe/`,
unmodified, with jtframe's `LICENSE`. Obligations: publish the source.

### Sorgelig's SDRAM controller - GPL-3.0-or-later

`rtl/memory/sdram/sdram.sv`: Sorgelig's `sdram.v`, extended for burst-4 reads;
`sdram_upstream_reference.sv` is the unmodified upstream for diffing
(`rtl/memory/sdram/PROVENANCE.md`). Obligations: publish the source, keep the change notices in its
header.

### rmonic79's CRT Adjust - GPL-3.0-or-later

`rtl/video/crt_adjust.sv` (from Arcade-Raiden_MiSTer, one local fix marked `LOCAL FIX` in the file)
and `rtl/video/crt_vsize.sv` (from MiSTer-CRT-Adjust at `c682de9`, unmodified). Obligations: publish the source,
keep the change notice.

### Sorgelig's screen rotation - GPL-2.0-or-later

`rtl/video/screen_rotate_two.sv`, unmodified. GPL-2.0-or-later into a GPL-3.0-or-later work is
direct.

### MiSTer-devel/Template_MiSTer - GPL-2.0-or-later (`sys/`)

The framework, unmodified, pinned at `5dda373` (57 files, byte-identical to upstream). Its grant is
"or later", which is what lets it combine with GPL-3 code. `sim/sd_tb/` carries bench copies of
four framework modules (`scandoubler_vl.v`, `video_mixer_vl.sv`, `hq2x_vl.sv`, `sync_fix.v`), each
header naming the one change made for the simulator; they are not built into the core.

## Reference material, not code

MAME (<https://github.com/mamedev/mame>, `src/mame/kaneko/snowbros.cpp`, `kan_pand.cpp` and the
devices they use, BSD-3-Clause and GPL-2.0-or-later per file) is the reference for the hardware's
behaviour; no MAME source is compiled into the core. yutnori's sound sequencer
(`rtl/sound/yutnori_sound.sv`) implements the behaviour of MAME's high-level stand-in for the
undumped PIC (mamedev/mame#16478). The `scripts/mame_*.py` tools and `scripts/mame/*.lua` drive
MAME for reference captures; `rtl/mame_keys.sv` takes MAME's default key list.

## Release checklist

- every `PROVENANCE.md` current, and each modified vendored file carries its change notice
- `sys/` unmodified against Template_MiSTer
- `LICENSE` is the GPLv3 text
