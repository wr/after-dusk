from functools import reduce

import pytest

from fxcommon import TICK, check_bit7, check_budget, check_in_bounds, run, start
from sim import ST_TIMING, VblLatch

FRAMES = 0x2C                   # timing.s: vertical blanks counted

FX = 13
STRIDE = 64                     # each drop array has room for 64
YBIAS = 16512                   # y is kept as y + 64.5 (8 fraction bits)
VSTEP = 25.6                    # speeds go in tenths of a dot: v = 12 + j / 10
ACCEL = 12                      # 1.2 a step
JMAX = 140                      # 26 at most
START_J = (0, 39)               # starting speeds 12.0-15.9
START_X = (0, 310)              # x where a drop starts: in from past the right edge
FIRST_Y = (-64, 191)            # y at the very start: anywhere
TOP_Y = (-60, 0)                # y when it starts again
SEEDS = (0x4D2A, 0x1357, 0xBEEF)

ARRAYS = ("rn_yf", "rn_yk", "rn_j", "rn_qb", "rn_qm",
          "rn_r1s", "rn_r1e", "rn_m1", "rn_b1", "rn_r2s", "rn_r2e")


def signed8(v):
    return v - 0x100 if v & 0x80 else v


def ndrops(s):
    return s.labels["rn_ndrops"]


def speed(s, j):
    """Speed and streak length for speed index j, 8.8."""
    p = lambda name: s.peek(s.addr(name) + j)
    return p("rn_vl") | p("rn_vh") << 8, p("rn_ll") | p("rn_lh") << 8


def drop(s, i):
    """Drop i as (Q, y, j): its lane Q (the dot of row r is at x = (Q - r) // 7),
    y with 8 fraction bits, and its speed index."""
    p = lambda name: s.peek(s.addr(name) + i)
    y = (p("rn_yf") | p("rn_yk") << 8) - YBIAS
    return signed8(p("rn_qb")) * 49 + p("rn_qm"), y, p("rn_j")


def set_drop(s, i, q, y, j):
    qb, qm = divmod(q, 49)
    y += YBIAS
    assert 0 <= y < 0x10000
    for name, val in (("rn_qb", qb), ("rn_qm", qm), ("rn_yf", y), ("rn_yk", y >> 8),
                      ("rn_j", j)):
        s.poke(s.addr(name) + i, val)


def drops(s):
    return [drop(s, i) for i in range(ndrops(s))]


def streak(s, q, y, j):
    """A drop's streak: from (x, y) to (x - l / 7, y + l), l = 0.9 v, one dot a
    row from round(y) to round(y + l), each on the drop's lane, clipped to the
    screen."""
    l = speed(s, j)[1]
    a, b = (y + 128) >> 8, (y + l + 128) >> 8
    return {((q - r) // 7, r) for r in range(max(a, 0), min(b, 191) + 1)
            if 0 <= (q - r) // 7 <= 279}


def start_x(q, y):
    """Where on the top row of its streak a fresh drop (whole y) is: x0."""
    assert y & 0xFF == 0
    x7 = q - (y >> 8) - 3
    assert x7 % 7 == 0
    return x7 // 7


def fresh(d, ys):
    q, y, j = d
    return (ys[0] <= y >> 8 <= ys[1] and y & 0xFF == 0 and START_J[0] <= j <= START_J[1]
            and START_X[0] <= start_x(q, y) <= START_X[1])


def fell(s, d):
    """The sample's fall for one drop: on by its speed, which grows by 1.2 up to
    26; past the bottom it starts again above the top (None)."""
    q, y, j = d
    y += speed(s, j)[0]
    if y > 191 << 8:
        return None
    return q, y, min(j + ACCEL, JMAX)


@pytest.fixture
def s(built):
    return start(FX)


# ---- budget and bounds ----

def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median, "drops", ndrops(start(FX)))


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_steps_count_every_blank(built):
    """Steps take about two frames; every vertical blank they work through is counted."""
    s = start(FX)
    VblLatch(s)
    s.poke(ST_TIMING, 1)
    s.poke16(FRAMES, 0)
    first = s.mpu.processorCycles // TICK
    run(s, 100)
    crossed = s.mpu.processorCycles // TICK - first
    assert crossed > 100
    assert crossed - 1 <= s.peek16(FRAMES) <= crossed


# ---- speeds ----

def test_speeds_are_tenths_from_12_to_26_and_streaks_nine_tenths(s):
    for j in range(JMAX + 1):
        v, l = speed(s, j)
        assert abs(v - (12 + j / 10) * 256) <= 1
        assert abs(l - 0.9 * (12 + j / 10) * 256) <= 1


# ---- the drops ----

def test_starts_on_a_blank_screen_with_drops_anywhere(built):
    ys, xs, js = [], [], []
    for seed in SEEDS:
        s = start(FX, seed=seed)
        assert s.page_pixels() == set()
        ds = drops(s)
        assert len(set(ds)) == len(ds)
        for d in ds:
            assert fresh(d, FIRST_Y), d
            ys.append(d[1] >> 8)
            xs.append(start_x(d[0], d[1]))
            js.append(d[2])
    assert min(ys) < -50 and max(ys) > 170
    assert min(xs) < 20 and max(xs) > 290
    assert min(js) < 4 and max(js) > 35


def test_every_drop_falls_each_step(s):
    """Every drop moves on each step, and only those: the rest of each array is
    never touched."""
    s.start_tracking()
    for _ in range(30):
        before = drops(s)
        s.step()
        for b, a in zip(before, drops(s)):
            want = fell(s, b)
            if want is None:
                assert fresh(a, TOP_Y), a
            else:
                assert a == want
    n = ndrops(s)
    spare = {s.addr(name) + i for name in ARRAYS for i in range(n, STRIDE)}
    assert not spare & s.mem.written


def test_speeds_up_to_26_at_most(s):
    set_drop(s, 0, 7 * 140 + 3, 20 << 8, JMAX - 5)
    set_drop(s, 1, 7 * 100 + 3, 20 << 8, JMAX)
    s.step()
    assert drop(s, 0) == (7 * 140 + 3, (20 << 8) + speed(s, JMAX - 5)[0], JMAX)
    assert drop(s, 1)[2] == JMAX
    assert speed(s, JMAX) == (26 << 8, round(0.9 * 26 * 256))


def test_starts_again_above_the_top_after_passing_the_bottom(s):
    v = speed(s, 0)[0]                                       # 12
    set_drop(s, 0, 7 * 140 + 3, (191 << 8) - v + 1, 0)      # to just past 191
    set_drop(s, 1, 7 * 140 + 3, (191 << 8) - v, 0)          # to 191: still on
    s.step()
    assert fresh(drop(s, 0), TOP_Y)
    assert drop(s, 1)[1] == 191 << 8
    assert ((7 * 140 + 3 - 191) // 7, 191) in s.page_pixels()


def test_starting_places_spread_across_and_past_the_right_edge(s):
    xs, ys = [], []
    for _ in range(150):
        before = drops(s)
        s.step()
        for b, a in zip(before, drops(s)):
            if fell(s, b) is None:
                xs.append(start_x(a[0], a[1]))
                ys.append(a[1] >> 8)
    assert len(xs) > 300
    assert min(xs) < 10 and max(xs) > 300 and sum(x > 279 for x in xs) > 20
    assert min(ys) < -55 and max(ys) > -5


# ---- drawing ----

CASES = [   # lane, y (8 fraction bits), speed index (streak 0.9 (12 + j/10))
    (7 * 140 + 50 + 3, 50 << 8, 0),                 # in the middle, rows 50-61
    (7 * 60 + 3, (100 << 8) + 102, 0),              # rounding both ends
    (7 * 60 + 3, (100 << 8) + 154, 0),
    (7 * 100 - 5 + 3, -5 << 8, 20),                 # off the top
    (7 * 33, -154, 0),                              # y -0.6: from row 0
    (7 * 200 + 3, (185 << 8) + 150, 60),            # off the bottom
    (49 * 10 + 3 + 70, 70 << 8, 40),                # into the next byte to the left
    (49 * 10 + 48 + 70, 70 << 8, JMAX),             # from a byte's last dot, 24 rows
    (49 * 10 + 20 + 70, 70 << 8, JMAX),
    (10 + 30, 30 << 8, 40),                         # off the left edge part way down
    (49 * 40 + 5 + 30, 30 << 8, 40),                # in from past the right edge
    (49 * 40 + 30 + 30, 30 << 8, 0),                # wholly past the right edge
    (49 * 41 + 2 + 30, 30 << 8, JMAX),              # further past it
    (-3 + 40, 40 << 8, 30),                         # wholly past the left edge
    (7 * 140, -40 << 8, 0),                         # wholly above the top
    (7 * 140 + 191 + 3, 191 << 8, 0),               # one row, the bottom one
    (7 * 279 + 3, 0, JMAX),                         # the rightmost dot, top row
    (7 * 279 + 3 + 100, 100 << 8, JMAX),
    (7 * 279 + 3 + 168, 168 << 8, JMAX),            # down to the bottom row
    (49 * 40 + 20 + 168, 168 << 8, JMAX),           # in from the right at the bottom
]


@pytest.mark.parametrize("case", CASES)
def test_draws_and_rubs_out_one_streak(s, case):
    q, y, j = case
    s.fill_page(0x20, 0)
    set_drop(s, 0, q, y, j)
    s.call("rn_plan", x=0)
    s.call("rn_flip", x=0)
    assert s.page_pixels() == streak(s, q, y, j)
    s.call("rn_flip", x=0)
    assert s.page_pixels() == set()


def test_streaks_lean_a_dot_left_every_7_rows(s):
    q = 7 * 140 + 3 + 20
    s.fill_page(0x20, 0)
    set_drop(s, 0, q, 20 << 8, JMAX)                         # 23.4 long: rows 20-43
    s.call("rn_plan", x=0)
    s.call("rn_flip", x=0)
    lit = sorted(s.page_pixels(), key=lambda p: p[1])
    assert [y for _, y in lit] == list(range(20, 44))
    assert [x for x, _ in lit] == [140] * 4 + [139] * 7 + [138] * 7 + [137] * 6


def test_screen_holds_just_the_current_streaks(s):
    """Old streaks are rubbed out as drops fall: the screen is each drop's
    streak where it is now (streaks are flipped onto the screen, so where two
    drops' streaks cross, the dots they share are dark)."""
    for n in (20, 7, 31):
        run(s, n)
        want = reduce(set.symmetric_difference, (streak(s, *d) for d in drops(s)), set())
        assert len(want) > 300
        assert s.page_pixels() == want


def test_streaks_lengthen_as_drops_fall(s):
    run(s, 40)
    rows = [(y >> 8, len(streak(s, q, y, j))) for q, y, j in drops(s)
            if 25 <= y >> 8 <= 165 and 30 <= (q - (y >> 8)) // 7 <= 250]
    high = [n for y, n in rows if y < 80]
    low = [n for y, n in rows if y > 110]
    assert high and low
    assert sum(low) / len(low) > sum(high) / len(high) + 2
