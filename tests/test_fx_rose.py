import math

import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start

FX = 8
A, B, XA = 36, 18, 1.1          # ring radius, loop radius, the IIc's wide dots
CX, CY = 140, 96                # centre of the figure
KEEP = 900                      # points (dots) kept on screen
PER_STEP = 4                    # points added each step
RING = 1024                     # slots in the point ring
REPICK = 900                    # steps between new loop counts
TURN = 1 << 24                  # angles: 24 bits, 256 table steps to a turn
DT = 0.03                       # radians a point, t
DROT = 0.0008                   # radians a point, rot


@pytest.fixture
def s(built):
    return start(FX)


def angle(s, name):
    a = s.addr(name)
    return s.peek(a) | (s.peek(a + 1) << 8) | (s.peek(a + 2) << 16)


def radians(units):
    return units * 2 * math.pi / TURN


def k_of(s):
    """The loop count k, from the per-point step of k t."""
    return radians(angle(s, "rose_kdt")) / DT


def kept(s):
    """The kept points, oldest first, as (x, y) of each dot's top-left."""
    tail, count = s.peek16(s.addr("rose_tail")), s.peek16(s.addr("rose_count"))
    xs, ys = s.addr("rose_x"), s.addr("rose_y")
    return [(s.peek(xs + (tail + i) % RING), s.peek(ys + (tail + i) % RING)) for i in range(count)]


def block(x, y):
    return {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)}


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_dots_stay_in_the_ring(s):
    """Every lit dot is between A - B and A + B from the middle, x shrunk by 1.1. A dot drawn at
    (x, y) covers x..x+1 and y..y+1, so the dots' middle is at (140.5, 96.5)."""
    run(s, 300)
    lit = s.page_pixels()
    assert lit
    for x, y in lit:
        r = math.hypot((x - CX - 0.5) / XA, y - CY - 0.5)
        assert A - B - 2 <= r <= A + B + 2, (x, y, r)


def test_points_follow_the_formula(s):
    """x = 140 + 1.1 (A cos(t + rot) + B cos(k t + rot)), y = 96 + A sin(t + rot) + B sin(k t + rot)."""
    run(s, 40)
    for _ in range(20):
        t, kt, rot = (radians(angle(s, n)) for n in ("rose_t", "rose_kt", "rose_rot"))
        kdt = radians(angle(s, "rose_kdt"))
        s.step()
        pts = kept(s)[-PER_STEP:]
        for i, (x, y) in enumerate(pts, 1):
            a1 = t + i * DT + rot + i * DROT
            a2 = kt + i * kdt + rot + i * DROT
            ex = CX + XA * (A * math.cos(a1) + B * math.cos(a2))
            ey = CY + A * math.sin(a1) + B * math.sin(a2)
            assert abs(x - ex) <= 2 and abs(y - ey) <= 2, ((x, y), (ex, ey))


def test_dots_are_2x2_blocks(s):
    s.step()
    pts = kept(s)
    assert len(pts) == PER_STEP
    assert s.page_pixels() == set().union(*(block(x, y) for x, y in pts))
    run(s, 300)
    x, y = kept(s)[-1]                          # the newest dot is always whole
    assert block(x, y) <= s.page_pixels()


def test_keeps_900_points(s):
    run(s, KEEP // PER_STEP - 1)
    assert s.peek16(s.addr("rose_count")) == KEEP - PER_STEP
    run(s, 1)
    assert s.peek16(s.addr("rose_count")) == KEEP
    run(s, 100)
    assert s.peek16(s.addr("rose_count")) == KEEP


def test_screen_holds_only_the_kept_dots(s):
    """Old dots are rubbed out, so over a long run (two new loop counts) the screen never holds
    more than the 900 kept dots."""
    for _ in range(4):
        run(s, 500)
        lit = s.page_pixels()
        allowed = set().union(*(block(x, y) for x, y in kept(s)))
        assert lit <= allowed
        assert 2000 < len(lit) <= KEEP * 4


def test_starts_with_a_loop_count_of_5_to_11(built):
    for seed in (0x1111, 0x2222, 0x3333, 0x4444, 0x5555):
        k = k_of(start(FX, seed=seed))
        assert 5 <= int(k) <= 11
        assert 0.0149 <= k - int(k) <= 0.0401


def test_loops_match_k(s):
    """The trail swings out and back in k - 1 times each time round the ring."""
    k = k_of(s)
    run(s, KEEP // PER_STEP)
    outs, inside = 0, True
    for x, y in kept(s):
        r = math.hypot((x - CX) / XA, y - CY)
        if inside and r > 46:
            outs, inside = outs + 1, False
        elif not inside and r < 34:
            inside = True
    turns = KEEP * DT / (2 * math.pi)            # rot turns both terms alike
    assert abs(outs - (k - 1) * turns) <= 2


def test_loop_count_changes_every_900_steps(built):
    seen = set()
    for seed in (0x1111, 0x2222, 0x3333, 0x4444, 0x5555):
        s = start(FX, seed=seed)
        k0 = angle(s, "rose_kdt")
        run(s, 10)
        assert angle(s, "rose_kdt") == k0               # held between picks
        assert s.peek16(s.addr("rose_n")) == 10
        for _ in range(5):
            s.poke16(s.addr("rose_n"), REPICK - 1)
            s.step()
            assert s.peek16(s.addr("rose_n")) == 0
            k = k_of(s)
            assert 5 <= int(k) <= 11
            assert 0.0149 <= k - int(k) <= 0.0401
            seen.add(int(k))
    assert len(seen) >= 4


def test_figure_turns_as_it_goes(s):
    """Each point t moves on 0.03 radians and rot, which turns the whole figure, 0.0008."""
    t0, rot0 = angle(s, "rose_t"), angle(s, "rose_rot")
    run(s, 50)                                  # 200 points: t goes round less than once
    points = 50 * PER_STEP
    assert radians((angle(s, "rose_t") - t0) % TURN) / points == pytest.approx(DT, rel=0.001)
    assert radians((angle(s, "rose_rot") - rot0) % TURN) / points == pytest.approx(DROT, rel=0.005)


def test_ring_wraps(s):
    s.poke16(s.addr("rose_head"), RING - 3)
    s.poke16(s.addr("rose_tail"), RING - 3)
    s.start_tracking()
    run(s, KEEP // PER_STEP + 20)
    assert s.writes_outside(*ALLOWED) == []
    assert s.peek16(s.addr("rose_count")) == KEEP
    assert s.peek16(s.addr("rose_head")) == (RING - 3 + KEEP + 20 * PER_STEP) % RING
    assert s.page_pixels() <= set().union(*(block(x, y) for x, y in kept(s)))
