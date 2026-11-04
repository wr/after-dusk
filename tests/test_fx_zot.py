import random

import pytest

from fxcommon import ALLOWED, TICK, check_bit7, check_in_bounds, start
from sim import PAGE1, ST_TIMING, VblLatch

FX = 3


def pattern(s):
    rnd = random.Random(7)
    for i in range(0x2000):
        s.poke(0x2000 + i, rnd.randrange(128))


def segments(s):
    n = s.peek(s.addr("zot_nseg"))
    base = s.addr("zot_seg")
    out = []
    for i in range(n):
        a = base + i * 7
        x0 = s.peek(a) | (s.peek(a + 1) << 8)
        x1 = s.peek(a + 3) | (s.peek(a + 4) << 8)
        out.append((x0, s.peek(a + 2), x1, s.peek(a + 5), s.peek(a + 6)))
    return out


@pytest.fixture
def s(built):
    return start(FX, prepare=pattern)


def test_budget(built):
    # Zot! has no motion, so a long step can't stutter: a bolt simply takes a
    # moment to draw (top to bottom). Keep that moment short: under 0.2 s,
    # including a flash's one-tick hold. All other steps are tiny.
    cycles = []
    for seed in (0x4D2A, 0x1357, 0xBEEF):
        s = start(FX, seed=seed)
        cycles += [s.step() for _ in range(300)]
    worst = max(cycles)
    median = sorted(cycles)[len(cycles) // 2]
    print("worst step", worst, "median", median)
    assert worst < 12 * TICK
    assert median < 1000


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_keeps_the_screen(built):
    s = start(FX, prepare=pattern)
    before = s.page_bytes(PAGE1)
    assert s.page_bytes(PAGE1) == before


def test_restores(s):
    original = s.page_bytes(PAGE1)
    bolts = 0
    for _ in range(1500):
        s.step()
        if s.peek(s.addr("zot_phase")) == 0:
            assert s.page_bytes(PAGE1) == original
            assert s.peek(0x24) == 0                 # page 1 showing
        bolts = s.peek(s.addr("zot_nbolt"))
    assert bolts >= 10
    assert s.peek(s.addr("zot_nflash")) >= 1
    assert s.peek(s.addr("zot_nflick")) >= 1


def test_trunk(s):
    seen = 0
    for _ in range(600):
        s.step()
        if s.peek(s.addr("zot_phase")) == 1 and s.peek(s.addr("zot_nseg")):
            trunk = [seg for seg in segments(s) if seg[4] & 1]
            assert trunk[0][1] == 0                  # starts at the top
            assert max(seg[3] for seg in trunk) >= 120
            seen += 1
    assert seen >= 5


def test_near_wrap(s):
    s.poke(s.addr("zot_nbolt"), 0xFE)
    s.start_tracking()
    for _ in range(200):
        s.step()
    assert s.writes_outside(*ALLOWED) == []


def test_flash_is_a_whole_frame(built):
    """The flash starts at a vertical blank and lasts a full frame."""
    s = start(FX, prepare=pattern)
    VblLatch(s)
    s.poke(ST_TIMING, 1)
    events = []
    s.mem.write_hooks[0xC055] = lambda v: events.append(("page2", s.mpu.processorCycles))
    s.mem.write_hooks[0xC054] = lambda v: events.append(("page1", s.mpu.processorCycles))
    flashes = 0
    for _ in range(600):
        before = s.peek(s.addr("zot_nflash"))
        events.clear()
        s.step()
        if s.peek(s.addr("zot_nflash")) != before:
            flashes += 1
            on = [c for e, c in events if e == "page2"][0]
            off = [c for e, c in events if e == "page1" and c > on][0]
            assert on % 17030 < 400, "the flash should start just after a blank"
            assert off - on >= 17030 - 400, "the flash should last a whole frame"
    assert flashes >= 2
