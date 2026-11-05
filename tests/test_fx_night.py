import math

import pytest

from fxcommon import TICK, check_bit7, check_budget, check_in_bounds, run, start
from sim import ST_TIMING, VblLatch

FRAMES = 0x2C                   # timing.s: vertical blanks counted

FX = 6
KEEP = 8                        # generations kept, 4 lines each
XMAX, YMAX = 279, 191           # the ends bounce off the edges of the whole screen
XA = 1.1                        # x speeds stretched for the IIc's dot shape
SPEED = (7, 10.5)               # dots a step (x part unstretched)
START_X, START_Y = (125, 155), (85, 107)
SEEDS = (0x4D2A, 0x1357, 0xBEEF, 0x2468, 0x0F0F, 0x7777)

LINES = [
    (0, 0, 139, 95), (139, 95, 0, 0), (10, 80, 130, 5), (5, 0, 5, 95), (0, 40, 139, 40),
    (70, 30, 70, 30), (139, 0, 0, 95), (3, 90, 9, 2), (20, 10, 26, 60), (131, 7, 3, 9),
    (6, 50, 7, 51), (0, 95, 139, 94),
    # across the middle, wider than 140, taller than 96
    (139, 96, 140, 95), (100, 5, 250, 180), (30, 0, 60, 191), (200, 191, 150, 0),
    (5, 0, 5, 191), (279, 191, 279, 0), (140, 0, 139, 191), (0, 191, 191, 0),
    # wider than 255 (and the x tables' seam at 256)
    (0, 0, 279, 191), (279, 191, 0, 0), (0, 191, 279, 0), (0, 0, 279, 0), (0, 191, 279, 191),
    (0, 95, 279, 96), (10, 20, 270, 30), (3, 7, 270, 7), (0, 50, 255, 60), (0, 50, 256, 60),
    (1, 120, 278, 40), (255, 10, 256, 11), (260, 100, 270, 100), (250, 3, 279, 190),
    (275, 0, 279, 4), (256, 0, 256, 191),
]


def signed(v):
    return v - 0x10000 if v & 0x8000 else v


def end_base(s, e):
    return s.addr("nl_a") + 10 * e


def axis(s, e, ax):
    """End e's position (8 fraction bits) and speed (signed 8.8) on axis 0 (x) or 1 (y)."""
    a = end_base(s, e) + 5 * ax
    return s.peek(a) | s.peek(a + 1) << 8 | s.peek(a + 2) << 16, signed(s.peek16(a + 3))


def set_axis(s, e, ax, p, v):
    a = end_base(s, e) + 5 * ax
    s.poke(a, p)
    s.poke(a + 1, p >> 8)
    s.poke(a + 2, p >> 16)
    s.poke16(a + 3, v)


def ends(s):
    """A and B as (x, y, vx, vy) in dots."""
    out = []
    for e in (0, 1):
        (x, vx), (y, vy) = axis(s, e, 0), axis(s, e, 1)
        out.append((x / 256, y / 256, vx / 256, vy / 256))
    return out


def generations(s):
    """The kept generations, oldest first, as (ax, ay, bx, by)."""
    head, count = s.peek(s.addr("nl_head")), s.peek(s.addr("nl_count"))
    cols = [s.addr(n) for n in ("nl_gaxl", "nl_gaxh", "nl_gay", "nl_gbxl", "nl_gbxh", "nl_gby")]
    out = []
    for i in range(count):
        k = (head - count + i) % KEEP
        axl, axh, ay, bxl, bxh, by = (s.peek(c + k) for c in cols)
        out.append((axl | axh << 8, ay, bxl | bxh << 8, by))
    return out


def set_generations(s, line):
    for k in range(KEEP):
        for name, v in zip(("nl_gaxl", "nl_gaxh", "nl_gay", "nl_gbxl", "nl_gbxh", "nl_gby"),
                           (line[0] & 0xFF, line[0] >> 8, line[1], line[2] & 0xFF, line[2] >> 8,
                            line[3])):
            s.poke(s.addr(name) + k, v)
    s.poke(s.addr("nl_head"), 0)
    s.poke(s.addr("nl_count"), KEEP)


def rounded(x, y):
    return math.floor(x + 0.5), math.floor(y + 0.5)


def ref_line(x0, y0, x1, y1):
    """The dots of a line as fline draws it: left to right, the error starting
    at half the longer side."""
    if x1 < x0:
        x0, y0, x1, y1 = x1, y1, x0, y0
    dx, dy, sy = x1 - x0, abs(y1 - y0), 1 if y1 >= y0 else -1
    x, y, dots = x0, y0, []
    if dx >= dy:
        err = dx // 2
        for _ in range(dx + 1):
            dots.append((x, y))
            x += 1
            err -= dy
            if err < 0:
                err += dx
                y += sy
    else:
        err = dy // 2
        for _ in range(dy + 1):
            dots.append((x, y))
            y += sy
            err -= dx
            if err < 0:
                err += dy
                x += 1
    return dots


def quad(x0, y0, x1, y1):
    """A line and its three mirror images."""
    return {(mx, my) for x, y in ref_line(x0, y0, x1, y1)
            for mx in (x, 279 - x) for my in (y, 191 - y)}


def draw(s, x0, y0, x1, y1, mode=1):
    q = s.addr("nl_q")
    return s.call("quad_line", zp={q: x0 & 0xFF, q + 1: x0 >> 8, q + 2: y0,
                                   q + 3: x1 & 0xFF, q + 4: x1 >> 8, q + 5: y1, q + 6: mode})


def moved(p, v, top):
    """The sample's move for one axis, in fixed point: straight on, or back off an edge."""
    q = p + v
    if q < 0:
        return 0, -v
    if q > top << 8:
        return top << 8, -v
    return q, v


@pytest.fixture
def s(built):
    return start(FX)


# ---- budget ----

def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_full_screen_lines_fit_the_budget(s):
    """The slowest step there can be: the oldest generation and the newest both
    run corner to corner of the screen, so 8 lines 280 dots across and 192 rows
    tall are rubbed out and drawn."""
    s.fill_page(0x20, 0)
    draw(s, 0, 191, 279, 0)
    set_generations(s, (0, 191, 279, 0))
    set_axis(s, 0, 0, 277 << 8, 3 << 8)         # A into the top-right corner
    set_axis(s, 0, 1, 1 << 8, -3 << 8)
    set_axis(s, 1, 0, 2 << 8, -3 << 8)          # B into the bottom-left one
    set_axis(s, 1, 1, 189 << 8, 3 << 8)
    cycles = s.step()
    assert generations(s)[-1] == (279, 0, 0, 191)
    assert s.page_pixels() == quad(279, 0, 0, 191)
    print("longest step", cycles)
    assert cycles < 5 * TICK - 300


# ---- drawing ----

def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_draws_one_line_four_times_mirrored(s):
    for line in LINES:
        s.fill_page(0x20, 0)
        draw(s, *line)
        assert s.page_pixels() == quad(*line), line


def test_erasing_a_line_takes_all_of_it(s):
    for line in LINES:
        s.fill_page(0x20, 0)
        draw(s, *line, mode=1)
        draw(s, *line, mode=0)
        assert s.page_pixels() == set(), line


def test_mirrored_left_right_and_top_bottom_after_every_step(s):
    for n in range(200):
        s.step()
        lit = s.page_pixels()
        assert {(279 - x, y) for x, y in lit} == lit, n
        assert {(x, 191 - y) for x, y in lit} == lit, n


def test_keeps_the_last_8_generations(s):
    run(s, 100)
    assert s.peek(s.addr("nl_count")) == KEEP
    gens = generations(s)
    (ax, ay, _, _), (bx, by, _, _) = ends(s)
    assert gens[-1] == (*rounded(ax, ay), *rounded(bx, by))   # the newest is where the ends are


def test_screen_holds_only_the_kept_generations(s):
    for n in (100, 37, 163):
        run(s, n)
        gens = generations(s)
        assert len(gens) == KEEP
        lit = s.page_pixels()
        assert lit <= set().union(*(quad(*g) for g in gens))
        assert quad(*gens[-1]) <= lit                # the newest is drawn whole


def test_newest_generation_is_always_whole(s):
    for _ in range(60):
        s.step()
        assert quad(*generations(s)[-1]) <= s.page_pixels()


def test_tall_lines_count_every_blank(s):
    """A line 192 rows tall takes more than a frame; it counts every vertical
    blank it works through."""
    VblLatch(s)
    s.poke(ST_TIMING, 1)
    s.poke16(FRAMES, 0)
    first = s.mpu.processorCycles // TICK
    for n in range(30):
        draw(s, 5 + n, 0, 5 + n, 191, mode=n & 1 ^ 1)
    crossed = s.mpu.processorCycles // TICK - first
    assert crossed > 30
    assert crossed - 1 <= s.peek16(FRAMES) <= crossed


def test_steps_count_every_blank(built):
    """Steps can take two frames; every vertical blank they work through is counted."""
    s = start(FX)
    VblLatch(s)
    s.poke(ST_TIMING, 1)
    s.poke16(FRAMES, 0)
    first = s.mpu.processorCycles // TICK
    run(s, 200)
    crossed = s.mpu.processorCycles // TICK - first
    assert crossed > 100
    assert crossed - 1 <= s.peek16(FRAMES) <= crossed


# ---- motion ----

def speed(vx, vy):
    return math.hypot(vx / XA, vy)


def test_ends_start_near_the_middle(built):
    for seed in SEEDS:
        s = start(FX, seed=seed)
        for x, y, vx, vy in ends(s):
            assert START_X[0] <= x < START_X[1] and START_Y[0] <= y < START_Y[1]
            assert SPEED[0] <= speed(vx, vy) <= SPEED[1]
        s.step()
        [g] = generations(s)
        (ax, ay, _, _), (bx, by, _, _) = ends(s)
        assert g == (*rounded(ax, ay), *rounded(bx, by))
        assert s.page_pixels() == quad(*g)


def test_starting_speeds_and_directions_vary(built):
    speeds, signs, steep = [], set(), set()
    for seed in range(1, 120):
        for x, y, vx, vy in ends(start(FX, seed=seed * 0x1F3)):
            speeds.append(speed(vx, vy))
            signs.add((vx > 0, vy > 0))
            steep.add(abs(vy) > abs(vx / XA))
    assert min(speeds) < 7.3 and max(speeds) > 10.2
    assert len(signs) == 4 and steep == {True, False}


def test_ends_keep_a_steady_velocity_and_bounce_off_every_edge(built):
    """Each end goes straight on at the speed it started with; where it would
    cross an edge, it is put back on the edge and that part of its speed turns
    round. Between them the ends reach all four edges of the screen."""
    edges = set()
    for seed in SEEDS[:3]:
        s = start(FX, seed=seed)
        before = [[axis(s, e, ax) for ax in (0, 1)] for e in (0, 1)]
        for vs in before:
            (x, vx), (y, vy) = vs
            assert SPEED[0] <= speed(vx / 256, vy / 256) <= SPEED[1]
        for _ in range(800):
            s.step()
            for e in (0, 1):
                for ax, top in ((0, XMAX), (1, YMAX)):
                    p0, v0 = before[e][ax]
                    p1, v1 = axis(s, e, ax)
                    assert (p1, v1) == moved(p0, v0, top), (seed, e, ax)
                    assert 0 <= p1 <= top << 8
                    if v1 != v0:
                        edges.add((ax, p1 == 0))
                    before[e][ax] = (p1, v1)
    assert edges == {(0, True), (0, False), (1, True), (1, False)}


@pytest.mark.parametrize("e", [0, 1])
def test_ends_bounce_off_the_edges(s, e):
    cases = [   # axis, position and speed (8 fraction bits), where it stops
        (0, 0x11680, 0x0300, 0x11700),  # x 278.5 heading right at 3: stops at 279
        (0, 0x0080, -0x0300, 0x0000),   # x 0.5 heading left: stops at 0
        (1, 0xBE80, 0x0300, 0xBF00),    # y 190.5 heading down: stops at 191
        (1, 0x0080, -0x0300, 0x0000),   # y 0.5 heading up: stops at 0
        (0, 0x11400, 0x0300, 0x11700),  # x 276 heading right at 3: on the edge, no bounce yet
        # at full speed (10.5 dots, x part stretched: 11.55)
        (0, 0x11080, 0x0B8D, 0x11700),  # x 272.5 heading right at 11.55: stops at 279
        (0, 0x0B00, 0x0B8D, 0x168D),    # x 11 heading right: straight on to 22.55
        (0, 0x0480, -0x0B8D, 0x0000),   # x 4.5 heading left at 11.55: stops at 0
        (0, 0x0B8D, -0x0B8D, 0x0000),   # x 11.55 heading left: on the edge, no bounce yet
        (0, 0x0B8E, -0x0B8D, 0x0001),   # just inside it: on to 1/256 of a dot
        (0, 0x10B73, 0x0B8D, 0x11700),  # x 267.45 heading right: on the edge, no bounce yet
        (0, 0x10B74, 0x0B8D, 0x11700),  # 1/256 further: over it, back on it
        (1, 0xB980, 0x0A80, 0xBF00),    # y 185.5 heading down at 10.5: stops at 191
        (1, 0x0300, -0x0A80, 0x0000),   # y 3 heading up at 10.5: stops at 0
        (1, 0xB480, 0x0A80, 0xBF00),    # y 180.5 heading down: on the edge, no bounce yet
        (1, 0xB481, 0x0A80, 0xBF00),    # 1/256 further: over it, back on it
    ]
    for ax, pos, v, want in cases:
        set_axis(s, e, ax, pos, v)
        s.step()
        p1, v1 = axis(s, e, ax)
        assert p1 == want, (ax, pos)
        assert v1 == (v if pos + v == want else -v), (ax, pos, v1)
