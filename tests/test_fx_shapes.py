from collections import Counter

import pytest

from fxcommon import OVERHEAD, TICK, check_bit7, check_budget, check_in_bounds, start
from sim import PAGE1, row_base
from test_hires import grey, scribble

FX = 10
TICKS = 3
RECT, OVAL, TRI = 0, 1, 2
OPAQUE, SEE_THROUGH = 0, 1
WPAD, HWMAX = 161, 13851        # sizes with h (w + WPAD) > HWMAX would not fit 3 ticks


def fits(w, h):
    return h * (w + WPAD) <= HWMAX


def v(s, name):
    return s.peek(s.addr(name))


def w16(s, name):
    n = s.peek16(s.addr(name))
    return n - 0x10000 if n & 0x8000 else n


def shape(s):
    """The shape the effect last picked."""
    p = dict(kind=v(s, "sh_kind"), x0=w16(s, "sh_x0"), y0=w16(s, "sh_y0"), w=v(s, "sh_w"),
             h=v(s, "sh_h"), mode=v(s, "sh_mode"), level=v(s, "sh_lev"))
    if p["kind"] == TRI:
        p["tri"] = [(w16(s, "sh_ax"), p["y0"]), (w16(s, "sh_bx"), w16(s, "sh_by")),
                    (w16(s, "sh_cx"), p["y0"] + p["h"])]
    return p


def put_shape(s, kind, x0, y0, w, h, mode, level, tri=None):
    for name, n in (("sh_kind", kind), ("sh_w", w), ("sh_h", h), ("sh_mode", mode), ("sh_lev", level)):
        s.poke(s.addr(name), n)
    s.poke16(s.addr("sh_x0"), x0)
    s.poke16(s.addr("sh_y0"), y0)
    if tri:
        s.poke16(s.addr("sh_ax"), tri[0][0])
        s.poke16(s.addr("sh_bx"), tri[1][0])
        s.poke16(s.addr("sh_by"), tri[1][1])
        s.poke16(s.addr("sh_cx"), tri[2][0])


def in_tri(x2, y2, tri):
    """The sample's inTri, on doubled coordinates (so the dot's centre is a whole number)."""
    p = [(2 * x, 2 * y) for x, y in tri]

    def side(a, b, c):
        return (a[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (a[1] - c[1])
    q = (x2, y2)
    d = side(q, p[0], p[1]), side(q, p[1], p[2]), side(q, p[2], p[0])
    return not (any(n < 0 for n in d) and any(n > 0 for n in d))


def region(p):
    """The sample's dots for a shape: every dot of its box, on screen, that is inside it."""
    x0, y0, w, h = p["x0"], p["y0"], p["w"], p["h"]
    out = set()
    for y in range(max(0, y0), min(192, y0 + h)):
        for x in range(max(0, x0), min(280, x0 + w)):
            if p["kind"] == RECT:
                inside = True
            elif p["kind"] == OVAL:                    # ((x - cx) / (w/2))^2 + ((y - cy) / (h/2))^2 <= 1
                inside = (2 * (x - x0) - w) ** 2 * h * h + (2 * (y - y0) - h) ** 2 * w * w <= w * w * h * h
            else:
                inside = in_tri(2 * x + 1, 2 * y + 1, p["tri"])
            if inside:
                out.add((x, y))
    return out


def anti_pattern(s, level):
    for y in range(192):
        base = row_base(y, PAGE1)
        for b in range(40):
            s.poke(base + b, sum(1 << i for i in range(7) if not grey(b * 7 + i, y, level)))


def check_drawn(s, p, seed=1):
    """Draw the shape now in the effect's state and check every dot against the sample:
    opaque shapes put down their grey on every dot they cover and touch nothing else;
    see-through ones only add their lit dots."""
    want = region(p)
    if p["mode"] == OPAQUE:
        anti_pattern(s, p["level"])
        before = s.page_pixels()
        s.call("sh_draw", max_cycles=1_000_000)
        assert before ^ s.page_pixels() == want
    else:
        scribble(s, seed)
        before = s.page_pixels()
        s.call("sh_draw", max_cycles=1_000_000)
        assert s.page_pixels() == before | {q for q in want if grey(*q, p["level"])}
    assert all(b & 0x80 == 0 for b in s.page_bytes(PAGE1))


def test_budget(built):
    worst, median = check_budget(FX, steps=100)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX, steps=100))


def test_each_shape_is_the_samples_shape_in_its_grey(built):
    kinds = Counter()
    for seed in (0x4D2A, 0x1357, 0xBEEF):
        s = start(FX, seed=seed)
        for n in range(25):
            s.call("sh_pick")
            p = shape(s)
            kinds[p["kind"], p["mode"]] += 1
            check_drawn(s, p, seed + n)
    assert len(kinds) == 6                             # every kind, both ways


TRIS = [  # A on the top edge, B on a side between half and all of the way down, C bottom corner
    (RECT, -35, -35, 140, 96, None), (RECT, 270, 180, 10, 8, None), (RECT, 0, 0, 280 - 140, 96, None),
    (OVAL, -35, -35, 140, 96, None), (OVAL, 100, 50, 10, 8, None), (OVAL, 3, 4, 11, 9, None),
    (OVAL, 200, 150, 139, 95, None), (OVAL, 50, 60, 140, 8, None), (OVAL, 50, 60, 10, 96, None),
    (TRI, 20, 10, 100, 80, [(70, 10), (120, 50), (20, 90)]),
    (TRI, 20, 10, 100, 80, [(70, 10), (20, 89), (120, 90)]),             # B and C mirrored
    (TRI, 20, 10, 100, 80, [(20, 10), (20, 60), (20, 90)]),              # all down one side: nothing
    (TRI, -35, -35, 140, 96, [(104, -35), (-35, 13), (105, 61)]),
    (TRI, 250, 150, 140, 96, [(250, 150), (390, 240), (250, 246)]),
    (TRI, 100, 100, 10, 8, [(109, 100), (110, 104), (100, 108)]),
    (TRI, 100, 100, 137, 9, [(101, 100), (237, 108), (237, 109)]),
]


@pytest.mark.parametrize("kind,x0,y0,w,h,tri", TRIS)
@pytest.mark.parametrize("mode", [OPAQUE, SEE_THROUGH])
def test_edge_case_shapes_match_the_sample(built, kind, x0, y0, w, h, tri, mode):
    s = start(FX)
    put_shape(s, kind, x0, y0, w, h, mode, 9, tri)
    p = shape(s)
    check_drawn(s, p)


def test_shapes_vary_like_the_sample(built):
    s = start(FX, seed=0x2468)
    ps = []
    for _ in range(1500):
        s.call("sh_pick")
        ps.append(shape(s))
    kinds = Counter(p["kind"] for p in ps)
    assert set(kinds) == {RECT, OVAL, TRI} and min(kinds.values()) > 400
    assert all(10 <= p["w"] <= 140 and 8 <= p["h"] <= 96 and fits(p["w"], p["h"]) for p in ps)
    assert min(p["w"] for p in ps) == 10 and max(p["w"] for p in ps) == 140
    assert min(p["h"] for p in ps) == 8 and max(p["h"] for p in ps) >= 78     # at most 81
    assert max(p["h"] for p in ps if p["w"] >= 130) >= 44                     # 140 wide: at most 46
    assert min(p["x0"] for p in ps) == -35 and max(p["x0"] for p in ps) == 279
    assert min(p["y0"] for p in ps) == -35 and max(p["y0"] for p in ps) == 191
    modes = Counter(p["mode"] for p in ps)
    assert set(modes) == {OPAQUE, SEE_THROUGH} and min(modes.values()) > 650
    assert {p["level"] for p in ps if p["mode"] == OPAQUE} == set(range(17))
    assert {p["level"] for p in ps if p["mode"] == SEE_THROUGH} == set(range(2, 17))


def test_triangle_corners_are_placed_and_mirrored_like_the_sample(built):
    s = start(FX, seed=0x5A5A)
    flips = Counter()
    n = 0
    while n < 400:
        s.call("sh_pick")
        p = shape(s)
        if p["kind"] != TRI:
            continue
        n += 1
        (ax, ay), (bx, by), (cx, cy) = p["tri"]
        x0, y0, w, h = p["x0"], p["y0"], p["w"], p["h"]
        assert ay == y0 and x0 <= ax <= x0 + w                         # on the top edge
        assert bx in (x0, x0 + w) and y0 + h / 2 <= by < y0 + h        # on a side, lower half
        assert cx in (x0, x0 + w) and cy == y0 + h                     # a bottom corner
        flips["b", bx == x0] += 1
        flips["c", cx == x0 + w] += 1
    assert all(flips["b", f] > 120 and flips["c", f] > 120 for f in (False, True))


def test_see_through_shapes_never_clear_a_dot(built):
    s = start(FX, seed=0x7777)
    seen = 0
    for _ in range(40):
        before = s.page_pixels()
        s.step()
        if v(s, "sh_mode") == SEE_THROUGH:
            seen += 1
            assert before <= s.page_pixels()
    assert seen > 10


def test_shapes_pile_up(built):
    """Each shape changes only dots inside its own box, so the picture builds up."""
    s = start(FX, seed=0x3141)
    for _ in range(20):
        before = s.page_pixels()
        s.step()
        p = shape(s)
        changed = before ^ s.page_pixels()
        assert all(p["x0"] <= x < p["x0"] + p["w"] and p["y0"] <= y < p["y0"] + p["h"] for x, y in changed)
    assert len(s.page_pixels()) > 3000


@pytest.mark.parametrize("w", [10, 40, 70, 100, 115, 140])
def test_biggest_shapes_fit_their_ticks(built, w):
    """The tallest shape allowed at each width, every kind and way, wholly on screen."""
    s = start(FX)
    h = HWMAX // (w + WPAD)
    x0, y0 = 70, 10
    worst = 0
    for mode in (OPAQUE, SEE_THROUGH):
        shapes = [(RECT, None), (OVAL, None)]
        for a in (0, w - 1):
            for bx in (x0, x0 + w):
                for cx in (x0, x0 + w):
                    shapes.append((TRI, [(x0 + a, y0), (bx, y0 + (h + 1) // 2), (cx, y0 + h)]))
        for kind, tri in shapes:
            put_shape(s, kind, x0, y0, w, h, mode, 9, tri)
            worst = max(worst, s.call("sh_draw", max_cycles=1_000_000))
    print("width", w, "height", h, "worst", worst)
    assert worst < TICKS * TICK - OVERHEAD
