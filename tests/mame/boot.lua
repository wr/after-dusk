-- The disk boots on its own into After Dusk: hi-res on, program running.
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.check(T.wait_until(T.running, 60 * 20), "After Dusk never started")
  T.wait_frames(60)
  T.check(T.hires_on(), "hi-res is not on")
  local b1 = T.peek16(T.ST_BEAT)
  T.wait_frames(60)
  T.check(T.peek16(T.ST_BEAT) ~= b1, "status heartbeat is not advancing")
  T.snap("boot")
  if not T.failed then T.pass("boot") end
end)
