-- The IIc's vertical blank is found and paces the program: one step per
-- tick while the placeholder loop waits one tick per pass.
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.check(T.wait_until(T.running, 60 * 20), "After Dusk never started")
  T.wait_frames(60)
  T.check(T.peek(T.ST_TIMING) == 1, "vertical-blank pacing not detected (fell back to delays)")
  local b1 = T.peek16(T.ST_BEAT)
  T.wait_frames(600)
  local steps = (T.peek16(T.ST_BEAT) - b1) % 65536
  T.info("steps in 600 frames: " .. steps)
  T.check(math.abs(steps - 600) <= 6, "expected 600 +/- 6 steps, got " .. steps)
  if not T.failed then T.pass("timing") end
end)
