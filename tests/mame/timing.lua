-- The IIc's vertical blank is found and paces every step to whole ticks:
-- over 600 frames an effect takes 600 / ticks_per_step steps.
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.wait_started()
  T.wait_frames(60)
  T.check(T.peek(T.ST_TIMING) == 1, "vertical-blank pacing not detected (fell back to delays)")
  local st, b1 = T.peek(T.ST_STARTS), T.peek16(T.ST_BEAT)
  T.wait_frames(600)
  T.check(T.peek(T.ST_STARTS) == st, "the effect changed during the measurement")
  local per = T.peek(T.label("fx_table") + T.peek(T.ST_FX) * 6 + 5)
  local steps = (T.peek16(T.ST_BEAT) - b1) % 65536
  T.info(string.format("effect %d: %d steps in 600 frames at %d ticks per step",
                       T.peek(T.ST_FX), steps, per))
  T.check(math.abs(steps - 600 / per) <= 2, "expected " .. 600 / per .. " +/- 2 steps")
  if not T.failed then T.pass("timing") end
end)
