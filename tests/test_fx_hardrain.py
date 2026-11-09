import pytest

from fxcommon import TICK, check_bit7, check_budget, check_in_bounds, start

FX = 15
NDROPS = 10
MAXR = 9
LIFE = (3, MAXR)                # how far a ring spreads before it vanishes
XRANGE = (9, 270)               # centres: rings never need clipping
YRANGE = (9, 182)
SPAWN = 115 / 256               # chance of a new drop a step while a slot is free
SEEDS = (0x4D2A, 0x1357, 0xBEEF)

ARRAYS = ("hr_on", "hr_x_lo", "hr_x_hi", "hr_y", "hr_r", "hr_life")


def ring(r):
    """The sample's midpoint circle of radius r, each dot once."""
    pts, seen = [], set()
    x, y, e = r, 0, 1 - r
    while x >= y:
        for p in ((x, y), (y, x), (-x, y), (-y, x), (x, -y), (y, -x), (-x, -y), (-y, -x)):
            if p not in seen:
                seen.add(p)
                pts.append(p)
        y += 1
        if e < 0:
            e += 2 * y + 1
        else:
            x -= 1
            e += 2 * (y - x) + 1
    return pts


RINGS = [ring(r) for r in range(MAXR + 1)]


def drops(s):
    """The live drops as (x, y, r, life)."""
    p = lambda name, i: s.peek(s.addr(name) + i)
    return [(p("hr_x_lo", i) | p("hr_x_hi", i) << 8, p("hr_y", i), p("hr_r", i), p("hr_life", i))
            for i in range(NDROPS) if p("hr_on", i)]


def picture(live):
    """The XOR of the live drops' rings."""
    lit = set()
    for x, y, r, _ in live:
        lit ^= {(x + dx, y + dy) for dx, dy in RINGS[r]}
    return lit


@pytest.fixture
def s(built):
    return start(FX)


# ---- budget and bounds ----

def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_worst_case_fits(s):
    """All ten drops at radius 8 going to 9: the widest rings off and on."""
    for i in range(NDROPS):
        for name, v in (("hr_on", 1), ("hr_x_lo", (9 + 29 * i) & 0xFF), ("hr_x_hi", (9 + 29 * i) >> 8),
                        ("hr_y", 9 + 19 * i), ("hr_r", 8), ("hr_life", 9)):
            s.poke(s.addr(name) + i, v)
    s.poke(s.addr("hr_x_lo") + 9, 270 & 0xFF)
    s.poke(s.addr("hr_x_hi") + 9, 270 >> 8)
    place(s)
    s.set_pixels(picture(drops(s)))             # the rings they show
    cycles = s.step()
    print("worst case", cycles)
    assert cycles < 3 * TICK - 300
    assert s.page_pixels() == picture(drops(s))
    check_bit7(s)


def place(s):
    """Set the drawing fields a spawn would from each live drop's x."""
    for i in range(NDROPS):
        if not s.peek(s.addr("hr_on") + i):
            continue
        x = s.peek(s.addr("hr_x_lo") + i) | s.peek(s.addr("hr_x_hi") + i) << 8
        cb, bit = divmod(x, 7)
        off = 1 if bit >= 5 or cb == 1 else 0
        s.poke(s.addr("hr_s") + i, bit)
        s.poke(s.addr("hr_off") + i, off)
        s.poke(s.addr("hr_cbw") + i, cb - 2 + off)


# ---- start ----

def test_starts_on_a_blank_screen(s):
    assert s.page_pixels() == set()
    assert drops(s) == []


# ---- drawing ----

def test_picture_is_xor_of_rings(built):
    """After every step the screen is the XOR of the live drops' rings and
    nothing else: each drop's old ring is gone and its new one is there."""
    assert len(RINGS[0]) == 1 and len(RINGS[1]) == 4
    for seed in SEEDS[:2]:
        s = start(FX, seed=seed)
        for n in range(400):
            s.step()
            assert s.page_pixels() == picture(drops(s)), (seed, n)


def test_drop_limits(built):
    """Each drop lives 3-9 steps and sits where its widest ring stays on the
    screen."""
    for seed in SEEDS:
        s = start(FX, seed=seed)
        for _ in range(400):
            s.step()
            for x, y, r, life in drops(s):
                assert LIFE[0] <= life <= LIFE[1]
                assert 0 <= r <= life
                assert XRANGE[0] <= x <= XRANGE[1]
                assert YRANGE[0] <= y <= YRANGE[1]


def test_rain_keeps_falling(built):
    """While a slot is free, a new drop starts on about 45% of steps."""
    s = start(FX, seed=0x2468)
    chances = spawns = 0
    for _ in range(2000):
        # a slot is free this step if one was free before it or a drop dies in it
        live = drops(s)
        free = len(live) < NDROPS or any(r + 1 > life for _, _, r, life in live)
        s.step()
        births = sum(1 for _, _, r, _ in drops(s) if r == 0)   # a new drop starts at r = 0
        assert births <= 1
        if free:
            chances += 1
            spawns += births
        else:
            assert births == 0
    assert chances > 1000
    assert spawns / chances == pytest.approx(SPAWN, abs=0.1)


def test_spread_covers_the_screen(built):
    """Drops land anywhere in range, not in one corner."""
    xs, ys = [], []
    s = start(FX, seed=0x0F0F)
    for _ in range(600):
        s.step()
        xs += [x for x, _, r, _ in drops(s) if r == 0]
        ys += [y for _, y, r, _ in drops(s) if r == 0]
    assert min(xs) < 40 and max(xs) > 240 and min(ys) < 40 and max(ys) > 150
