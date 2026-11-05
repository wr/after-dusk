import pytest

from fxcommon import TICK, check_bit7, check_budget, check_in_bounds, run, start
from sim import ST_TIMING, VblLatch

FRAMES = 0x2C                   # timing.s: vertical blanks counted

FX = 6
KEEP = 20                       # generations kept, 4 lines each
W, H = 140, 96                  # the top-left quarter the two ends stay in
VMAX_X, VMAX_Y = 4.0, 3.0       # speed limits, dots a step
PUSH_X, PUSH_Y = 1.2, 1.0       # random push a step, at most
DAMP = 0.9                      # share of the speed kept from one step to the next

LINES = [
    (0, 0, 139, 95), (139, 95, 0, 0), (10, 80, 130, 5), (5, 0, 5, 95), (0, 40, 139, 40),
    (70, 30, 70, 30), (139, 0, 0, 95), (3, 90, 9, 2), (20, 10, 26, 60), (131, 7, 3, 9),
    (6, 50, 7, 51), (0, 95, 139, 94),
]


def signed(v):
    return v - 0x10000 if v & 0x8000 else v


def ends(s):
    """A and B as (x, y, vx, vy) in dots."""
    out = []
    for name in ("nl_a", "nl_b"):
        a = s.addr(name)
        out.append((s.peek16(a) / 256, s.peek16(a + 2) / 256,
                    signed(s.peek16(a + 4)) / 256, signed(s.peek16(a + 6)) / 256))
    return out


def generations(s):
    """The kept generations, oldest first, as (ax, ay, bx, by)."""
    head, count = s.peek(s.addr("nl_head")), s.peek(s.addr("nl_count"))
    cols = [s.addr(n) for n in ("nl_gax", "nl_gay", "nl_gbx", "nl_gby")]
    return [tuple(s.peek(c + (head - count + i) % KEEP) for c in cols) for i in range(count)]


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
    """A line in the top-left quarter and its three mirror images."""
    return {(mx, my) for x, y in ref_line(x0, y0, x1, y1)
            for mx in (x, 279 - x) for my in (y, 191 - y)}


def draw(s, x0, y0, x1, y1, mode=1):
    q = s.addr("nl_q")
    s.call("quad_line", zp={q: x0, q + 1: y0, q + 2: x1, q + 3: y1, q + 4: mode})


@pytest.fixture
def s(built):
    return start(FX)


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_longest_lines_fit_the_budget(s):
    """The slowest step there can be: the oldest generation and the newest both
    run corner to corner of the quarter (140 dots across, 96 rows)."""
    for slot, name in enumerate(("nl_gax", "nl_gay", "nl_gbx", "nl_gby")):
        for i in range(KEEP):
            s.poke(s.addr(name) + i, (0, 95, 139, 0)[slot])
    s.poke(s.addr("nl_head"), 0)
    s.poke(s.addr("nl_count"), KEEP)
    a, b = s.addr("nl_a"), s.addr("nl_b")
    for base, x, y, vx, vy in ((a, 0x8B80, 0x0080, 0x0400, -0x0300),    # A into the far corner
                               (b, 0x0080, 0x5F80, -0x0400, 0x0300)):   # B into the near one
        s.poke16(base, x)
        s.poke16(base + 2, y)
        s.poke16(base + 4, vx)
        s.poke16(base + 6, vy)
    cycles = s.step()
    assert generations(s)[-1] == (139, 0, 0, 95)
    print("longest step", cycles)
    assert cycles < 5 * 17030 - 300


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


def test_starts_as_a_cross(built):
    """One end near the middle, the other near the corner, both still: the first
    four lines make an X through the middle of the screen."""
    for seed in (0x1111, 0x2222, 0x3333, 0x4444, 0x5555, 0x6666):
        s = start(FX, seed=seed)
        (ax, ay, avx, avy), (bx, by, bvx, bvy) = ends(s)
        assert 115 <= ax < 139 and 75 <= ay < 95
        assert 0 <= bx < 20 and 0 <= by < 15
        assert avx == avy == bvx == bvy == 0
        s.step()
        [g] = generations(s)
        gax, gay, gbx, gby = g
        assert gax >= 113 and gay >= 73          # one push moves an end 1.2 dots at most
        assert gbx <= 21 and gby <= 16
        assert s.page_pixels() == quad(*g)


def test_mirrored_left_right_and_top_bottom(s):
    for n in range(150):
        s.step()
        lit = s.page_pixels()
        assert {(279 - x, y) for x, y in lit} == lit, n
        assert {(x, 191 - y) for x, y in lit} == lit, n


def test_keeps_the_last_20_generations(s):
    run(s, 100)
    assert s.peek(s.addr("nl_count")) == KEEP
    gens = generations(s)
    (ax, ay, _, _), (bx, by, _, _) = ends(s)
    assert gens[-1] == (int(ax), int(ay), int(bx), int(by))   # the newest is where the ends are


def test_older_generations_are_gone(s):
    for n in (100, 37, 163):
        run(s, n)
        gens = generations(s)
        assert len(gens) == KEEP
        lit = s.page_pixels()
        assert lit <= set().union(*(quad(*g) for g in gens))
        assert quad(*gens[-1]) <= lit                # the newest is drawn whole
        assert len(lit) <= KEEP * 4 * W


def test_newest_generation_is_always_whole(s):
    for _ in range(60):
        s.step()
        assert quad(*generations(s)[-1]) <= s.page_pixels()


def test_ends_stay_in_the_quarter_within_the_speed_limits(built):
    for seed in (0x4D2A, 0x1357, 0xBEEF):
        s = start(FX, seed=seed)
        for _ in range(400):
            s.step()
            for x, y, vx, vy in ends(s):
                assert 0 <= x < W and 0 <= y < H
                assert abs(vx) <= VMAX_X and abs(vy) <= VMAX_Y


def test_speeds_carry_over_with_a_random_push(built):
    """Each step v = 0.9 v + a push of up to 1.2 dots (x) or 1 dot (y), and the
    end moves by v: the ends drift in smooth curves rather than jitter."""
    pushes = {"x": [], "y": []}
    s = start(FX, seed=0x2468)
    before = ends(s)
    for _ in range(500):
        s.step()
        after = ends(s)
        for (x0, y0, vx0, vy0), (x1, y1, vx1, vy1) in zip(before, after):
            for axis, p0, v0, p1, v1, vmax, edge in (("x", x0, vx0, x1, vx1, VMAX_X, W - 1),
                                                     ("y", y0, vy0, y1, vy1, VMAX_Y, H - 1)):
                if p1 in (0, edge):                  # bounced: see the next test
                    continue
                assert p1 == p0 + v1
                if abs(v1) < vmax:                   # not held at the limit
                    pushes[axis].append(v1 - DAMP * v0)
        before = after
    for axis, most in (("x", PUSH_X), ("y", PUSH_Y)):
        p = pushes[axis]
        assert len(p) > 600
        assert max(abs(v) for v in p) <= most + 0.02
        assert min(p) < -0.8 * most and max(p) > 0.8 * most
        assert abs(sum(p) / len(p)) < 0.1
    assert max(abs(v) for v in pushes["x"]) > 1.05   # x pushes go past a dot


def test_ends_bounce_off_the_edges(s):
    a = s.addr("nl_a")
    cases = [   # offset of the position (0 = x, 2 = y), position and speed (8.8), where it stops
        (0, 0x8A80, 0x0300, 0x8B00),    # x 138.5 heading right at 3: stops at 139
        (0, 0x0080, -0x0300, 0x0000),   # x 0.5 heading left: stops at 0
        (2, 0x5E80, 0x0300, 0x5F00),    # y 94.5 heading down: stops at 95
        (2, 0x0080, -0x0300, 0x0000),   # y 0.5 heading up: stops at 0
    ]
    for off, pos, v, want in cases:
        s.poke16(a + off, pos)
        s.poke16(a + 4 + off, v)
        s.step()
        assert s.peek16(a + off) == want, (off, pos)
        v1 = signed(s.peek16(a + 4 + off))
        assert (v1 < 0) == (v > 0) and v1 != 0, (off, pos, v1)   # turned back


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
