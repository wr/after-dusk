-- Shared helpers for After Dusk's MAME tests. A test does:
--   local T = dofile("tests/mame/lib.lua")
--   T.run(function() T.wait_frames(600); T.check(...); T.pass("name") end)
-- T.run drives the function as a coroutine, one resume per emulated frame.
-- Every test also fails if After Dusk's own code touches the speaker.

local T = {}
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
T.mac, T.mem = mac, mem
T.frame = 0

-- Status block and switches (see src/config.inc)
T.ST_FX, T.ST_STARTS, T.ST_BEAT, T.ST_TIMING, T.ST_FAST = 0x0310, 0x0311, 0x0312, 0x0314, 0x0315
T.SEED = 0x0300

T.TICKS = 0x22

-- Addresses from the linker's label file (same layout for every build).
local labels
function T.label(name)
  if not labels then
    labels = {}
    for line in io.lines("build/afterdusk.lbl") do
      local addr, sym = line:match("^al (%x+) %.(%S+)")
      if addr then labels[sym] = tonumber(addr, 16) end
    end
  end
  return labels[name]
end

function T.peek(a) return mem:read_u8(a) end
function T.peek16(a) return mem:read_u8(a) + 256 * mem:read_u8(a + 1) end
function T.poke(a, v) mem:write_u8(a, v) end
function T.pc() return cpu.state["PC"].value end

function T.fail(msg) T.failed = true; print("FAIL " .. msg) end
function T.pass(msg) print("PASS " .. msg) end
function T.info(msg) print("INFO " .. msg) end
function T.check(cond, msg) if not cond then T.fail(msg) end; return cond end

function T.wait_frames(n) for _ = 1, n do coroutine.yield() end end
function T.wait_seconds(s) T.wait_frames(math.floor(s * 60)) end

-- Wait until fn() is true, up to `frames`; returns whether it became true.
function T.wait_until(fn, frames)
  for _ = 1, frames do
    if fn() then return true end
    coroutine.yield()
  end
  return fn()
end

function T.press(s) mac.natkeyboard:post(s) end

function T.snap(name)
  mac.screens[":screen"]:snapshot(name .. ".png")
end

-- Hi-res on and text off, read from the soft-switch status registers.
function T.hires_on()
  return (T.peek(0xC01D) & 0x80) ~= 0 and (T.peek(0xC01A) & 0x80) == 0
end

-- True once After Dusk is running: its code is executing.
function T.running()
  local pc = T.pc()
  return pc >= 0x6000 and pc < 0x9600
end

-- The speaker guard. The IIc ROM beeps at power-on, so only accesses made
-- while After Dusk's own code is executing count. (The language card only
-- ever holds sprite data, never code, and the ROM shares its addresses.)
local function guard(offset, data, mask)
  if T.running() and not T.speaker_hit then
    T.speaker_hit = true
    T.fail(string.format("speaker accessed at PC %04X", T.pc()))
  end
  return data
end
-- Kept in globals: a tap or notifier whose handle is garbage-collected
-- silently stops working.
_G.after_dusk_taps = {
  mem:install_read_tap(0xC030, 0xC03F, "speaker_r", guard),
  mem:install_write_tap(0xC030, 0xC03F, "speaker_w", guard),
}

function T.run(fn)
  -- MAME re-runs the autoboot script after a hard reset; the first run is
  -- still going, so the second must not start another.
  if _G.after_dusk_test_running then return end
  _G.after_dusk_test_running = true
  local co = coroutine.create(function()
    fn()
    print("INFO done after " .. T.frame .. " frames")
    mac:exit()
  end)
  _G.after_dusk_sub = emu.add_machine_frame_notifier(function()
    T.frame = T.frame + 1
    if coroutine.status(co) == "suspended" then
      local ok, err = coroutine.resume(co)
      if not ok then T.fail("lua error: " .. tostring(err)); mac:exit() end
    end
  end)
end

return T
