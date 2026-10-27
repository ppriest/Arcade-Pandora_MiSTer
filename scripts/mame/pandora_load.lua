-- SPDX-License-Identifier: GPL-3.0-or-later
-- Pandora line load, for docs/sprite_load_mame.txt. Per frame, resolves the 512 entries
-- with the relative chaining of kan_pand.cpp draw() and counts the entries overlapping each
-- visible line (16..239) with sx in -15..255; writes the per-frame maximum as a histogram.
-- Blank tiles are counted: the count is an upper bound on what draws.
--   PL_OUT file   PL_SKIP frames before counting   PL_FRAMES frames counted
--   PL_COIN frame to coin up and start, then hold right and pulse button 1 (0 = attract)
local OUT = os.getenv("PL_OUT"); local SKIP = tonumber(os.getenv("PL_SKIP")); local FRAMES = tonumber(os.getenv("PL_FRAMES"))
local COIN = tonumber(os.getenv("PL_COIN") or "0")
local mach = manager.machine
local prog = mach.devices[":maincpu"].spaces["program"]
local n = 0
local worst, worst_frame, hist = 0, 0, {}
local per_frame_total = {}
local function field(name) for _, p in pairs(mach.ioport.ports) do local f = p.fields[name]; if f then return f end end end
local fc, fs, fr, fb = field("Coin 1"), field("1 Player Start"), field("P1 Right"), field("P1 Button 1")
local function sext9(v) v = v & 0x1ff; if v >= 0x100 then return v - 0x200 end; return v end
emu.register_frame_done(function()
  n = n + 1
  if COIN > 0 then
    if n == COIN then fc:set_value(1) elseif n == COIN + 5 then fc:clear_value() end
    if n == COIN + 60 then fs:set_value(1) elseif n == COIN + 65 then fs:clear_value() end
    if n > COIN + 65 then fr:set_value(1); if (n % 20) < 3 then fb:set_value(1) else fb:clear_value() end end
  end
  if n <= SKIP or n > SKIP + FRAMES then
    if n == SKIP + FRAMES + 1 then
      local f = io.open(OUT, "w")
      f:write(string.format("worst %d frame %d\n", worst, worst_frame))
      for k = 0, 512 do if hist[k] then f:write(string.format("hist %d %d\n", k, hist[k])) end end
      f:close(); mach:exit()
    end
    return
  end
  local cnt = {}
  for l = 16, 239 do cnt[l] = 0 end
  local x, y = 0, 0
  for e = 0, 511 do
    local b = e * 8
    local function rb(o) return prog:read_u16(0x700000 + 2 * (b + o)) & 0xff end
    local t3, dx, dy = rb(3), rb(4), rb(5)
    if t3 & 1 ~= 0 then dx = dx | 0x100 end
    if t3 & 2 ~= 0 then dy = dy | 0x100 end
    if t3 & 4 ~= 0 then x = x + dx; y = y + dy else x = dx; y = dy end
    local sx, sy = sext9(x), sext9(y)
    if sx > -16 and sx < 256 then
      for l = math.max(16, sy), math.min(239, sy + 15) do cnt[l] = cnt[l] + 1 end
    end
  end
  local m = 0
  for l = 16, 239 do if cnt[l] > m then m = cnt[l] end end
  hist[m] = (hist[m] or 0) + 1
  if m > worst then worst = m; worst_frame = n end
end)
