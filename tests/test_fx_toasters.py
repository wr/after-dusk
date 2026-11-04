import sys

import pytest

from conftest import ROOT
from fxcommon import check_bit7, check_budget, check_in_bounds, run, start
from sim import DISP, PAGE1, PAGE2

sys.path.insert(0, str(ROOT / "tools"))
import gen_art  # noqa: E402

FX = 0
SPRITES = gen_art.sprites()


def objects(s):
    n = s.peek(s.addr("tst_count"))
    out = []
    for i in range(n):
        x = s.peek(s.addr("tst_xl") + i) | (s.peek(s.addr("tst_xh") + i) << 8)
        y = s.peek(s.addr("tst_yl") + i) | (s.peek(s.addr("tst_yh") + i) << 8)
        x = x - 0x10000 if x & 0x8000 else x
        y = y - 0x10000 if y & 0x8000 else y
        out.append((x, y, s.peek(s.addr("tst_kind") + i), s.peek(s.addr("tst_frame") + i)))
    return out


def sprite_id(kind, frame):
    return 3 if kind else (0, 1, 2, 1)[(frame >> 1) & 3]


def frame_pixels(s):
    """What the shown page should hold: every object's sprite at its position,
    later objects drawn over earlier ones."""
    lit = set()
    for x, y, kind, frame in objects(s):
        sp = SPRITES[sprite_id(kind, frame)]
        for dx, dy in sp.mask:
            lit.discard((x + dx, y + dy))
        for dx, dy in sp.lit:
            lit.add((x + dx, y + dy))
    return {(x, y) for x, y in lit if 0 <= x < 280 and 0 <= y < 192}


@pytest.fixture
def s(built):
    return start(FX)


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    s = check_in_bounds(FX)
    check_bit7(s)


def test_counts(s):
    objs = objects(s)
    toast = sum(1 for o in objs if o[2])
    assert toast == 3
    assert len(objs) - toast == 4      # cut from 7 to fit the IIc's speed


def test_motion(s):
    for _ in range(40):
        before = objects(s)
        s.step()
        after = objects(s)
        for (x0, y0, k, _), (x1, y1, _, _) in zip(before, after):
            moved = x1 < x0 and y1 >= y0
            respawned = x1 >= 280 or y1 <= -40
            assert moved or respawned, ((x0, y0), (x1, y1))


def test_flip(s):
    for _ in range(12):
        d0 = s.peek(DISP)
        s.step()
        assert s.peek(DISP) != d0
        shown = PAGE2 if s.peek(DISP) else PAGE1
        assert s.page_pixels(shown) == frame_pixels(s)


def test_end_state(s):
    run(s, 7)
    final = frame_pixels(s)
    s.call("normalize_display")
    assert s.peek(DISP) == 0
    assert s.page_pixels(PAGE1) == final


def test_near_wrap(s):
    # Push every object to the edge so they all respawn within a few steps.
    for i in range(s.peek(s.addr("tst_count"))):
        s.poke(s.addr("tst_xl") + i, (-40) & 0xFF)
        s.poke(s.addr("tst_xh") + i, 0xFF)
        s.poke(s.addr("tst_frame") + i, 0xFE)
    s.start_tracking()
    run(s, 50)
    from fxcommon import ALLOWED
    assert s.writes_outside(*ALLOWED) == []
    assert all(-60 <= x <= 330 and -70 <= y <= 200 for x, y, _, _ in objects(s))
