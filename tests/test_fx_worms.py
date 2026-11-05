import math

import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start
from sim import PAGE1

FX = 4
STEP_X = 2 * 256 / 4            # a step's move, 1/256 dots: a quarter of the old 2 dots across
STEP_Y = 1.7 * 256 / 4          # ... and of 1.7 down: about 10 dots a second, the original's pace
TURN = 6                        # most a worm turns a step, 256 = a full turn (0.15 radians)
RING = 32                       # rings remembered per worm


def lit_page(s):
    s.fill_page(PAGE1, 0x7F)


def heads(s):
    n = s.peek(s.addr("wrm_count"))
    out = []
    for i in range(n):
        x = s.peek(s.addr("wrm_xi") + i) | (s.peek(s.addr("wrm_xh") + i) << 8)
        out.append((x, s.peek(s.addr("wrm_yi") + i)))
    return out


def bodies(s):
    """Each worm's head x and y in 1/256 dots, and its heading."""
    a = s.addr
    out = []
    for i in range(s.peek(a("wrm_count"))):
        x = s.peek(a("wrm_xf") + i) | s.peek(a("wrm_xi") + i) << 8 | s.peek(a("wrm_xh") + i) << 16
        y = s.peek(a("wrm_yf") + i) | s.peek(a("wrm_yi") + i) << 8
        out.append((x, y, s.peek(a("wrm_a") + i)))
    return out


@pytest.fixture
def s(built):
    return start(FX, prepare=lit_page)


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_keeps_the_screen(built):
    s = start(FX, prepare=lit_page)
    dark = 280 * 192 - len(s.page_pixels())
    assert dark < 300                                  # init only starts the worms


def test_eats(s):
    run(s, 200)
    dark = 280 * 192 - len(s.page_pixels())
    print("dark dots after 200 steps:", dark)
    assert dark >= 2000


def test_crawls_about_10_dots_a_second(s):
    moves, turns = 0, set()
    before = bodies(s)
    for _ in range(300):
        s.step()
        after = bodies(s)
        for (x0, y0, a0), (x1, y1, a1) in zip(before, after):
            if (x0, y0) == (x1, y1):
                continue                               # turned back from an edge
            turn = (a1 - a0 + 128) % 256 - 128
            assert -TURN <= turn <= TURN
            ang = a1 * math.pi / 128
            assert abs(x1 - x0 - STEP_X * math.cos(ang)) <= 1
            assert abs(y1 - y0 - STEP_Y * math.sin(ang)) <= 1
            moves += 1
            turns.add(turn)
        before = after
    assert moves > 1500
    assert min(turns) == -TURN and max(turns) == TURN


def rings(s, w):
    """Worm w's body rings, oldest first."""
    a = s.addr
    head, n = s.peek(a("wrm_head") + w), s.peek(a("wrm_len") + w) + 1
    out = []
    for k in range(head - n + 1, head + 1):
        i = w * RING + k % RING
        out.append((s.peek(a("ring_xl") + i) | s.peek(a("ring_xh") + i) << 8, s.peek(a("ring_y") + i)))
    return out


def test_worms_are_18_to_28_rings_long(s):
    lengths = [s.peek(s.addr("wrm_len") + i) for i in range(6)]
    assert all(18 <= n <= 28 for n in lengths)


def test_a_ring_every_2_dots(s):
    """The head cuts a ring into the body every fourth move, so the rings
    sit about 2 dots apart, as when a worm moved 2 dots a step."""
    run(s, 400)
    gaps = []
    for w in range(6):
        body = rings(s, w)
        gaps += [((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5 for (x0, y0), (x1, y1) in zip(body, body[1:])]
    assert all(gap <= 3 for gap in gaps)
    assert sum(gaps) / len(gaps) >= 1.4


def test_bodies_stay_striped_between_head_and_tail(built):
    """On a black screen a worm shows its whole body, not just a head and a tail."""
    for seed in (0x4D2A, 0x1357, 0xBEEF):
        s = start(FX, seed=seed)
        run(s, 400)
        lit = len(s.page_pixels())
        print("lit dots after 400 steps:", lit)
        assert lit > 450


def test_bounds(s):
    assert s.peek(s.addr("wrm_count")) == 6
    for _ in range(1000):
        s.step()
        for x, y in heads(s):
            assert 4 <= x <= 275 and 4 <= y <= 187, (x, y)


def test_near_wrap(s):
    for i in range(6):
        s.poke(s.addr("wrm_head") + i, 31)
    s.start_tracking()
    run(s, 50)
    assert s.writes_outside(*ALLOWED) == []
