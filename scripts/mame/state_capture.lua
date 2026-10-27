-- SPDX-License-Identifier: GPL-3.0-or-later
-- Capture the machine's state at entries of the level-4 interrupt handler, for
-- scripts/mame_state.py. The first fetch of the handler is an instruction boundary on any
-- 68000, MAME's or the RTL's: the registers are the interrupted program's, SR and A7 are the
-- exception's, PC is the handler, and level 4 is still asserted (the handler acknowledges it).
--
--   ST_PREFIX  output path prefix: <prefix>_<k>.sbst per capture, <prefix>.trace
--   ST_ARM     frame from which handler entries are counted
--   ST_EVERY   capture at entries 0, EVERY, 2*EVERY, ... after ST_ARM
--   ST_N       captures to take, then exit
--   ST_TRACE   bus accesses to log after the first capture (0: none)
--   ST_WRAM    work RAM bytes (16384 or 65536)
--   ST_ZRAM    Z80 RAM base, hex: 8000 (sound_map, 200-204) or d000 (hyperpac_sound_map, 358-365)
--   ST_COIN    frame to coin up and start, then hold right and pulse button 1 (0: attract)
--   ST_SET, ST_SOURCE   written into the manifest
--   ST_LOAD    a state file to apply at the first entry counted, before that entry's capture
--              (registers, work RAM, palette, sprite RAM, the latches the board holds). MAME's
--              interrupt lines cannot be set from Lua: the file's pending levels are checked
--              against MAME's and a difference is reported.
--
-- Sections and their meaning: docs/STATE.md.

local PREFIX = os.getenv("ST_PREFIX")
local ARM    = tonumber(os.getenv("ST_ARM") or "600")
local EVERY  = tonumber(os.getenv("ST_EVERY") or "60")
local NCAP   = tonumber(os.getenv("ST_N") or "2")
local TRACE  = tonumber(os.getenv("ST_TRACE") or "0")
local WRAM   = tonumber(os.getenv("ST_WRAM") or "16384")
local COIN   = tonumber(os.getenv("ST_COIN") or "0")
local SET    = os.getenv("ST_SET") or "?"
local SOURCE = os.getenv("ST_SOURCE") or "mame"

local mach = manager.machine
local cpu  = mach.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = mach.screens[":screen"]
local zcpu = mach.devices[":soundcpu"]       -- nil on yutnori
-- yutnori_map: work RAM 0x700000, palette 0x500000, the Pandora 0x600000; 0x400001 is its sound
-- command and 0x300000 its inputs, so no flip or latch
local YUT      = mach.system.name == "yutnori"
local WRAM_BASE = YUT and 0x700000 or 0x100000
local PAL_BASE  = YUT and 0x500000 or 0x600000
local SPR_BASE  = YUT and 0x600000 or 0x700000

local VTOTAL, LINE_CLK = 262, 3186            -- the RTL raster: 354 x 9 clk_sys a line
local frame_period = 1.0 / scr.refresh
local line_period = frame_period / VTOTAL
local function raster()
    local pos = (frame_period - scr:time_until_pos(0)) / line_period
    pos = pos % VTOTAL
    local line = math.floor(pos)
    return line, math.floor((pos - line) * LINE_CLK), pos
end
local function now() return mach.time:as_double() end

local ISR = prog:read_u32(0x70)               -- level 4 autovector

-- acknowledges, and the latches the board holds
local last_ack = {[2] = -1, [3] = -1, [4] = -1}
local flip_w, latch_w = 0x80, 0               -- flip bit 7 set = not flipped (snowbros.cpp 89-93)
_G.__st_taps = {
    prog:install_write_tap(0x800000, 0x800001, "ack4", function(o, d, m) last_ack[4] = now(); return d end),
    prog:install_write_tap(0x900000, 0x900001, "ack3", function(o, d, m) last_ack[3] = now(); return d end),
    prog:install_write_tap(0xa00000, 0xa00001, "ack2", function(o, d, m) last_ack[2] = now(); return d end),
}
if not YUT then
    _G.__st_taps[#_G.__st_taps + 1] = prog:install_write_tap(0x400000, 0x400001, "flip",
        function(o, d, m) if m & 0xff00 ~= 0 then flip_w = d >> 8 end; return d end)
    _G.__st_taps[#_G.__st_taps + 1] = prog:install_write_tap(0x300000, 0x300001, "latch",
        function(o, d, m) if m & 0x00ff ~= 0 then latch_w = d & 0xff end; return d end)
end

local function pending(level, assert_line, pos)
    local since = (pos - assert_line) % VTOTAL
    return last_ack[level] < now() - since * line_period
end

local function load_state(path)
    local f = assert(io.open(path, "rb"))
    local b = f:read("a"); f:close()
    assert(b:sub(1, 4) == "SBST", path .. ": not a state file")
    local ver, mlen = string.unpack(">I2I4", b, 5)
    local man = b:sub(11, 10 + mlen)
    local off, sec = 11 + mlen, {}
    for name, width, depth in man:gmatch('"name":"([%w_]+)","width":(%d+),"depth":(%d+)') do
        width, depth = tonumber(width), tonumber(depth)
        local fmt, nb, w = width == 32 and ">I4" or width == 16 and ">I2" or ">I1", width // 8, {}
        for i = 0, depth - 1 do w[i] = string.unpack(fmt, b, off + i * nb) end
        sec[name] = w
        off = off + depth * nb
    end
    return sec
end

local function apply(sec, pos)
    local st, r = cpu.state, sec.m68k_regs
    for i = 0, 7 do st["D" .. i].value = r[i] end
    for i = 0, 6 do st["A" .. i].value = r[8 + i] end
    st["USP"].value = r[15]
    st["SP"].value = r[18]
    st["SR"].value = r[19]
    for i = 0, #sec.wram do prog:write_u16(WRAM_BASE + 2 * i, sec.wram[i]) end
    for i = 0, 255 do prog:write_u16(PAL_BASE + 2 * i, sec.palette[i]) end
    for i = 0, 4095 do prog:write_u16(SPR_BASE + 2 * i, sec.spriteram[i]) end
    flip_w = (sec.board[1] & 1) << 7
    latch_w = sec.board[2]
    local pend = (pending(4, 32, pos) and 4 or 0) | (pending(3, 128, pos) and 2 or 0) |
                 (pending(2, 240, pos) and 1 or 0)
    print(string.format("LOAD %s: PC %06x SR %04x; pending %x in the file, %x in MAME%s", os.getenv("ST_LOAD"),
        r[20], r[19], sec.board[0], pend, sec.board[0] == pend and "" or "  MISMATCH"))
    if r[20] ~= ISR then print("LOAD MISMATCH: the file's PC is not this handler's entry") end
end

local LOAD = os.getenv("ST_LOAD")

local function capture(k)
    local line, hclk, pos = raster()
    local st = cpu.state
    local r = {}
    for i = 0, 7 do r[#r + 1] = st["D" .. i].value end
    for i = 0, 6 do r[#r + 1] = st["A" .. i].value end
    r[#r + 1] = st["USP"].value
    r[#r + 1] = 0; r[#r + 1] = 0               -- VBR, CACR: none on a 68000
    r[#r + 1] = st["SP"].value                 -- A7, supervisor
    r[#r + 1] = st["SR"].value
    r[#r + 1] = ISR                            -- PC
    r[#r + 1] = 0; r[#r + 1] = 0               -- frame format, stopped

    local pend = (pending(4, 32, pos) and 4 or 0) | (pending(3, 128, pos) and 2 or 0) |
                 (pending(2, 240, pos) and 1 or 0)
    -- reading 0x300001 has no side effect on the Z80-to-68000 latch (generic_latch_8 read)
    local board = {pend, (flip_w >> 7) & 1, latch_w, YUT and 0 or prog:read_u8(0x300001), line, hclk}

    local secs, payload = {}, {}
    local function add(name, width, words)
        secs[#secs + 1] = string.format('{"name":"%s","width":%d,"depth":%d}', name, width, #words)
        local fmt = width == 32 and ">I4" or width == 16 and ">I2" or ">I1"
        local t = {}
        for i = 1, #words do t[i] = string.pack(fmt, words[i]) end
        payload[#payload + 1] = table.concat(t)
    end
    add("m68k_regs", 32, r)
    add("board", 16, board)
    local w = {}
    for i = 0, WRAM / 2 - 1 do w[#w + 1] = prog:read_u16(WRAM_BASE + 2 * i) end
    add("wram", 16, w)
    local p = {}
    for i = 0, 255 do p[#p + 1] = prog:read_u16(PAL_BASE + 2 * i) end
    add("palette", 16, p)
    local s = {}
    for i = 0, 4095 do s[#s + 1] = prog:read_u16(SPR_BASE + 2 * i) & 0xff end
    add("spriteram", 8, s)
    if zcpu then
        local zs, zr = zcpu.state, {}
        for _, n in ipairs({"AF", "BC", "DE", "HL", "AF2", "BC2", "DE2", "HL2", "IX", "IY", "SP", "PC",
                            "I", "R", "IFF1", "IFF2", "IM", "WZ"}) do zr[#zr + 1] = zs[n].value & 0xffff end
        add("z80_regs", 16, zr)
        local zp, zm = zcpu.spaces["program"], {}
        local lo, n = tonumber(os.getenv("ST_ZRAM") or "8000", 16), 0x800
        for i = 0, n - 1 do zm[#zm + 1] = zp:read_u8(lo + i) end
        add("z80_ram", 8, zm)
    end

    local man = string.format('{"set":"%s","source":"%s","event":{"kind":"irq4_entry","index":%d,' ..
        '"frame":%d,"line":%d,"hclk":%d,"isr":%d,"mame_pc":%d,"mame_curpc":%d},"sections":[%s]}',
        SET, SOURCE, k, scr:frame_number(), line, hclk, ISR, cpu.state["PC"].value,
        cpu.state["CURPC"].value, table.concat(secs, ","))
    local f = assert(io.open(string.format("%s_%d.sbst", PREFIX, k), "wb"))
    f:write("SBST", string.pack(">I2I4", 1, #man), man, table.concat(payload))
    f:close()
    print(string.format("STATE %d: frame %d line %d hclk %d PC %06x SR %04x pend %x",
        k, scr:frame_number(), line, hclk, ISR, r[20], pend))
end

-- the bus trace after the first capture, in mame_boot_trace's format
local tf, tn = nil, 0
local function trace_tap(rw)
    return function(offset, data, mask)
        if tf and tn < TRACE then
            tn = tn + 1
            tf:write(string.format("%d\t%s\t%06X\t%04X\t%04X\n", tn, rw, offset & 0xffffff, mask, data))
            if tn == TRACE then tf:write("# end\n"); tf:close(); tf = false end
        end
        return data
    end
end

local armed, entries, taken, busy = false, 0, 0, false
_G.__st_isr = prog:install_read_tap(ISR, ISR + 1, "isr", function(o, d, m)
    if armed and not busy then
        busy = true
        if entries == 0 and LOAD and LOAD ~= "" then
            local _, _, pos = raster()
            local ok, err = pcall(function() apply(load_state(LOAD), pos) end)
            if not ok then print("LOAD ERROR: " .. tostring(err)); mach:exit() end
        end
        if entries % EVERY == 0 then
            local ok, err = pcall(capture, taken)
            if not ok then print("STATE ERROR: " .. tostring(err)); mach:exit() end
            taken = taken + 1
            if taken == 1 and TRACE > 0 then
                tf = assert(io.open(PREFIX .. ".trace", "w"))
                tf:write("# main-CPU bus accesses from the first capture, seq rw addr mask data\n")
                _G.__st_trace = {prog:install_read_tap(0, 0xffffff, "trd", trace_tap("r")),
                                 prog:install_write_tap(0, 0xffffff, "twr", trace_tap("w"))}
            end
            if taken >= NCAP and (tf == nil or tf == false) then mach:exit() end
        end
        entries = entries + 1
        busy = false
    end
    return d
end)

local function field(name)
    for _, port in pairs(mach.ioport.ports) do
        local f = port.fields[name]
        if f then return f end
    end
end
local fc, fs, fr, fb = field("Coin 1"), field("1 Player Start"), field("P1 Right"), field("P1 Button 1")
local n = 0
_G.__st_frame = emu.add_machine_frame_notifier(function()
    n = n + 1
    if n == ARM then armed = true end
    if COIN > 0 then
        if n == COIN then fc:set_value(1) elseif n == COIN + 5 then fc:clear_value() end
        if n == COIN + 60 then fs:set_value(1) elseif n == COIN + 65 then fs:clear_value() end
        if n > COIN + 65 then fr:set_value(1); if (n % 20) < 3 then fb:set_value(1) else fb:clear_value() end end
    end
    if taken >= NCAP and tf ~= nil and tf ~= false and n > ARM + 600 then tf:close(); mach:exit() end
    if n > ARM + 3600 then print("STATE ERROR: no handler entry in 3600 frames"); mach:exit() end
end)
