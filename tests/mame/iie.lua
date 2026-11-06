-- On an enhanced IIe (128K) the disk boots into After Dusk too. It has no
-- IIc vertical-blank latch, so it paces with delay loops, and its ROM must not
-- be taken for a IIc Plus's (that would make every effect four times slower).
-- A key still skips to the next effect.
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.wait_started()
  T.wait_frames(60)
  T.check(T.hires_on(), "hi-res is not on")
  T.check(T.peek(T.ST_TIMING) == 0, "found a vertical-blank latch on a IIe")
  T.check(T.peek(T.ST_FAST) == 0, "took the IIe for a IIc Plus")
  local b1 = T.peek16(T.ST_BEAT)
  T.wait_frames(60)
  T.check(T.peek16(T.ST_BEAT) ~= b1, "status heartbeat is not advancing")
  local s = T.peek(T.ST_STARTS)
  T.press(" ")
  T.check(T.wait_until(function() return T.peek(T.ST_STARTS) ~= s end, 120),
          "a key did not skip to the next effect")
  if not T.failed then T.pass("iie") end
end)
