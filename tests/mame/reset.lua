-- Ctrl-Reset in the middle of an effect restarts After Dusk in hi-res.
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.wait_started()
  T.wait_frames(120)
  T.mac:soft_reset()
  T.wait_frames(2)
  T.check(T.wait_until(function() return T.running() and T.hires_on() end, 60 * 3),
          "not back in After Dusk within 3 s of a reset")
  local b = T.peek16(T.ST_BEAT)                 -- the next effect may take a
  T.check(T.wait_until(function() return T.peek16(T.ST_BEAT) ~= b end, 60 * 4),
          "not running after the reset")             -- second or two to set up
  T.check(T.hires_on(), "hi-res off after the reset")
  T.snap("after-reset")
  if not T.failed then T.pass("reset") end
end)
