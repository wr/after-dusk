-- Screenshots of one effect for a person to look at:
--   AD_FX=0 tests/mame/run.sh apple2c tests/mame/shots.lua 90
-- Skips effects until AD_FX is showing, then takes three snapshots two
-- seconds apart into build/mame/snap/ as fx<id>-<n>.png.
local T = dofile("tests/mame/lib.lua")
local want = tonumber(os.getenv("AD_FX") or "0")
-- Wells's IIc has a green monochrome monitor.
local mon = T.mac.ioport.ports[":a2video:a2_video_config"].fields["Monitor type"]
mon.user_value = 5
T.run(function()
  T.wait_started()
  for _ = 1, 60 do
    if T.peek(T.ST_FX) == want and T.peek16(T.TICKS) < 2000 then break end
    T.press(" ")
    T.wait_frames(45)
  end
  T.check(T.peek(T.ST_FX) == want, "could not reach effect " .. want)
  T.wait_seconds(3)
  for n = 1, 3 do
    T.snap(string.format("fx%d-%d", want, n))
    T.wait_seconds(2)
  end
  if not T.failed then T.pass("shots " .. want) end
end)
