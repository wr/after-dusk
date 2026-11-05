-- Randomizer behaviour on the test disk (FX_TICKS = 120: 2-second effects).
local T = dofile("tests/mame/lib.lua")

local function starts() return T.peek(T.ST_STARTS) end
local function ticks() return T.peek16(T.TICKS) end
local function changed_from(s) return function() return starts() ~= s end end
local function beat() return T.peek16(T.ST_BEAT) end

-- Wait until the current effect is really running: it has taken at least
-- 3 steps since it started (so its wipe and set-up are over) and has plenty
-- of its time left.
local function wait_mid_effect()
  local st, b0 = starts(), beat()
  return T.wait_until(function()
    if starts() ~= st then st, b0 = starts(), beat() end
    return (beat() - b0) % 65536 >= 3 and ticks() < 60
  end, 60 * 10)
end

T.run(function()
  T.wait_started()

  -- 1. Left alone for 40 s: effects keep changing, never the same twice running.
  local s0, prev, last, repeats = starts(), starts(), T.peek(T.ST_FX), 0
  for _ = 1, 60 * 40 do
    coroutine.yield()
    if starts() ~= prev then
      local fx = T.peek(T.ST_FX)
      if fx == last then repeats = repeats + 1 end
      T.check(fx < T.peek(T.label("fx_count")), "effect id out of range: " .. fx)
      last, prev = fx, starts()
    end
  end
  local n = (starts() - s0) % 256
  T.info("effects started in 40 s: " .. n)
  T.check(n >= 12, "only " .. n .. " effects in 40 s")
  T.check(repeats == 0, repeats .. " back-to-back repeats")

  -- 2. A key in the middle of an effect skips within half a second.
  for k = 1, 20 do
    T.check(wait_mid_effect(), "never reached the middle of an effect")
    local s, fx, t0 = starts(), T.peek(T.ST_FX), T.frame
    T.press(" ")
    local ok = T.wait_until(changed_from(s), 90)
    T.check(ok and T.frame - t0 <= 30, string.format(
      "key %d did not skip within 30 frames (effect %d, took %d)", k, fx, T.frame - t0))
    T.wait_frames(30)
  end

  -- 3. A key during the wipe skips that effect exactly once. (After the
  -- wipe the effect still sets up, up to about a second for Starry Night,
  -- before its first step notices the key.)
  T.check(T.wait_until(function() return ticks() >= 122 end, 60 * 30), "never caught a wipe")
  local s = starts()
  T.press(" ")
  T.check(T.wait_until(changed_from(s), 120), "key during the wipe did not skip")
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
