import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, fx_entry, run, start

FX = 5
KEEP = 100                      # lines kept on screen
QUARTER = range(61, 69)         # step round the ellipse, 256 = a full turn: about a quarter turn
THIRD = range(81, 88)           # ... or, now and then, about a third
PH_STEP = 0x73                  # tilt drift per step, 8.8: 0.011 radians, the original's


@pytest.fixture
def s(built):
    return start(FX)


def step_angle(s):
    return s.peek16(s.addr("lis_dth")) >> 8


def test_draws_30_lines_a_second(built):
    assert fx_entry(start(FX), FX)[3] == 2             # ticks a step: 60 / 2


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_starts_with_a_quarter_turn(built):
    for seed in (0x1111, 0x2222, 0x3333, 0x4444):
        assert step_angle(start(FX, seed=seed)) in QUARTER


def test_keeps_the_last_100_lines(s):
    run(s, 300)
    assert s.peek(s.addr("lis_count")) == KEEP + 1     # points: one more than lines


def test_screen_does_not_fill_up(s):
    run(s, 300)
    early = len(s.page_pixels())
    run(s, 1200)
    late = len(s.page_pixels())
    assert early > 2000                                # long lines, not short segments
    assert late < early * 1.6


def test_hollow_middle(s):
    """Straight lines between points a quarter turn apart round the ellipse leave its middle empty."""
    run(s, 150)
    lit = s.page_pixels()
    assert all(10 <= x <= 270 and 8 <= y <= 184 for x, y in lit)
    assert not any(abs(x - 140) <= 5 and abs(y - 96) <= 5 for x, y in lit)


def test_tilt_drifts(s):
    before = s.peek16(s.addr("lis_ph"))
    run(s, 100)
    assert s.peek16(s.addr("lis_ph")) == (before + 100 * PH_STEP) & 0xFFFF


def test_step_changes_every_400(built):
    seen = set()
    for seed in (0x1111, 0x2222, 0x3333, 0x4444, 0x5555):
        s = start(FX, seed=seed)
        for _ in range(6):
            s.poke16(s.addr("lis_n"), 399)
            s.step()
            assert s.peek16(s.addr("lis_n")) == 0
            a = step_angle(s)
            assert a in QUARTER or a in THIRD
            seen.add(a)
    assert any(a in QUARTER for a in seen) and any(a in THIRD for a in seen)


def test_near_wrap(s):
    s.poke(s.addr("lis_head"), 0xFD)
    s.poke16(s.addr("lis_th"), 0xFFF0)
    s.start_tracking()
    run(s, 150)
    assert s.writes_outside(*ALLOWED) == []
    assert s.peek(s.addr("lis_count")) == KEEP + 1
