-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sound traces for scripts/mame_sndtrace.py: what the 68000 sends the sound board and what the
-- sound CPU writes to its chips, each with MAME's time in ns.
--
--   SN_OUT     output file
--   SN_FRAMES  frames to run
--   SN_COIN    frame to coin up and start, then hold right and pulse button 1 (0: attract)
--   SN_BOARD   "toaplan" (sound_io_map: YM3812 at I/O 02-03), "semicom"
--              (hyperpac_sound_map: YM2151 at F000-F001, M6295 at F002) or "yutnori" (no sound
--              CPU: yutnori_sound_hle_w drives two M6295s from the 68000's byte at 0x400001)
--
-- Lines: "<ns> L <byte>" a latch write by the 68000 (0x300001); "<ns> Y <a0> <byte>" a YM write;
-- "<ns> O <byte>" an M6295 write. yutnori: "<ns> C <byte>" a nonzero command; at each frame end
-- "<ns> S <chip> <voice> <start>" a voice that started (its position went back, or its start
-- address changed, since the last frame), "<ns> E <chip> <voice>" one that stopped, and
-- "<ns> B <chip> <bank>" a bank change. The HLE's chip writes are C++ calls, not bus writes,
-- so the voices' save-state items stand in for them; two starts of one voice in one frame show
-- as one.

local OUT    = os.getenv("SN_OUT")
local FRAMES = tonumber(os.getenv("SN_FRAMES") or "1200")
local COIN   = tonumber(os.getenv("SN_COIN") or "0")
local BOARD  = os.getenv("SN_BOARD") or "toaplan"

local mach = manager.machine
local main = mach.devices[":maincpu"].spaces["program"]
local snd  = mach.devices[":soundcpu"]   -- nil on yutnori
local f = assert(io.open(OUT, "w"))
local function ns() return string.format("%.0f", mach.time:as_double() * 1e9) end

_G.__sn = {main:install_write_tap(0x300000, 0x300001, "lat", function(o, d, m)
	if m & 0x00ff ~= 0 then f:write(ns(), " L ", string.format("%02x", d & 0xff), "\n") end
	return d
end)}
local voices = {}
if BOARD == "yutnori" then
	_G.__sn = {main:install_write_tap(0x400000, 0x400001, "cmd", function(o, d, m)
		if m & 0x00ff ~= 0 and d & 0xff ~= 0 then f:write(ns(), " C ", string.format("%02x", d & 0xff), "\n") end
		return d
	end)}
	for chip, tag in ipairs({":oki1", ":oki2"}) do
		local it = mach.devices[tag].items
		local function item(name) return emu.item(it[name]) end
		local v = {bank = item("0/m_cur_bank"), last_bank = -1}
		for ch = 0, 3 do
			local pre = ch .. "/m_voice[voicenum]."
			v[ch] = {base = item(pre .. "m_base_offset"), pos = item(pre .. "m_sample"),
			         play = item(pre .. "m_playing"), lb = -1, lp = 0, lplay = 0}
		end
		voices[chip] = v
	end
elseif BOARD == "toaplan" then
	_G.__sn[#_G.__sn + 1] = snd.spaces["io"]:install_write_tap(0x02, 0x03, "ym", function(o, d, m)
		f:write(ns(), " Y ", o & 1, " ", string.format("%02x", d & 0xff), "\n")
		return d
	end)
else
	_G.__sn[#_G.__sn + 1] = snd.spaces["program"]:install_write_tap(0xf000, 0xf002, "ym", function(o, d, m)
		if o == 0xf002 then f:write(ns(), " O ", string.format("%02x", d & 0xff), "\n")
		else f:write(ns(), " Y ", o & 1, " ", string.format("%02x", d & 0xff), "\n") end
		return d
	end)
end

local function field(name)
	for _, port in pairs(mach.ioport.ports) do
		local x = port.fields[name]
		if x then return x end
	end
end
local fc, fs, fr, fb = field("Coin 1"), field("1 Player Start"), field("P1 Right"), field("P1 Button 1")
local n = 0
_G.__sn_frame = emu.add_machine_frame_notifier(function()
	n = n + 1
	if COIN > 0 then
		-- two coins: yutnori's default coinage is 2 coins 1 credit
		if n == COIN or n == COIN + 15 then fc:set_value(1) elseif n == COIN + 5 or n == COIN + 20 then fc:clear_value() end
		if n == COIN + 60 then fs:set_value(1) elseif n == COIN + 65 then fs:clear_value() end
		if n > COIN + 65 then fr:set_value(1); if (n % 20) < 3 then fb:set_value(1) else fb:clear_value() end end
	end
	for chip, v in ipairs(voices) do
		local b = v.bank:read(0)
		if b ~= v.last_bank then f:write(ns(), " B ", chip - 1, " ", b, "\n"); v.last_bank = b end
		for ch = 0, 3 do
			local x = v[ch]
			local base, pos, play = x.base:read(0), x.pos:read(0), x.play:read(0)
			if play ~= 0 and (x.lplay == 0 or pos < x.lp or base ~= x.lb) then
				f:write(ns(), " S ", chip - 1, " ", ch, " ", string.format("%05x", base), "\n")
			elseif play == 0 and x.lplay ~= 0 then
				f:write(ns(), " E ", chip - 1, " ", ch, "\n")
			end
			x.lb, x.lp, x.lplay = base, pos, play
		end
	end
	if n >= FRAMES then f:close(); mach:exit() end
end)
