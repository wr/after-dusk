import pytest

from fxcommon import NFX
from sim import DISP, PAGE1, PAGE2, RNG, SEED, ST_BEAT, ST_FX, ST_STARTS, ST_TIMING, TICKS, Sim

FX_TICKS = 10800


@pytest.fixture
def s(built):
    s = Sim().load_effects()
    s.poke(ST_TIMING, 0)       # no vertical blank in the simulator
    return s


def picks(s, n, start=0xFF):
    s.poke(ST_FX, start)
    out = []
    for _ in range(n):
        s.call("pick_next")
        out.append(s.mpu.a)
        s.poke(ST_FX, s.mpu.a)
    return out


def test_pick_never_repeats(s):
    s.poke16(RNG, 0x7A31)
    seq = picks(s, 2000)
    assert set(seq) == set(range(NFX))
    assert all(a != b for a, b in zip(seq, seq[1:]))


def test_seed_changes_order(s):
    orders = set()
    for seed in range(1, 21):
        s.poke16(SEED, seed)
        s.call("rng_seed")
        orders.add(tuple(picks(s, 3)))
    assert len(orders) >= 10


def test_fx_table(s):
    base = s.addr("fx_table")
    wipes = [s.peek(base + i * 6 + 4) for i in range(NFX)]
    ticks = [s.peek(base + i * 6 + 5) for i in range(NFX)]
    assert wipes == [1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]       # only Can of Worms eats the last picture
    assert ticks == [4, 2, 4, 3, 3, 2, 5, 6, 2, 2, 3, 4, 2, 3, 1]


def test_normalize_display(s):
    for i in range(0, 0x2000, 13):
        s.poke(0x4000 + i, i & 0x7F)
    s.call("show_page2")
    s.call("normalize_display")
    assert s.page_bytes(PAGE1) == s.page_bytes(PAGE2)
    assert s.peek(DISP) == 0


def test_normalize_display_page1_untouched(s):
    s.poke(0x2000, 0x11)
    s.poke(0x4000, 0x22)
    s.call("show_page1")
    s.call("normalize_display")
    assert s.peek(0x2000) == 0x11


def test_wipe(s):
    s.fill_page(PAGE1, 0x7F)
    s.poke16(TICKS, 0)
    s.call("wipe_to_black", max_cycles=2_000_000)
    assert s.page_pixels(PAGE1) == set()   # the 512 hidden "screen hole" bytes may stay
    assert s.peek16(TICKS) == 24


def test_begin_effect(s):
    s.poke16(RNG, 0x1111)
    s.poke(ST_FX, 0xFF)
    s.poke(ST_STARTS, 7)
    s.call("begin_effect", max_cycles=2_000_000)
    assert s.peek(ST_FX) in range(NFX)
    assert s.peek(ST_STARTS) == 8
    assert s.peek16(TICKS) == 0


def test_counters_near_wrap(s):
    s.poke16(RNG, 0x2222)
    s.poke(ST_FX, 0xFF)
    s.call("begin_effect", max_cycles=2_000_000)
    first = s.peek(ST_FX)
    s.poke16(ST_BEAT, 0xFFFE)
    s.poke16(TICKS, FX_TICKS - 1)
    s.call("step_once", max_cycles=200_000)
    assert s.carry(), "time was up, the effect should end"
    assert s.peek16(ST_BEAT) == 0xFFFF
    s.call("begin_effect", max_cycles=2_000_000)
    assert s.peek(ST_FX) != first
    s.call("step_once", max_cycles=200_000)
    assert not s.carry()
    assert s.peek16(ST_BEAT) == 0


def test_key_ends_effect(s):
    s.poke16(RNG, 0x3333)
    s.poke(ST_FX, 0xFF)
    s.call("begin_effect", max_cycles=2_000_000)
    s.call("step_once", max_cycles=200_000)
    assert not s.carry()
    s.poke(0xC000, 0xA0)               # a key arrives
    s.call("step_once", max_cycles=200_000)
    assert s.carry()


# Fish! (14) steps every tick: whole-tick waits can't pace its step (about
# two thirds of a tick of work) within 25%. Task 6 sets its pacing.
FISH_PACING = pytest.mark.xfail(strict=True, reason="Task 6: Fish!'s fx_slow and fallback pacing")


@pytest.mark.parametrize("fx", [pytest.param(fx, marks=FISH_PACING) if fx == 14 else fx
                                for fx in range(NFX)])
def test_fallback_pacing(built, fx):
    """Without vertical blank, a step (work plus wait) still takes about its
    ticks, and TICKS still counts its ticks."""
    from fxcommon import fx_entry
    from fxcommon import start as fx_start
    s = fx_start(fx)
    s.poke(0x2B, fx * 6)                  # FXOFF: the randomizer's current effect
    ticks = fx_entry(s, fx)[3]
    # settle: worms only eat once their tails start; Nightlines' first steps, with
    # both ends flying apart from the middle, draw longer lines than it does later
    for _ in range(200 if fx == 6 else 40):
        s.step()
    periods = []
    for _ in range(24):
        t0 = s.peek16(TICKS)
        periods.append(s.call("step_once", max_cycles=2_000_000))
        assert (s.peek16(TICKS) - t0) & 0xFFFF == ticks
    median = sorted(periods)[len(periods) // 2]
    want = ticks * 17030
    assert abs(median - want) <= want * 0.25, (median, want)
