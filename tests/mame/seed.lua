-- Boots once and reports the seed HELLO handed over. tests/test_mame.py runs
-- this twice on the same disk image (MAME saves the disk when it exits) and
-- checks that the second boot got a different seed. (A hard reset inside one
-- run would be simpler, but MAME rebuilds the machine and crashes the script.)
local T = dofile("tests/mame/lib.lua")
T.run(function()
  T.check(T.wait_until(T.running, 60 * 20), "After Dusk never started")
  T.info("seed=" .. T.peek16(T.SEED))
  if not T.failed then T.pass("seed") end
end)
