-- Randomizer behaviour on the test disk (FX_TICKS = 120: 2-second effects).
local T = dofile("tests/mame/lib.lua")

local function starts() return T.peek(T.ST_STARTS) end
local function ticks() return T.peek16(T.TICKS) end
local function changed_from(s) return function() return starts() ~= s end end

T.run(function()
  T.check(T.wait_until(T.running, 60 * 20), "After Dusk never started")

  -- 1. Left alone for 40 s: effects keep changing, never the same twice running.
  local s0, prev, last, repeats = starts(), starts(), T.peek(T.ST_FX), 0
  for _ = 1, 60 * 40 do
    coroutine.yield()
    if starts() ~= prev then
      local fx = T.peek(T.ST_FX)
      if fx == last then repeats = repeats + 1 end
      T.check(fx <= 5, "effect id out of range: " .. fx)
      last, prev = fx, starts()
    end
  end
  local n = (starts() - s0) % 256
  T.info("effects started in 40 s: " .. n)
  T.check(n >= 15, "only " .. n .. " effects in 40 s")
  T.check(repeats == 0, repeats .. " back-to-back repeats")

  -- 2. A key in the middle of an effect skips within half a second.
  for k = 1, 20 do
    T.check(T.wait_until(function() local t = ticks(); return t >= 4 and t < 60 end, 60 * 10),
            "never reached the middle of an effect")
    local s = starts()
    T.press(" ")
    T.check(T.wait_until(changed_from(s), 30), "key " .. k .. " did not skip within 30 frames")
    T.wait_frames(30)
  end

  -- 3. A key during the wipe skips that effect exactly once.
  T.check(T.wait_until(function() return ticks() >= 122 end, 60 * 30), "never caught a wipe")
  local s = starts()
  T.press(" ")
  T.check(T.wait_until(changed_from(s), 60), "key during the wipe did not skip")
  local s2 = starts()
  T.wait_frames(60)
  T.check(starts() == s2, "key during the wipe skipped more than once")

  -- 4. A burst of five keys: at most five skips, and it keeps running.
  local s3 = starts()
  T.press("abcde")
  T.wait_frames(60 * 3)
  local skips = (starts() - s3) % 256
  T.info("skips after a burst of 5 keys: " .. skips)
  T.check(skips >= 1 and skips <= 6, "burst caused " .. skips .. " effect changes")
  local b = T.peek16(T.ST_BEAT)
  T.wait_frames(30)
  T.check(T.peek16(T.ST_BEAT) ~= b, "stopped running after the burst")

  if not T.failed then T.pass("randomizer") end
end)
