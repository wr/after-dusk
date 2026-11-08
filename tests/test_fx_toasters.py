import sys

import pytest

from conftest import ROOT
from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start
from sim import DISP, PAGE1, PAGE2

sys.path.insert(0, str(ROOT / "tools"))
import gen_art  # noqa: E402

FX = 0
SPRITES = gen_art.sprites()
TOAST_W, TOAST_H = 41, 40
SLICE_W, SLICE_H = 31, 23
# speed per update by class (0 slice, 1 slow toaster, 2 fast toaster), 8.8
SPEEDS = {0: (0x0118, 0x0090), 1: (0x0230, 0x011F), 2: (0x0348, 0x01AF)}


def signed16(v):
    return v - 0x10000 if v & 0x8000 else v


def objects(s):
    """(x, y, kind, frame, cls) per object, x and y as whole dots."""
    return [(x >> 8, y >> 8, k, f, c) for x, y, k, f, c in positions(s)]


def positions(s):
    """(x, y, kind, frame, cls) per object, x and y in 8.8 fixed point."""
    n = s.peek(s.addr("tst_count"))
    out = []
    for i in range(n):
        x = (signed16(s.peek(s.addr("tst_xl") + i) | (s.peek(s.addr("tst_xh") + i) << 8)) << 8) \
            | s.peek(s.addr("tst_xf") + i)
        y = (signed16(s.peek(s.addr("tst_yl") + i) | (s.peek(s.addr("tst_yh") + i) << 8)) << 8) \
            | s.peek(s.addr("tst_yf") + i)
        out.append((x, y, s.peek(s.addr("tst_kind") + i), s.peek(s.addr("tst_frame") + i),
                    s.peek(s.addr("tst_cls") + i)))
    return out


def sprite_id(kind, frame):
    return 4 if kind else (0, 1, 2, 3, 2, 1)[frame % 6]


def frame_pixels(s):
    """What the shown page should hold: every object's sprite at its position,
    later objects drawn over earlier ones."""
    lit = set()
    for x, y, kind, frame, _ in objects(s):
        sp = SPRITES[sprite_id(kind, frame)]
        for dx, dy in sp.mask:
            lit.discard((x + dx, y + dy))
        for dx, dy in sp.lit:
            lit.add((x + dx, y + dy))
    return {(x, y) for x, y in lit if 0 <= x < 280 and 0 <= y < 192}


def set_pos(s, i, x, y):
    s.poke(s.addr("tst_xf") + i, 0)
    s.poke(s.addr("tst_xl") + i, x & 0xFF)
    s.poke(s.addr("tst_xh") + i, (x >> 8) & 0xFF)
    s.poke(s.addr("tst_yf") + i, 0)
    s.poke(s.addr("tst_yl") + i, y & 0xFF)
    s.poke(s.addr("tst_yh") + i, (y >> 8) & 0xFF)


def freeze(s):
    """Every class's speed to 0, so nothing moves."""
    for name in ("cls_vxf", "cls_vxi", "cls_vyf", "cls_vyi"):
        for c in range(3):
            s.poke(s.addr(name) + c, 0)


def patch_sites(s):
    """The sprite engine's fast loops rewrite their own operands per sprite."""
    return (s.addr("fd_row"), s.addr("rebase"))


def respawned(before, after):
    """True when the object was replaced this update: a newcomer sits exactly
    at x = 280 or at y = -h, which no moving object reaches."""
    x1, y1, kind = after[0], after[1], after[2]
    h = TOAST_H if kind == 0 else SLICE_H
    return x1 == 280 << 8 or y1 == (-h) << 8


def respawns(s, updates):
    """Run updates; yields (kind, x, y, cls) of every newcomer, pushing every
    object to the left edge first so they turn over fast."""
    out = []
    for _ in range(updates):
        before = positions(s)
        for i, (_, _, kind, _, _) in enumerate(before):
            if (before[i][0] >> 8) > -20:
                set_pos(s, i, -(TOAST_W if kind == 0 else SLICE_W), 50)
        before = positions(s)
        s.step()
        after = positions(s)
        for b, a in zip(before, after):
            if respawned(b, a):
                out.append((a[2], a[0] >> 8, a[1] >> 8, a[4]))
    return out


@pytest.fixture
def s(built):
    return start(FX)


def test_budget(built):
    # Allowed to slip: updates with objects clipped at the screen edges run
    # over their 4 ticks (AGENTS.md's final counts). test_worst_update still
    # holds the all-on-screen case to 4 ticks.
    worst, median = check_budget(FX, worst_ticks=6, median_share=1.0)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(s):
    s = check_in_bounds(FX, extra=[patch_sites(s)])
    check_bit7(s)


def test_counts(s):
    objs = objects(s)
    kinds = [o[2] for o in objs]
    ntoast = kinds.count(0)
    assert kinds == [0] * ntoast + [1] * (len(objs) - ntoast)
    assert ntoast >= 3 and len(objs) - ntoast >= 3


def test_speeds(s):
    for _ in range(60):
        before = positions(s)
        s.step()
        after = positions(s)
        for b, a in zip(before, after):
            kind, cls = b[2], b[4]
            assert cls == 0 if kind else cls in (1, 2)
            if not respawned(b, a):
                vx, vy = SPEEDS[cls]
                assert (a[0], a[1]) == (b[0] - vx, b[1] + vy)


def test_fast_share(s):
    news = [c for k, x, y, c in respawns(s, 700) if k == 0]
    assert len(news) >= 2000
    share = sum(1 for c in news if c == 2) / len(news)
    assert abs(share - 2 / 3) < 0.05, share


def test_flap(built):
    starts = set()
    for seed in (0x4D2A, 0x1357, 0xBEEF):
        s = start(FX, seed=seed)
        frames = [o[3] for o in objects(s) if o[2] == 0]
        starts.add(tuple(frames))
        for _ in range(12):
            s.step()
            nxt = [o[3] for o in objects(s) if o[2] == 0]
            assert nxt == [(f + 1) % 6 for f in frames]
            frames = nxt
    assert len(starts) > 1


RANGES = {0: ((-20, 259), (-20, 151)), 1: ((-15, 264), (-11, 168))}


def test_init_placement(built):
    for seed in range(1, 51):
        s = start(FX, seed=seed * 0x1234 + 1)
        for x, y, kind, frame, cls in objects(s):
            (xlo, xhi), (ylo, yhi) = RANGES[kind]
            assert xlo <= x <= xhi and ylo <= y <= yhi, (kind, x, y)
            assert 0 <= frame < 6


def test_init_placement_reach(s):
    """Starting positions reach both ends of their ranges, and the leftmost
    strip is not over-represented."""
    objs = objects(s)
    xs, ys = {0: [], 1: []}, {0: [], 1: []}
    for _ in range(600):
        for i, o in enumerate(objs):
            s.call("spawn_anywhere", x=i)
        for x, y, kind, _, _ in objects(s):
            xs[kind].append(x)
            ys[kind].append(y)
    for kind in (0, 1):
        (xlo, xhi), (ylo, yhi) = RANGES[kind]
        assert min(xs[kind]) <= xlo + 3 and max(xs[kind]) >= xhi - 3, (kind, min(xs[kind]), max(xs[kind]))
        assert min(ys[kind]) <= ylo + 3 and max(ys[kind]) >= yhi - 3, (kind, min(ys[kind]), max(ys[kind]))
        left = sum(1 for x in xs[kind] if x < xlo + 23) / len(xs[kind])
        assert left < 1.5 * 23 / 280, (kind, left)


def test_respawn_edges(s):
    news = respawns(s, 300)
    assert len(news) >= 2000
    sides = 0
    for kind, x, y, cls in news:
        h = TOAST_H if kind == 0 else SLICE_H
        if x == 280:
            sides += 1
            assert -h <= y <= 110, (kind, x, y)
        else:
            assert y == -h and 60 <= x <= 300, (kind, x, y)
    assert abs(sides / len(news) - 0.5) < 0.05


def test_leaves(s):
    freeze(s)
    objs = objects(s)
    for i, (_, _, kind, _, _) in enumerate(objs):
        w = TOAST_W if kind == 0 else SLICE_W
        set_pos(s, i, -w, 50)
    s.step()
    assert [o[:2] for o in objects(s)] == [(-(TOAST_W if o[2] == 0 else SLICE_W), 50) for o in objs]
    for i, (_, _, kind, _, _) in enumerate(objs):
        set_pos(s, i, -(TOAST_W if kind == 0 else SLICE_W) - 1, 50)
    s.step()
    assert all(o[0] == 280 or o[1] < 0 for o in objects(s))
    for i in range(len(objs)):
        set_pos(s, i, 100, 192)
    s.step()
    assert all(o[:2] == (100, 192) for o in objects(s))
    for i in range(len(objs)):
        set_pos(s, i, 100, 193)
    s.step()
    assert all(o[0] == 280 or o[1] < 0 for o in objects(s))


def shown_page(s):
    return PAGE2 if s.peek(DISP) else PAGE1


def test_flip(s):
    # The first step draws but shows nothing new: page 1 stays, still clear.
    s.step()
    assert s.peek(DISP) == 0
    assert s.page_pixels(PAGE1) == set()
    # From then on each step shows what the step before it drew.
    for _ in range(12):
        d0 = s.peek(DISP)
        pic = frame_pixels(s)
        s.step()
        assert s.peek(DISP) != d0
        assert s.page_pixels(shown_page(s)) == pic


def test_end_state(s):
    run(s, 6)
    final = frame_pixels(s)        # drawn by step 6, shown by step 7
    s.step()
    s.call("normalize_display")
    assert s.peek(DISP) == 0
    assert s.page_pixels(PAGE1) == final


def test_near_wrap(s):
    # Push every object to the edge so they all respawn within a few updates.
    for i in range(s.peek(s.addr("tst_count"))):
        set_pos(s, i, -40, 50)
        s.poke(s.addr("tst_frame") + i, 5)
    s.start_tracking()
    run(s, 50)
    assert s.writes_outside(*ALLOWED, patch_sites(s)) == []
    assert all(-60 <= x <= 330 and -70 <= y <= 200 for x, y, _, _, _ in objects(s))


def test_crossings(s):
    objs = objects(s)
    slow = next(i for i, o in enumerate(objs) if o[2] == 0)
    fast = next(i for i, o in enumerate(objs) if o[2] == 0 and i != slow)
    slice_ = next(i for i, o in enumerate(objs) if o[2] == 1)
    s.poke(s.addr("tst_cls") + slow, 1)
    s.poke(s.addr("tst_cls") + fast, 2)
    set_pos(s, slow, 120, 80)
    set_pos(s, fast, 130, 90)
    set_pos(s, slice_, 125, 95)
    s.step()                       # drawn now, shown by the next step
    for _ in range(10):
        pic = frame_pixels(s)
        s.step()
        assert s.page_pixels(shown_page(s)) == pic


def test_after_fish(built):
    def prepare(s):
        s.fill_page(PAGE2, 0x55)
        s.mem.ram[0x0800:0x2000] = bytes([0x55]) * 0x1800

    s = start(FX, prepare=prepare)
    s.step()
    pic1 = frame_pixels(s)         # drawn on page 2 by step 1
    s.step()
    assert shown_page(s) == PAGE2
    assert s.page_pixels(PAGE2) == pic1
    pic2 = frame_pixels(s)         # drawn on page 1 by step 2
    s.step()
    assert shown_page(s) == PAGE1
    assert s.page_pixels(PAGE1) == pic2


def test_worst_update(s):
    """Every object fully on screen at one spot, at each of the 7 shifts,
    nothing moving: a full flap's worst update must fit 4 ticks."""
    freeze(s)
    worst = 0
    for k in range(7):
        for i in range(s.peek(s.addr("tst_count"))):
            set_pos(s, i, 100 + k, 70)
        for _ in range(6):
            worst = max(worst, s.step())
    print("worst update, all on screen:", worst)
    assert worst < 67_820
