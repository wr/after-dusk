import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start

FX = 1


def stars(s):
    n = s.peek(s.addr("wrp_count"))
    out = []
    for i in range(n):
        x = s.peek(s.addr("wrp_xi") + i)          # stored halved
        x = x - 0x100 if x & 0x80 else x
        y = s.peek(s.addr("wrp_yi") + i)
        y = y - 0x100 if y & 0x80 else y
        xf = s.peek(s.addr("wrp_xf") + i) / 256
        yf = s.peek(s.addr("wrp_yf") + i) / 256
        out.append((2 * (x + xf), y + yf))
    return out


@pytest.fixture
def s(built):
    return start(FX)


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_star_count(s):
    st = stars(s)
    assert 60 <= len(st) <= 70
    assert all(-141 <= x <= 141 and -97 <= y <= 97 for x, y in st)


def test_outward(s):
    for _ in range(10):
        before = stars(s)
        s.step()
        after = stars(s)
        for (x0, y0), (x1, y1) in zip(before, after):
            respawned = abs(x1) <= 16 and abs(y1) <= 14 and (x1 * x1 + y1 * y1) < (x0 * x0 + y0 * y0)
            assert respawned or (x1 * x1 + y1 * y1) > (x0 * x0 + y0 * y0), ((x0, y0), (x1, y1))


def test_draws_stars(s):
    run(s, 20)
    lit = s.page_pixels()
    assert len(lit) >= 40
    assert s.peek(0x24) == 0          # drawn on page 1, which is showing


def test_near_wrap(s):
    for i in range(s.peek(s.addr("wrp_count"))):
        s.poke(s.addr("wrp_xi") + i, 67)
        s.poke(s.addr("wrp_yi") + i, (-94) & 0xFF)
    s.start_tracking()
    run(s, 50)
    assert s.writes_outside(*ALLOWED) == []
    assert all(-141 <= x <= 141 and -97 <= y <= 97 for x, y in stars(s))
