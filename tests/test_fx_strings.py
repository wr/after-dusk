import math
import random

import pytest

from fxcommon import ALLOWED, OVERHEAD, TICK, check_bit7, check_budget, check_in_bounds, fx_entry, run, start
from sim import PAGE1, ST_TIMING, VblLatch

FX = 7
KEEP = 24                       # strings kept per ribbon
RING = 32                       # ring slots per ribbon
PERIM = 2 * (279 + 191)         # 940: the screen's edge, clockwise from the top-left corner
SWING = 0.3                     # far end: s + PERIM (0.5 + 0.3 sin ph)
V_MIN, V_MAX = 307, 614         # speed limits, 8.8 (1.2-2.4 dots a step)
V0_MIN, V0_MAX = 359, 563       # starting speeds, 8.8 (1.4-2.2 dots a step)
DPH_MIN, DPH_MAX = 83, 146      # phase step, 65536 = a full turn (0.008-0.014 radians)
FRAMES = 0x2C                   # timing.s: vertical blanks counted


@pytest.fixture
def s(built):
    return start(FX)


# ---- reading the effect's state ----

def ribbon(s, g, name):
    return s.peek(s.addr("str_" + name) + g)


def speed(s, g):
    return ribbon(s, g, "vl") | ribbon(s, g, "vh") << 8


def phase(s, g):
    return ribbon(s, g, "pl") | ribbon(s, g, "ph") << 8


def phase_step(s, g):
    """Ribbon g's phase step, signed."""
    d = ribbon(s, g, "dl") | ribbon(s, g, "dh") << 8
    return d - 0x10000 if d & 0x8000 else d


def set_phase(s, g, p):
    s.poke(s.addr("str_pl") + g, p & 0xFF)
    s.poke(s.addr("str_ph") + g, (p >> 8) & 0xFF)


def strings(s, g):
    """Ribbon g's kept strings, oldest first, as (xa, ya, xc, yc)."""
    head, count = ribbon(s, g, "head"), ribbon(s, g, "count")
    out = []
    for i in range(count):
        slot = g * RING + ((head - count + i) & (RING - 1))
        out.append((s.peek(s.addr("str_xal") + slot) | s.peek(s.addr("str_xah") + slot) << 8,
                    s.peek(s.addr("str_ya") + slot),
                    s.peek(s.addr("str_xcl") + slot) | s.peek(s.addr("str_xch") + slot) << 8,
                    s.peek(s.addr("str_yc") + slot)))
    return out


def set_string(s, g, i, xa, ya, xc, yc):
    """Overwrite ribbon g's string i (0 = oldest)."""
    head, count = ribbon(s, g, "head"), ribbon(s, g, "count")
    slot = g * RING + ((head - count + i) & (RING - 1))
    for name, v in (("xal", xa & 0xFF), ("xah", xa >> 8), ("ya", ya),
                    ("xcl", xc & 0xFF), ("xch", xc >> 8), ("yc", yc)):
        s.poke(s.addr("str_" + name) + slot, v)


def edge_pos(x, y):
    """Where (x, y) lies along the screen's edge (the inverse of the sample's edgePt)."""
    if y == 0 and 0 <= x < 279:
        return x
    if x == 279 and 0 <= y < 191:
        return 279 + y
    if y == 191 and 0 < x <= 279:
        return 470 + 279 - x
    if x == 0 and 0 < y <= 191:
        return 749 + 191 - y
    raise AssertionError(f"({x}, {y}) is not on the screen's edge")


def separation(st):
    xa, ya, xc, yc = st
    return (edge_pos(xc, yc) - edge_pos(xa, ya)) % PERIM


def far_end_wanted(ph):
    return PERIM * (0.5 + SWING * math.sin(ph * 2 * math.pi / 65536))


# ---- the line routine's dots ----

def segment(x0, y0, x1, y1):
    dx, dy, sy = x1 - x0, abs(y1 - y0), 1 if y1 >= y0 else -1
    x, y, dots = x0, y0, set()
    if dx >= dy:
        e = dx // 2
        for _ in range(dx + 1):
            dots.add((x, y))
            e -= dy
            if e < 0:
                e += dx
                y += sy
            x += 1
    else:
        e = dy // 2
        for _ in range(dy + 1):
            dots.add((x, y))
            y += sy
            e -= dx
            if e < 0:
                e += dy
                x += 1
    return dots


def string_dots(xa, ya, xc, yc):
    """The dots str_line draws: Bresenham, left to right; a line more than 255 dots across
    is drawn as two halves meeting at (about) its middle."""
    if xc < xa:
        xa, ya, xc, yc = xc, yc, xa, ya
    dx = xc - xa
    if dx <= 255:
        return segment(xa, ya, xc, yc)
    xm = xa + dx // 2
    ym = ya + (yc - ya) // 2 if yc >= ya else ya - (ya - yc) // 2
    return segment(xa, ya, xm, ym) | segment(xm, ym, xc, yc)


def draw(s, xa, ya, xc, yc, mode):
    for name, v in (("lx0", xa), ("lx1", xc)):
        s.poke16(s.addr("str_" + name), v)
    s.poke(s.addr("str_ly0"), ya)
    s.poke(s.addr("str_ly1"), yc)
    s.poke(s.addr("str_mode"), mode)
    return s.call("str_line", max_cycles=100_000)


# ---- budget and bounds ----

def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_longest_strings_fit(s):
    """The costliest string the effect can draw, four times over, still fits a step."""
    hard = fx_entry(s, FX)[3] * TICK - OVERHEAD
    worst, shape = 0, None
    for pa in range(0, PERIM, 5):
        for d in (188, 230, 290, 350, 410, 470, 530, 590, 650, 710, 752):
            pc = (pa + d) % PERIM
            a, c = edge_point(pa), edge_point(pc)
            cycles = draw(s, *a, *c, 1)
            if cycles > worst:
                worst, shape = cycles, (a, c)
    print("costliest string", worst, "cycles", shape)
    assert 4 * worst + 3000 < hard


def test_four_diagonals_fit(s):
    """A step that rubs out two corner-to-corner strings and draws two more."""
    run(s, KEEP + 4)
    set_string(s, 0, 0, 0, 0, 279, 191)
    set_string(s, 1, 0, 279, 0, 0, 191)
    for g, sint in ((0, 939), (1, 278)):           # the new ends land on corners too
        s.poke(s.addr("str_sl") + g, sint & 0xFF)
        s.poke(s.addr("str_sh") + g, sint >> 8)
        s.poke(s.addr("str_sf") + g, 10)
        s.poke(s.addr("str_vl") + g, V_MIN & 0xFF)  # at the slowest, s moves on 1 dot
        s.poke(s.addr("str_vh") + g, V_MIN >> 8)
        set_phase(s, g, -phase_step(s, g))          # phase 0 once moved: d = 470
    cycles = s.step()
    assert strings(s, 0)[-1] == (0, 0, 279, 191)
    assert strings(s, 1)[-1] == (279, 0, 0, 191)
    hard = fx_entry(s, FX)[3] * TICK - OVERHEAD
    print("four diagonals", cycles, "cycles")
    assert cycles < hard


def test_steps_count_every_blank(built):
    """A step takes a few frames; it counts every vertical blank it works through."""
    s = start(FX)
    VblLatch(s)
    s.poke(ST_TIMING, 1)
    s.poke16(FRAMES, 0)
    first = s.mpu.processorCycles // TICK
    run(s, KEEP + 60)
    crossed = s.mpu.processorCycles // TICK - first
    assert crossed > 100
    assert crossed - 1 <= s.peek16(FRAMES) <= crossed


def edge_point(p):
    """The sample's edgePt, for whole positions."""
    p %= PERIM
    if p < 279:
        return p, 0
    p -= 279
    if p < 191:
        return 279, p
    p -= 191
    if p < 279:
        return 279 - p, 191
    return 0, 191 - (p - 279)


# ---- the line routine ----

def test_lines_are_drawn_solid_and_rubbed_out_exactly(s):
    s.fill_page(PAGE1, 0)
    rnd = random.Random(7)
    lines = [(0, 0, 279, 0), (279, 191, 0, 191), (0, 0, 0, 191), (279, 191, 279, 0),
             (0, 0, 279, 191), (279, 0, 0, 191), (0, 191, 279, 0), (5, 5, 5, 5),
             (10, 20, 265, 30), (10, 20, 266, 30), (3, 100, 9, 90), (140, 0, 141, 191),
             (24, 0, 279, 150), (255, 10, 279, 180), (6, 50, 7, 51)]
    lines += [(rnd.randrange(280), rnd.randrange(192), rnd.randrange(280), rnd.randrange(192))
              for _ in range(40)]
    for ln in lines:
        draw(s, *ln, 1)
        assert s.page_pixels(PAGE1) == string_dots(*ln), ln
        draw(s, *ln, 0)
        assert s.page_pixels(PAGE1) == set(), ln
    for ln in lines:                                   # set on top of others: never flips
        draw(s, *ln, 1)
        assert string_dots(*ln) <= s.page_pixels(PAGE1), ln


def test_rubbing_out_leaves_other_dots_alone(s):
    s.fill_page(PAGE1, 0x7F)
    draw(s, 0, 0, 279, 191, 0)
    lit = s.page_pixels(PAGE1)
    gone = string_dots(0, 0, 279, 191)
    assert lit == {(x, y) for x in range(280) for y in range(192)} - gone


# ---- the look ----

def test_ribbons_start_anywhere_at_their_own_speed_and_turn(built):
    steps = set()
    for seed in (0x1111, 0x2222, 0x3333, 0x4444, 0x5555, 0x6666, 0x7777, 0x8888):
        s = start(FX, seed=seed)
        for g in (0, 1):
            assert V0_MIN <= speed(s, g) <= V0_MAX                 # 1.4-2.2 dots a step
            assert DPH_MIN <= abs(phase_step(s, g)) <= DPH_MAX     # 0.008-0.014 radians
            steps.add(phase_step(s, g))
            assert ribbon(s, g, "count") == 0
            assert (ribbon(s, g, "sl") | ribbon(s, g, "sh") << 8) < PERIM
    assert min(steps) < 0 < max(steps)                 # either way round
    assert len(steps) > 8


def test_keeps_24_strings_per_ribbon(s):
    run(s, KEEP + 20)
    for g in (0, 1):
        assert ribbon(s, g, "count") == KEEP
        assert len(strings(s, g)) == KEEP


def test_every_string_crosses_the_screen(s):
    run(s, KEEP + 20)
    for g in (0, 1):
        for st in strings(s, g):
            assert (0.5 - SWING) * PERIM - 1 <= separation(st) <= (0.5 + SWING) * PERIM + 1, st


def test_far_end_follows_the_phase(s):
    """All the way round the phase, including the far end's widest swings (282 dots
    either way of across)."""
    for k in range(64):
        for g in (0, 1):
            set_phase(s, g, k * 1024 + 300 * g + 37)
        s.step()
        for g in (0, 1):
            want = far_end_wanted(phase(s, g))
            assert abs(separation(strings(s, g)[-1]) - want) <= 1.5, (k, g)


def test_each_ribbon_turns_at_its_own_fixed_pace(s):
    steps = [phase_step(s, g) for g in (0, 1)]
    before = [phase(s, g) for g in (0, 1)]
    run(s, 100)
    assert [phase_step(s, g) for g in (0, 1)] == steps
    assert [phase(s, g) for g in (0, 1)] == [(p + 100 * d) & 0xFFFF for p, d in zip(before, steps)]


def test_speeds_drift_within_limits(s):
    s.poke(s.addr("str_vl"), V_MIN & 0xFF)
    s.poke(s.addr("str_vh"), V_MIN >> 8)
    s.poke(s.addr("str_vl") + 1, V_MAX & 0xFF)
    s.poke(s.addr("str_vh") + 1, V_MAX >> 8)
    seen = [set(), set()]
    for _ in range(80):
        s.step()
        for g in (0, 1):
            v = speed(s, g)
            assert V_MIN <= v <= V_MAX
            seen[g].add(v)
    assert all(len(v) > 10 for v in seen)
    assert V_MIN in seen[0] and V_MAX in seen[1]
    steps = [abs(a - b) for g in (0, 1) for a, b in zip(sorted(seen[g]), sorted(seen[g])[1:])]
    assert max(steps) <= 2 * 13                        # drifts about 0.05 a step


def test_ribbons_move_smoothly(s):
    """The near end moves on 1-3 dots every step, so no two strings share it; the far end
    moves with it plus the phase's drift, up to 4 dots either way."""
    s.step()
    last = [strings(s, g)[-1] for g in (0, 1)]
    moved = [0, 0]
    for _ in range(60):
        s.step()
        for g in (0, 1):
            new = strings(s, g)[-1]
            near = (edge_pos(*new[:2]) - edge_pos(*last[g][:2])) % PERIM
            far = (edge_pos(*new[2:]) - edge_pos(*last[g][2:]) + PERIM // 2) % PERIM - PERIM // 2
            assert near in (1, 2, 3)           # s moves 1.2-2.4 dots a step
            assert -4 <= far - near <= 4       # 282 sin ph moves up to 3.95 dots a step
            moved[g] += near
            last[g] = new
    assert all(m >= 60 * 1.2 - 1 for m in moved)


def test_screen_holds_only_the_kept_strings(s):
    """The oldest string goes before the newest comes, so nothing is left behind, and the
    newest strings are drawn solid, never by flipping dots."""
    for n in (KEEP + 10, 15):
        run(s, n)
        lit = s.page_pixels(PAGE1)
        assert lit <= kept_dots(s)
        for g in (0, 1):
            assert string_dots(*strings(s, g)[-1]) <= lit


def kept_dots(s):
    kept = set()
    for g in (0, 1):
        for st in strings(s, g):
            kept |= string_dots(*st)
    return kept


def test_screen_does_not_fill_up(s):
    """Over a long run the screen only ever holds the kept strings. How many dots they light
    depends on where the ribbons lie (strings across the screen are longer than strings across
    a corner), so the count goes up and down, but never towards a full screen."""
    for _ in range(8):
        run(s, 60)
        lit = s.page_pixels(PAGE1)
        assert lit <= kept_dots(s)
        assert 2000 < len(lit) < 280 * 192 * 0.2


def test_near_wrap(s):
    for g in (0, 1):
        s.poke(s.addr("str_head") + g, RING - 3)
        s.poke(s.addr("str_sl") + g, (PERIM - 2) & 0xFF)
        s.poke(s.addr("str_sh") + g, (PERIM - 2) >> 8)
        set_phase(s, g, 0xFFF0)
    s.start_tracking()
    run(s, KEEP + 10)
    assert s.writes_outside(*ALLOWED) == []
    for g in (0, 1):
        assert ribbon(s, g, "count") == KEEP
        for st in strings(s, g):
            separation(st)
