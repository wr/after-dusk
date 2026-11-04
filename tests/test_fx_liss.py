import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start

FX = 5
FIGURES = {(3, 2), (5, 4), (3, 4), (1, 2), (5, 6), (2, 3)}


@pytest.fixture
def s(built):
    return start(FX)


def figure(s):
    return s.peek(s.addr("lis_a")), s.peek(s.addr("lis_b"))


def end_figure(s):
    """Run until the current figure has drawn itself back in."""
    s.poke16(s.addr("lis_n"), 900)
    for _ in range(200):
        s.step()
        if not s.peek(s.addr("lis_leaving")):
            return
    raise AssertionError("the figure never finished")


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_figure_is_known(s):
    assert figure(s) in FIGURES


def test_trail_length(s):
    run(s, 200)
    assert s.peek(s.addr("lis_count")) in (254, 255)   # full: one in, one out
    lit = s.page_pixels()
    assert len(lit) > 300
    assert all(10 <= x <= 270 and 8 <= y <= 184 for x, y in lit)


def test_clears_between_figures(s):
    run(s, 150)
    end_figure(s)
    assert s.page_pixels() == set()
    assert s.peek(s.addr("lis_count")) == 0


def test_figure_changes(built):
    seen = set()
    for seed in (0x1111, 0x2222, 0x3333):
        s = start(FX, seed=seed)
        for _ in range(3):
            seen.add(figure(s))
            run(s, 20)
            end_figure(s)
    assert seen <= FIGURES
    assert len(seen) >= 2


def test_near_wrap(s):
    s.poke(s.addr("lis_head"), 0xFD)
    s.poke16(s.addr("lis_t"), 0xFFF0)
    s.start_tracking()
    run(s, 50)
    assert s.writes_outside(*ALLOWED) == []
