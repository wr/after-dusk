-- Fish! (effect 14) runs at its rate: one step a frame. On a trial disk
-- (ONLY_FX=14) it shows from power-on; after the wipe and init, 300 frames
-- hold 300 steps on the IIc (within 3%: pacing.lua's band) and, without its
-- vertical-blank latch, within -17%..+22% on an enhanced IIe (Review Focus
-- 5; the step pads itself to about a tick there).
--   tests/mame/run.sh apple2c tests/mame/fish_rate.lua 60 build/FISH-A-2DOT.dsk
--   tests/mame/run.sh apple2ee tests/mame/fish_rate.lua 60 build/FISH-A-2DOT.dsk
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.wait_started()
  T.check(T.wait_until(function() return T.peek(T.ST_FX) == 14 end, 600), "Fish! never came up")
  T.wait_frames(120)                        -- past the wipe and init
  local timing = T.peek(T.ST_TIMING)
  local b1 = T.peek16(T.ST_BEAT)
  T.wait_frames(300)
  local steps = (T.peek16(T.ST_BEAT) - b1) % 65536
  T.info(string.format("effect 14: %d steps in 300 frames (vertical blank %d)", steps, timing))
  if timing == 1 then
    T.check(steps >= 291 and steps <= 309, "Fish! runs at the wrong rate on the IIc")
  else
    T.check(steps >= 249 and steps <= 366, "Fish! runs at the wrong rate without a vertical blank")
  end
  if not T.failed then T.pass("fish_rate") end
end)
