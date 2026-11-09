import math

import pytest

from fxcommon import ALLOWED, TICK, check_bit7, check_budget, check_in_bounds, start
from sim import DISP, PAGE1, PAGE2

FX = 16
P, GC, GR, X0, Y0 = 7, 38, 26, 7, 5          # cell pitch, grid, origin
HOLD = 90                                   # steps the solved maze stays up
STEP_BUDGET = 2 * TICK - 300                # every step, the hold's included
D = [(0, -1, 1, 4), (1, 0, 2, 8), (0, 1, 4, 1), (-1, 0, 8, 2)]   # dc, dr, bit, back
SEEDS = (0x4D2A, 0x1357, 0xBEEF)


# ---- the sample's geometry, pixel for pixel ----

def bx(c):
    return X0 + c * P + 2


def by(r):
    return Y0 + r * P + 2


def rect(x0, y0, x1, y1):
    return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)
            if 0 <= x < 280 and 0 <= y < 192}


def block(c, r):
    return rect(bx(c), by(r), bx(c) + 3, by(r) + 3)


def link(a, b):
    (ac, ar), (cc, cr) = a, b
    return rect(min(bx(ac), bx(cc)), min(by(ar), by(cr)),
                max(bx(ac), bx(cc)) + 3, max(by(ar), by(cr)) + 3)


def walls(open_):
    pix = set()
    for r in range(GR):
        for c in range(GC):
            w, x, y = open_[r][c], X0 + c * P, Y0 + r * P
            if not w & 1:
                pix |= rect(x, y, x + P, y)
            if not w & 8:
                pix |= rect(x, y, x, y + P)
            if c == GC - 1 and not w & 2:
                pix |= rect(x + P, y, x + P, y + P)
            if r == GR - 1 and not w & 4:
                pix |= rect(x, y + P, x + P, y + P)
    return pix


def doorway(e):
    """The dots the door clears from the outer wall, and the rectangle that
    runs through it."""
    c, r, side = e
    x, y = X0 + c * P, Y0 + r * P
    if side == 0:
        return rect(x + 1, y, x + P - 1, y), (bx(c), Y0 - 3, bx(c) + 3, by(r))
    if side == 2:
        return rect(x + 1, y + P, x + P - 1, y + P), (bx(c), by(r) + 3, bx(c) + 3, Y0 + GR * P + 3)
    if side == 1:
        return rect(x + P, y + 1, x + P, y + P - 1), (bx(c) + 3, by(r), X0 + GC * P + 3, by(r) + 3)
    return rect(x, y + 1, x, y + P - 1), (X0 - 3, by(r), bx(c), by(r) + 3)


def oval(e):
    c, r, side = e
    cx, cy = bx(c) + 1.5, by(r) + 1.5
    if side == 0:
        cy = Y0
    elif side == 2:
        cy = Y0 + GR * P
    elif side == 1:
        cx = X0 + GC * P
    else:
        cx = X0
    rnd = lambda v: math.floor(v + 0.5)         # JavaScript's Math.round
    return {(rnd(cx + x), rnd(cy + y)) for y in range(-2, 3) for x in range(-3, 4)
            if x * x / 12.25 + y * y / 6.25 <= 1}


def fresh(open_, start_, exit_):
    """The screen right after a maze is built: walls, both doors opened, the
    exit's oval, the stub through the start door and the start block."""
    pix = walls(open_)
    clear_s, stub = doorway(start_)
    clear_e, _ = doorway(exit_)
    pix -= clear_s
    pix -= clear_e
    return pix | oval(exit_) | rect(*stub) | block(start_[0], start_[1])


def body(stack):
    pix = block(*stack[0])
    for a, b in zip(stack, stack[1:]):
        pix |= link(a, b)
    return pix


def extended(pix, exit_):
    """The exit reached: the door opened again, run through, the oval redrawn."""
    clear_e, through = doorway(exit_)
    return (pix - clear_e) | rect(*through) | oval(exit_)


# ---- the effect's state ----

def maze(s):
    a = s.addr("sn_maze")
    return [[s.peek(a + r * GC + c) for c in range(GC)] for r in range(GR)]


def open_bits(s):
    return [[v & 15 for v in row] for row in maze(s)]


def stack(s):
    n = s.peek16(s.addr("sn_sp"))
    c, r = s.addr("sn_stack_c"), s.addr("sn_stack_r")
    return [(s.peek(c + i), s.peek(r + i)) for i in range(n)]


def exit_of(s):
    return tuple(s.peek(s.addr(n)) for n in ("sn_exit_c", "sn_exit_r", "sn_exit_side"))


def start_of(s):
    c, r = stack(s)[0]
    return c, r, s.peek(s.addr("sn_start_side"))


def state(s):
    return s.peek(s.addr("sn_state"))


def hold(s):
    return s.peek(s.addr("sn_hold"))


def shown(s):
    return PAGE2 if s.peek(DISP) else PAGE1


def picture(s):
    """What the model says the shown page holds now."""
    pix = fresh(open_bits(s), start_of(s), exit_of(s)) | body(stack(s))
    return extended(pix, exit_of(s)) if state(s) else pix


def solve(s, cap=3000):
    """Run until the exit is reached; returns the steps it took."""
    for n in range(cap):
        if state(s):
            return n
        s.step()
    raise AssertionError("never solved")


def bring_exit_to_snake(s):
    """Make the snake's head the exit, so the next step reaches it. The door
    side stays, so the stub and oval are drawn at a wrong place: only for
    timing, never for the picture."""
    c, r = stack(s)[-1]
    s.poke(s.addr("sn_exit_c"), c)
    s.poke(s.addr("sn_exit_r"), r)


def check_perfect(o):
    """Neighbours agree, no passage through the outer wall, every cell reached
    by exactly 987 passages: a tree."""
    passages = 0
    for r in range(GR):
        for c in range(GC):
            for dc, dr, bit, back in D:
                if o[r][c] & bit:
                    nc, nr = c + dc, r + dr
                    assert 0 <= nc < GC and 0 <= nr < GR, (c, r, bit)
                    assert o[nr][nc] & back, (c, r, bit)
                    passages += 1
    assert passages == 2 * (GC * GR - 1)
    seen, todo = {(0, 0)}, [(0, 0)]
    while todo:
        c, r = todo.pop()
        for dc, dr, bit, _ in D:
            n = (c + dc, r + dr)
            if o[r][c] & bit and n not in seen:
                seen.add(n)
                todo.append(n)
    assert len(seen) == GC * GR


def check_edge(e):
    c, r, side = e
    assert side in range(4)
    if side == 0:
        assert r == 0 and 0 <= c < GC
    elif side == 2:
        assert r == GR - 1 and 0 <= c < GC
    elif side == 1:
        assert c == GC - 1 and 0 <= r < GR
    else:
        assert c == 0 and 0 <= r < GR


@pytest.fixture
def s(built):
    return start(FX)


# ---- budget and bounds ----

def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_stays_in_bounds_through_the_hold(built):
    """From a fresh maze, through the exit, the hold and the page swap, onto
    the next maze: page 2 gets drawn here, so bit 7 is checked on a real maze."""
    s = start(FX, seed=SEEDS[0])
    s.start_tracking()
    state = s.addr("sn_state")
    for wanted in (1, 0):
        for _ in range(4000):
            if s.peek(state) == wanted:
                break
            s.step()
        assert s.peek(state) == wanted
    assert s.writes_outside(*ALLOWED) == []
    assert s.aux_writes_outside() == []
    assert s.page_pixels(PAGE1) and s.page_pixels(PAGE2)
    check_bit7(s)


def test_direction_choices_are_distinct(built):
    """At a fork each open way is listed once, so each is equally likely."""
    OPT, NOPT = 0x4A, 0x4E              # FXZ+10, FXZ+14
    s = start(FX, seed=SEEDS[1])
    forks = 0
    for _ in range(250):
        s.step()
        opts = [s.peek(OPT + i) for i in range(s.peek(NOPT))]
        assert len(set(opts)) == len(opts), opts
        forks += len(opts) > 1
    assert forks > 0


# ---- the maze ----

def test_maze_is_perfect(built):
    for seed in SEEDS:
        check_perfect(open_bits(start(FX, seed=seed)))


def test_walls_on_screen(built):
    for seed in SEEDS:
        s = start(FX, seed=seed)
        assert s.page_pixels(PAGE1) == fresh(open_bits(s), start_of(s), exit_of(s))
        assert s.page_pixels(PAGE2) == set()
        assert shown(s) == PAGE1


def test_exit_opposite_start(built):
    sides = set()
    for seed in range(1, 13):
        s = start(FX, seed=seed * 0x3A7)
        st, ex = start_of(s), exit_of(s)
        check_edge(st)
        check_edge(ex)
        assert ex[2] == (st[2] + 2) % 4
        assert stack(s) == [st[:2]]
        assert maze(s)[st[1]][st[0]] & 16
        sides.add(st[2])
    assert sides == {0, 1, 2, 3}


# ---- the snake ----

def test_body_is_a_path(built):
    for seed in SEEDS:
        s = start(FX, seed=seed)
        o = open_bits(s)
        for _ in range(4):
            for _ in range(75):
                s.step()
            path = stack(s)
            assert len(set(path)) == len(path)
            for (c, r), (nc, nr) in zip(path, path[1:]):
                bit = next(b for dc, dr, b, _ in D if (c + dc, r + dr) == (nc, nr))
                assert o[r][c] & bit
            for c, r in path:
                assert maze(s)[r][c] & 16


def test_body_on_screen(built):
    """After every step the screen is the built maze plus the body along the
    stack: the links out to the head, and nothing left where it backed out."""
    for seed in SEEDS[:2]:
        s = start(FX, seed=seed)
        base = fresh(open_bits(s), start_of(s), exit_of(s))
        retreats, depth = 0, 1
        for n in range(300):
            s.step()
            if state(s):
                break
            path = stack(s)
            retreats += len(path) < depth
            depth = len(path)
            assert s.page_pixels(PAGE1) == base | body(path), (seed, n)
        assert retreats > 10


def test_solves_and_holds(built):
    """The snake reaches the exit and runs out through its door; the picture
    then stands for 90 steps while the next maze is drawn out of sight, and
    on the 90th a new maze shows, from its start."""
    s = start(FX, seed=0x2468)
    old = open_bits(s)
    steps = solve(s)
    assert 100 < steps < 3000
    assert s.page_pixels(PAGE1) == picture(s)
    assert hold(s) == HOLD
    frozen = s.page_pixels(PAGE1)
    for k in range(1, HOLD):
        s.step()
        assert state(s) == 1 and hold(s) == HOLD - k
        assert shown(s) == PAGE1
        assert s.page_pixels(PAGE1) == frozen
    s.step()
    assert hold(s) == 0 and state(s) == 0
    assert shown(s) == PAGE2
    new = open_bits(s)
    assert new != old
    check_perfect(new)
    st, ex = start_of(s), exit_of(s)
    check_edge(st)
    check_edge(ex)
    assert ex[2] == (st[2] + 2) % 4
    assert stack(s) == [st[:2]]
    assert s.page_pixels(PAGE2) == fresh(new, st, ex)
    s.step()                                    # and it solves the new one
    assert len(stack(s)) == 2
    assert s.page_pixels(PAGE2) == picture(s)


def test_hold_fits(built):
    """From the exit step until the new maze shows, no step overruns 2 ticks,
    and the drawing is done before the hold runs out."""
    for seed in SEEDS:
        s = start(FX, seed=seed)
        for _ in range(5):
            s.step()
        bring_exit_to_snake(s)
        cycles = [s.step()]
        assert state(s) == 1
        for k in range(1, HOLD + 1):
            cycles.append(s.step())
            if k < HOLD:
                assert shown(s) == PAGE1
        assert shown(s) == PAGE2 and state(s) == 0, seed
        assert max(cycles) < STEP_BUDGET, (seed, max(cycles))
        print("seed", hex(seed), "hold worst", max(cycles), "median", sorted(cycles)[len(cycles) // 2])


def test_flip_then_normalize(built):
    """With page 2 showing, the end of the effect leaves that maze on page 1."""
    s = start(FX, seed=0x1357)
    for _ in range(5):
        s.step()
    bring_exit_to_snake(s)
    for _ in range(HOLD + 1):
        s.step()
    assert shown(s) == PAGE2
    for _ in range(3):
        s.step()
    want = s.page_pixels(PAGE2)
    assert want == picture(s)
    s.call("normalize_display")
    assert s.peek(DISP) == 0
    assert s.page_pixels(PAGE1) == want
    check_bit7(s)
