# jt6295 (OKI M6295) provenance

jotego's jt6295 (https://github.com/jotego/jt6295, `master` at commit
`7d76b0be8cd8f85f3ae741178c9830b20e2071a1`), copied from Arcade-Fuuki_MiSTer
`rtl/sound/jt6295/` (`hdl/` and `LICENSE`) at Fuuki commit
`8e706177f38dd43064db8341e6b2e07da627ba54`. The same `hdl/*.v` is in the Eolith, Vamphalf,
NixPirates and GStream cores (diffed: identical, apart from the extra files listed below).
Unchanged.

`jt12_comb.v` and `jt12_interpol.v` are jt12 modules jt6295 carries for its optional
interpolator (`INTERPOL`); there is no jt12 tree in this core, so this copy of them is the one
compiled. `jt6295.qip` and `jtframe_fir4.m` are not used (the qip names a jtframe file that is
not here).

**Licence: GPL-3.0** (`LICENSE`).

## Use here

Two M6295 at 1 MHz with pin 7 low (dreamwld.cpp lines 826, 838). The ROM bus is a level
interface (`rom_addr` out, `rom_data`/`rom_ok` in) that expects data within two `cen32` ticks
of the address changing; Fuuki's `rtl/sound/sample_cache.sv` is the worked answer for serving
that from SDRAM.

## Tests

The upstream repository's benches were not part of the copy. `sim/oki_tb` plays a phrase from
dreamwld's OKI ROM and checks the status bit and the output.
