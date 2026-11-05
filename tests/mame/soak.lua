-- Hours of running on the release disk: every emulated minute the program
-- is still running, in hi-res, on a valid effect; at the end every effect
-- has appeared, none followed itself, and effects lasted 3 minutes on average.
-- (The speaker guard in lib.lua fails the run on any speaker access.)
local T = dofile("tests/mame/lib.lua")
local HOURS = tonumber(os.getenv("AD_SOAK_HOURS") or "8")
T.run(function()
  T.wait_started()
  local NFX = T.peek(T.label("fx_count"))
  local seen, starts, first_frame, last_frame = {}, 0, nil, nil
  local prev_st, last_fx, repeats = T.peek(T.ST_STARTS), T.peek(T.ST_FX), 0
  local minutes = math.floor(HOURS * 60)
  for m = 1, minutes do
    local b = T.peek16(T.ST_BEAT)
    for _ = 1, 60 * 60 do
      coroutine.yield()
      local st = T.peek(T.ST_STARTS)
      if st ~= prev_st then
        local fx = T.peek(T.ST_FX)
        if fx == last_fx then repeats = repeats + 1 end
        if last_frame and os.getenv("AD_SOAK_LOG") then
          T.info(string.format("effect %d lasted %.1f s", last_fx, (T.frame - last_frame) / 60))
        end
        seen[fx] = true
        starts = starts + 1
        first_frame = first_frame or T.frame
        last_frame = T.frame
        prev_st, last_fx = st, fx
      end
    end
    if not T.check(T.peek16(T.ST_BEAT) ~= b, "stopped at minute " .. m) then break end
    if not T.check(T.peek(T.ST_FX) < NFX, "bad effect id at minute " .. m) then break end
    if not T.check(T.hires_on(), "hi-res off at minute " .. m) then break end
    if T.failed then break end
  end
  for i = 0, NFX - 1 do T.check(seen[i], "effect " .. i .. " never appeared") end
  T.check(repeats == 0, repeats .. " back-to-back repeats")
  if starts >= 2 then
    local avg = (last_frame - first_frame) / (starts - 1) / 60
    T.info(string.format("%d effects; average %.1f s each", starts, avg))
    T.check(math.abs(avg - 180) <= 5, "effects average " .. avg .. " s, not 3 minutes")
  else
    T.fail("only " .. starts .. " effect changes")
  end
  if not T.failed then T.pass("soak " .. HOURS .. " h") end
end)
