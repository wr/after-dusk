import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start
from sim import PAGE1

FX = 4


def lit_page(s):
    s.fill_page(PAGE1, 0x7F)


def heads(s):
    n = s.peek(s.addr("wrm_count"))
    out = []
    for i in range(n):
        x = s.peek(s.addr("wrm_xi") + i) | (s.peek(s.addr("wrm_xh") + i) << 8)
        out.append((x, s.peek(s.addr("wrm_yi") + i)))
    return out


@pytest.fixture
def s(built):
    return start(FX, prepare=lit_page)


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_keeps_the_screen(built):
    s = start(FX, prepare=lit_page)
    dark = 280 * 192 - len(s.page_pixels())
    assert dark < 300                                  # init only starts the worms


def test_eats(s):
    run(s, 200)
    dark = 280 * 192 - len(s.page_pixels())
    print("dark dots after 200 steps:", dark)
    assert dark >= 2000


def test_bounds(s):
    assert s.peek(s.addr("wrm_count")) == 6
    for _ in range(1000):
        s.step()
        for x, y in heads(s):
            assert 4 <= x <= 275 and 4 <= y <= 187, (x, y)


def test_near_wrap(s):
    for i in range(6):
        s.poke(s.addr("wrm_head") + i, 31)
    s.start_tracking()
    run(s, 50)
    assert s.writes_outside(*ALLOWED) == []
