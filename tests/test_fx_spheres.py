import math

import pytest

from fxcommon import ALLOWED, OVERHEAD, TICK, check_bit7, check_budget, check_in_bounds, run, start
from sim import PAGE1, ST_TIMING, VblLatch, row_base
from test_hires import grey

FX = 11
TICKS = 4
CIRCLES = 34                    # a sphere: circles k = 0..33, one a step
SPHERES = 10                    # then the screen clears
HOLD = 16                       # steps the last sphere stays, the clear included
RMAX = 44                       # the biggest sphere (the original's is 58): it must fit 4 ticks
XA = 1.1                        # the IIc's dots are a little narrower than tall
FRAMES = 0x2C                   # timing.s: vertical blanks counted


def v(s, name, i=0):
    return s.peek(s.addr(name) + i)


def signed(n):
    return n - 0x10000 if n & 0x8000 else n


def sphere(s):
    return v(s, "sp_r"), s.peek16(s.addr("sp_cx")), v(s, "sp_cy")


def want_circle(r, cx, cy, k):
    """The sample's circle k: radius, centre and grey level."""
    rr = r * math.sqrt(1 - k / 33)
    off = r * 3 / 20 * math.sqrt(k / 33)
    return rr, cx + off * XA, cy - off, round((24 + 7 * k) / 255 * 16)


def drawn_circle(s):
    """The circle the effect last worked out: radius and centre (in dots) and level."""
    return (v(s, "sp_rr") / 4, signed(s.peek16(s.addr("sp_ccx"))) / 4,
            signed(s.peek16(s.addr("sp_ccy"))) / 4, v(s, "sp_lev"))


def sample_disc(rr, cx, cy):
    """The sample's dots for a circle, on screen."""
    out = set()
    for y in range(math.ceil(cy - rr), math.floor(cy + rr) + 1):
        half = math.sqrt(max(0, rr * rr - (y - cy) ** 2)) * XA
        for x in range(math.ceil(cx - half), math.floor(cx + half) + 1):
            if 0 <= x < 280 and 0 <= y < 192:
                out.add((x, y))
    return out


def anti_pattern(s, level):
    """Every dot the opposite of grey `level`, so an opaque circle in that grey flips every dot it covers."""
    for y in range(192):
        base = row_base(y, PAGE1)
        for b in range(40):
            s.poke(base + b, sum(1 << i for i in range(7) if not grey(b * 7 + i, y, level)))


def set_sphere(s, r, cx, cy, k=0):
    s.poke(s.addr("sp_r"), r)
    s.poke16(s.addr("sp_cx"), cx)
    s.poke(s.addr("sp_cy"), cy)
    s.poke(s.addr("sp_k"), k)


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_stays_in_bounds_through_a_clear(built):
    s = start(FX)
    s.poke(s.addr("sp_count"), SPHERES - 1)
    s.start_tracking()
    run(s, CIRCLES + HOLD + 40)
    assert s.writes_outside(*ALLOWED) == []
    check_bit7(s)


def test_a_sphere_is_34_circles_one_a_step(built):
    s = start(FX, seed=0x1357)
    for _ in range(3):
        first = sphere(s)
        for k in range(CIRCLES):
            assert v(s, "sp_k") == k
            assert sphere(s) == first
            s.step()
        assert v(s, "sp_k") == 0                       # and the next sphere starts
        assert sphere(s) != first


def test_circles_shrink_brighten_and_move_towards_the_highlight(built):
    for seed in (0x4D2A, 0xBEEF):
        s = start(FX, seed=seed)
        for _ in range(2):
            r, cx, cy = sphere(s)
            assert 12 <= r <= 58 and 0 <= cx <= 279 and 0 <= cy <= 191
            for k in range(CIRCLES):
                s.step()
                rr, ccx, ccy, lev = drawn_circle(s)
                wr, wx, wy, wl = want_circle(r, cx, cy, k)
                assert abs(rr - wr) <= 0.25, (k, rr, wr)       # sizes are kept in quarter dots,
                assert abs(ccx - wx) <= 0.25, (k, ccx, wx)     # the height to the nearest half dot
                assert abs(ccy - wy) <= 0.4 and v(s, "sp_ccy") % 2 == 0, (k, ccy, wy)
                assert lev == wl


def test_levels_rise_from_dark_to_white(built):
    s = start(FX)
    levels = []
    for _ in range(CIRCLES):
        s.step()
        levels.append(drawn_circle(s)[3])
    assert levels == [round((24 + 7 * k) / 255 * 16) for k in range(CIRCLES)]
    assert levels[0] == 2 and levels[-1] == 16 and levels == sorted(levels)


@pytest.mark.parametrize("r,cx,cy", [(RMAX, 140, 96), (31, 3, 188), (12, 277, 0), (40, 200, 20), (23, 90, 150), (37, 139, 95)])
def test_each_circle_is_the_samples_disc_in_its_grey(built, r, cx, cy):
    s = start(FX)
    for k in (0, 1, 7, 16, 25, 31, 32, 33):
        set_sphere(s, r, cx, cy, k)
        rr, wx, wy, level = want_circle(r, cx, cy, k)
        anti_pattern(s, level)
        before = s.page_pixels()
        s.step()
        covered = before ^ s.page_pixels()
        want = sample_disc(rr, wx, wy)
        for x, y in covered ^ want:                    # only dots within half a dot of
            d = math.hypot((x - wx) / XA, y - wy)      # the true edge may differ
            assert abs(d - rr) <= 0.5, (k, x, y, d, rr)
        rim = 2 * math.pi * rr * XA                    # and only a few of those
        assert len(covered ^ want) <= 4 + rim / 4, (k, len(covered ^ want), len(want))


def test_spheres_land_anywhere_at_any_size(built):
    s = start(FX)
    seen = [sphere(s)]
    for _ in range(400):
        s.call("sp_fresh")
        seen.append(sphere(s))
    rs, xs, ys = zip(*seen)
    assert min(rs) == 12 and max(rs) == RMAX
    assert min(xs) < 10 and max(xs) > 270 and max(xs) <= 279
    assert min(ys) < 10 and max(ys) > 182 and max(ys) <= 191


def test_after_10_spheres_it_holds_then_clears_and_starts_again(built):
    s = start(FX, seed=0x2468)
    s.poke(s.addr("sp_count"), SPHERES - 1)            # the tenth sphere
    run(s, CIRCLES)
    s.fill_page(PAGE1, 0x55)                           # so the clear shows on every row
    picture = s.page_bytes(PAGE1)
    for _ in range(HOLD - 2):                          # it stays two seconds...
        s.step()
        assert s.page_bytes(PAGE1) == picture
    s.step()                                           # ...then the top half clears...
    assert {y for _, y in s.page_pixels()} == set(range(96, 192))
    s.step()                                           # ...and the bottom half
    assert s.page_pixels() == set()
    assert v(s, "sp_k") == 0 and v(s, "sp_count") == 0
    s.step()                                           # and a new sphere starts
    assert v(s, "sp_k") == 1
    assert s.page_pixels()


def test_biggest_circle_and_the_clear_fit_their_ticks(built):
    s = start(FX)
    worst = 0
    for cx, cy in ((140, 96), (60, 50), (220, 150)):
        set_sphere(s, RMAX, cx, cy)
        worst = max(worst, s.step())
    print("biggest circle", worst)
    s.poke(s.addr("sp_k"), CIRCLES)
    s.poke(s.addr("sp_hold"), 2)
    clear = max(s.step(), s.step())
    print("clear", clear)
    assert max(worst, clear) < TICKS * TICK - OVERHEAD


def test_long_steps_keep_counting_vertical_blanks(built):
    s = start(FX)
    VblLatch(s)
    s.poke(ST_TIMING, 1)
    s.poke16(FRAMES, 0)
    first = s.mpu.processorCycles // TICK
    for _ in range(3):
        set_sphere(s, RMAX, 140, 96)
        s.step()
    s.poke(s.addr("sp_k"), CIRCLES)
    s.poke(s.addr("sp_hold"), 2)
    s.step()
    s.step()
    crossed = s.mpu.processorCycles // TICK - first
    assert crossed >= 14
    assert crossed - 1 <= s.peek16(FRAMES) <= crossed
