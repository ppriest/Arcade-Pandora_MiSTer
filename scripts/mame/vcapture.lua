-- Video captures for scripts/render_model.py, driven by scripts/mame_vcapture.py.
--
--   VC_OUT     output directory; one subdirectory per frame
--   VC_FRAMES  "f1,f2,..." frames to capture, ascending
--   VC_COIN    frame to coin up and start, then hold right and pulse button 1 (0: attract)
--
-- At each listed frame N, from the frame notifier (MAME's vblank start): spriteram.bin (the
-- Pandora's 4 KB as the 68000 reads it, one byte a word) for frames N-1 and N, palette.bin,
-- the last flip byte written, and MAME's screenshot of frame N. Which sprite list frame N
-- shows is for the model to establish against the screenshot, not assumed here.

local OUT    = os.getenv("VC_OUT")
local COIN   = tonumber(os.getenv("VC_COIN") or "0")
local want = {}
for f in string.gmatch(os.getenv("VC_FRAMES") or "", "(%d+)") do want[tonumber(f)] = true end

local m    = manager.machine
local prog = m.devices[":maincpu"].spaces["program"]
local scr  = m.screens[":screen"]
-- yutnori_map moves the palette to 0x500000 and the Pandora to 0x600000, and has no flip
-- register (0x400001 is its sound command)
local YUT      = m.system.name == "yutnori"
local SPR_BASE = YUT and 0x600000 or 0x700000
local PAL_BASE = YUT and 0x500000 or 0x600000
local function mkdir(p) os.execute('mkdir "' .. p:gsub("/", "\\") .. '" 2>nul') end

local function wr(path, s) local f = assert(io.open(path, "wb")); f:write(s); f:close() end
local function spr()
    local t = {}
    for i = 0, 4095 do t[#t + 1] = string.char(prog:read_u16(SPR_BASE + 2 * i) & 0xff) end
    return table.concat(t)
end
local function pal()
    local t = {}
    for i = 0, 255 do t[#t + 1] = string.pack(">I2", prog:read_u16(PAL_BASE + 2 * i)) end
    return table.concat(t)
end

local flip = 0x80
_G.__vc_taps = YUT and {} or {prog:install_write_tap(0x400000, 0x400001, "flip",
    function(o, d, mask) if mask & 0xff00 ~= 0 then flip = d >> 8 end; return d end)}

local function field(name)
    for _, port in pairs(m.ioport.ports) do
        local f = port.fields[name]
        if f then return f end
    end
end
local fc, fs, fr, fb = field("Coin 1"), field("1 Player Start"), field("P1 Right"), field("P1 Button 1")

local last, prev_spr, maxf = nil, nil, 0
for f in pairs(want) do if f > maxf then maxf = f end end
_G.__vc_frame = emu.add_machine_frame_notifier(function()
    local ok, err = pcall(function()
        local n = scr:frame_number()
        if COIN > 0 then
            if n == COIN then fc:set_value(1) elseif n == COIN + 5 then fc:clear_value() end
            if n == COIN + 60 then fs:set_value(1) elseif n == COIN + 65 then fs:clear_value() end
            if n > COIN + 65 then fr:set_value(1); if (n % 20) < 3 then fb:set_value(1) else fb:clear_value() end end
        end
        local s = spr()
        if want[n] then
            local d = string.format("%s/%05d", OUT, n)
            mkdir(d)
            wr(d .. "/spriteram_prev.bin", prev_spr or s)
            wr(d .. "/spriteram.bin", s)
            wr(d .. "/palette.bin", pal())
            wr(d .. "/flip.txt", string.format("%d\n", flip))
            scr:snapshot(d .. "/reference.png")
            print(string.format("VCAP %d", n))
        end
        prev_spr = s
        if n >= maxf then m:exit() end
    end)
    if not ok then print("VCAP ERROR " .. tostring(err)); m:exit() end
end)
