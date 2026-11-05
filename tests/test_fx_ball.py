import math

import pytest

from fxcommon import check_bit7, check_budget, check_in_bounds, run, start

FX = 12
R = 3                           # the ball's radius
XMIN, XMAX = R, 279 - R         # where its centre may go
YMIN, YMAX = R, 191 - R
XA = 1.1                        # x speeds stretched for the IIc's dot shape
SPEED = 3.8                     # dots a step (x part unstretched): about 115 a second
ANGLE = (0.45, 1.1)             # radians off an axis
START_X, START_Y = (20, 260), (20, 170)
SEEDS = (0x4D2A, 0x1357, 0xBEEF, 0x2468, 0x0F0F, 0x7777)


def signed(v):
    return v - 0x10000 if v & 0x8000 else v


def ball(s):
    """Position (8 fraction bits) and speed (signed 8.8) as (x, y, vx, vy)."""
    a = s.addr("bb_x")
    x = s.peek(a) | s.peek(a + 1) << 8 | s.peek(a + 2) << 16
    y = s.peek16(s.addr("bb_y"))
    return x, y, signed(s.peek16(s.addr("bb_vx"))), signed(s.peek16(s.addr("bb_vy")))


def set_ball(s, x, y, vx, vy):
    a = s.addr("bb_x")
    s.poke(a, x)
    s.poke(a + 1, x >> 8)
    s.poke(a + 2, x >> 16)
    s.poke16(s.addr("bb_y"), y)
    s.poke16(s.addr("bb_vx"), vx)
    s.poke16(s.addr("bb_vy"), vy)


def centre(x, y):
    """Where the disc is drawn: the position rounded to the nearest dot."""
    return (x + 128) >> 8, (y + 128) >> 8


def disc(cx, cy):
    """Every dot with dx*dx + dy*dy <= r*r + r, as the sample draws it."""
    return {(cx + dx, cy + dy) for dx in range(-R, R + 1) for dy in range(-R, R + 1)
            if dx * dx + dy * dy <= R * R + R}


def moved(p, v, lo, hi):
    """The sample's move along one axis, in fixed point: straight on, or put
    back on the edge it crossed with that part of the speed turned round."""
    q = p + v
    if q < lo << 8:
        return lo << 8, -v
    if q > hi << 8:
        return hi << 8, -v
    return q, v


def speed(vx, vy):
    return math.hypot(vx / 256 / XA, vy / 256)


def off_axis(vx, vy):
    """Angle between the heading and the x axis, folded into the first quadrant."""
    return math.atan2(abs(vy), abs(vx) / XA)


@pytest.fixture
def s(built):
    return start(FX)


# ---- budget and bounds ----

def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


# ---- start ----

def test_starts_on_a_blank_screen(s):
    assert s.page_pixels() == set()


def test_starts_anywhere_at_one_speed(built):
    for seed in SEEDS:
        x, y, vx, vy = ball(start(FX, seed=seed))
        assert x & 0xFF == 0 and y & 0xFF == 0                # on a whole dot
        assert START_X[0] <= x >> 8 <= START_X[1]
        assert START_Y[0] <= y >> 8 <= START_Y[1]
        assert speed(vx, vy) == pytest.approx(SPEED, abs=0.015)


def test_heads_off_diagonally_in_any_direction(built):
    signs, angles, xs, ys = set(), [], [], []
    for seed in range(1, 150):
        x, y, vx, vy = ball(start(FX, seed=seed * 0x1F3))
        signs.add((vx > 0, vy > 0))
        a = off_axis(vx, vy)
        # a is 0.45-1.1 off the x axis, or (a quarter turn on) 0.45-1.1 off the y axis
        assert ANGLE[0] - 0.01 <= a <= math.pi / 2 - ANGLE[0] + 0.01
        angles.append(a)
        xs.append(x >> 8)
        ys.append(y >> 8)
    assert len(signs) == 4
    assert min(angles) < 0.55 and max(angles) > 1.0
    assert min(xs) < 50 and max(xs) > 230 and min(ys) < 40 and max(ys) > 150


# ---- motion ----

def test_glides_in_a_straight_line_and_bounces_off_the_edges(built):
    """Each step the ball goes on by its speed; where that would cross an edge
    it is put back on the edge and that part of its speed turns round."""
    for seed in SEEDS[:2]:
        s = start(FX, seed=seed)
        x, y, vx, vy = ball(s)
        for _ in range(400):
            s.step()
            (wx, wvx), (wy, wvy) = moved(x, vx, XMIN, XMAX), moved(y, vy, YMIN, YMAX)
            assert ball(s) == (wx, wy, wvx, wvy)
            x, y, vx, vy = wx, wy, wvx, wvy


@pytest.mark.parametrize("case", [
    # axis, position, speed, where it ends up
    ("x", 0x0380, -0x0100, 0x0300),      # x 3.5 heading left 1: stops at 3, turns
    ("x", 0x11380, 0x0100, 0x11400),     # x 275.5 heading right: stops at 276
    ("y", 0x0380, -0x0100, 0x0300),      # y 3.5 heading up: stops at 3
    ("y", 0xBB80, 0x0100, 0xBC00),       # y 187.5 heading down: stops at 188
    ("x", 0x11300, 0x0100, 0x11400),     # x 275 + 1: on the edge, no turn yet
    ("y", 0x0400, -0x0100, 0x0300),      # y 4 - 1: on the edge, no turn yet
])
def test_bounces_off_each_edge(s, case):
    ax, pos, v, want = case
    x, y = (pos, 0x6000) if ax == "x" else (0x8C00, pos)
    vx, vy = (v, 0x00C0) if ax == "x" else (0x00C0, v)
    set_ball(s, x, y, vx & 0xFFFF, vy & 0xFFFF)
    s.step()
    nx, ny, nvx, nvy = ball(s)
    p, pv = (nx, nvx) if ax == "x" else (ny, nvy)
    assert p == want
    assert pv == (v if pos + v == want else -v)
    assert s.page_pixels() == disc(*centre(nx, ny))


def test_reaches_every_edge(built):
    """Sent into each corner, the ball bounces off both of its edges and comes away."""
    for x, y, vx, vy in ((10 << 8, 10 << 8, -0x150, -0x130), (269 << 8, 10 << 8, 0x150, -0x130),
                         (10 << 8, 181 << 8, -0x150, 0x130), (269 << 8, 181 << 8, 0x150, 0x130)):
        s = start(FX)
        set_ball(s, x, y, vx & 0xFFFF, vy & 0xFFFF)
        run(s, 12)
        _, _, nvx, nvy = ball(s)
        assert (nvx, nvy) == (-vx, -vy)


# ---- drawing ----

def test_draws_one_solid_disc_of_radius_3(built):
    """After every step the screen holds the disc at the ball's position and
    nothing else: the old one is gone."""
    assert len(disc(100, 100)) == 37
    for seed in SEEDS[:2]:
        s = start(FX, seed=seed)
        for n in range(150):
            s.step()
            x, y, _, _ = ball(s)
            assert s.page_pixels() == disc(*centre(x, y)), (seed, n)


def test_disc_follows_a_jump(s):
    """Moved far away, the ball leaves nothing behind."""
    run(s, 3)
    set_ball(s, 200 << 8, 50 << 8, 0x0100, 0x0100)
    s.step()
    assert s.page_pixels() == disc(201, 51)
