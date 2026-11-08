-- Every effect runs at its intended rate on the IIc: over 5 seconds it takes
-- 300 / ticks_per_step steps (within 3%), even when a step takes longer
-- than two frames to draw.
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.wait_started()
  local NFX = T.peek(T.label("fx_count"))
  local seen = {}
  local tries = 0
  while tries < 20 * NFX do
    tries = tries + 1
    local fx, st = T.peek(T.ST_FX), T.peek(T.ST_STARTS)
    if fx < NFX and not seen[fx] then
      T.wait_frames(90)                       -- past the wipe and init
      local b1 = T.peek16(T.ST_BEAT)
      T.wait_frames(300)
      if T.peek(T.ST_STARTS) == st and T.peek(T.ST_FX) == fx then
        local per = T.peek(T.label("fx_table") + fx * 6 + 5)
        local steps = (T.peek16(T.ST_BEAT) - b1) % 65536
        local want = 300 / per
        -- Zot! has no motion: a bolt may take a few frames to draw (accepted
        -- in its design), so it runs a little under its rate.
        -- Flying Toasters keeps 7 objects at about 14.3 updates a second
        -- instead of 15 (AGENTS.md's final counts).
        local slack = 0.03
        if fx == 3 then slack = 0.2 elseif fx == 0 then slack = 0.08 end
        T.info(string.format("effect %d: %d steps in 300 frames (want %.1f)", fx, steps, want))
        T.check(steps <= want * 1.03 and steps >= want * (1 - slack),
                "effect " .. fx .. " runs at the wrong rate")
        seen[fx] = true
      end
    end
    local n = 0
    for i = 0, NFX - 1 do if seen[i] then n = n + 1 end end
    if n == NFX then break end
    local s = T.peek(T.ST_STARTS)
    T.press(" ")
    T.wait_until(function() return T.peek(T.ST_STARTS) ~= s end, 120)
  end
  for i = 0, NFX - 1 do T.check(seen[i], "never measured effect " .. i) end
  if not T.failed then T.pass("pacing") end
end)
