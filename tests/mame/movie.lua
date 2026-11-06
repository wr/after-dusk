-- Every frame of one effect, for the README's animations (tools/make-gifs.sh):
--   AD_FX=0 AD_SECS=10 mame apple2c ... -autoboot_script tests/mame/movie.lua
-- Skips effects until AD_FX is showing, waits AD_WAIT seconds (default 2),
-- then snapshots every frame for AD_SECS seconds (default 10) as f0000.png,
-- f0001.png... in the snapshot directory.
local T = dofile("tests/mame/lib.lua")
local want = tonumber(os.getenv("AD_FX") or "0")
local wait = tonumber(os.getenv("AD_WAIT") or "2")
local secs = tonumber(os.getenv("AD_SECS") or "10")
-- Shown on a green monochrome monitor, as on a IIc's own.
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
  T.wait_seconds(wait)
  for n = 0, math.floor(secs * 60) - 1 do
    T.snap(string.format("f%04d", n))
    T.wait_frames(1)
  end
  if not T.failed then T.pass("movie " .. want) end
end)
