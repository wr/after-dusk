import math

import pytest

from fxcommon import ALLOWED, OVERHEAD, TICK, check_bit7, check_budget, check_in_bounds, run, start
from sim import PAGE1, row_base

FX = 9
W, H = 280, 192
PTS = 41                        # points in a doodle, joined by 40 segments
PER = 20                        # steps a doodle takes: 2 segments a step
HOLD = 75                       # steps a full grid stays up
DRAW, HOLDING, CLEARING = 0, 1, 2
TICKS = 2


def v(s, name, i=0):
    return s.peek(s.addr(name) + i)


def grid(s):
    return v(s, "dd_cols"), v(s, "dd_rows")


def cell_box(cols, rows, n):
    """The cell's edges and the doodle's centre and reach (0.34 of the cell's
    width, 0.38 of its height)."""
    cw, ch = W / cols, H / rows
    c, r = n % cols, n // cols
    return c * cw, r * ch, cw, ch, (c + 0.5) * cw, (r + 0.5) * ch, 0.34 * cw, 0.38 * ch


def inside(pixels, cols, rows, n):
    x0, y0, cw, ch = cell_box(cols, rows, n)[:4]
    return all(x0 <= x < x0 + cw and y0 <= y < y0 + ch for x, y in pixels)


def components(pixels):
    """How many 8-connected pieces the dots make."""
    left = set(pixels)
    n = 0
    while left:
        n += 1
        todo = [left.pop()]
        while todo:
            x, y = todo.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    p = (x + dx, y + dy)
                    if p in left:
                        left.remove(p)
                        todo.append(p)
    return n


def recording(points):
    """A start() prepare hook: every point the effect works out goes into
    `points` (the effect writes the new x, then the new y)."""
    def prepare(s):
        nx, ny = s.addr("dd_nx"), s.addr("dd_ny")
        s.mem.write_hooks[ny] = lambda y: points.append((s.peek16(nx), y))
    return prepare


def params(s):
    f = [v(s, "dd_f", j) for j in range(4)]
    q = [s.peek16(s.addr("dd_q") + 2 * j) for j in range(4)]
    return f, q, s.peek16(s.addr("dd_dt"))


def expected_points(s, n):
    """The sample's doodle for cell n, from the parameters the effect picked:
    t = end * i / 40, x = cx + ax (0.63 sin(f0 t + q0) + 0.37 sin(f1 t + q1)),
    y likewise with f2, f3, q2, q3. Angles in 1/65536 of a turn."""
    cols, rows = grid(s)
    cx, cy, ax, ay = cell_box(cols, rows, n)[4:]
    f, q, dt = params(s)
    out = []
    for i in range(PTS):
        a = [2 * math.pi * (f[j] * i * dt + q[j]) / 65536 for j in range(4)]
        out.append((cx + ax * (0.63 * math.sin(a[0]) + 0.37 * math.sin(a[1])),
                    cy + ay * (0.63 * math.sin(a[2]) + 0.37 * math.sin(a[3]))))
    return out


def to_last_cell(s):
    """Make the doodle being drawn the grid's last one."""
    cols, rows = grid(s)
    s.poke(s.addr("dd_cell"), cols * rows - 1)
    s.poke(s.addr("dd_col"), cols - 1)
    s.poke(s.addr("dd_row"), rows - 1)


def row_bytes(s, y):
    a = row_base(y, PAGE1)
    return bytes(s.mem.ram[a:a + 40])


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_stays_in_bounds_through_a_new_grid(built):
    s = start(FX)
    to_last_cell(s)
    s.start_tracking()
    run(s, PER + HOLD + 40)
    assert s.writes_outside(*ALLOWED) == []
    check_bit7(s)


def test_cells_fill_in_order_one_doodle_every_20_steps(built):
    s = start(FX, seed=0x1357)
    cols, rows = grid(s)
    before = set()
    for n in range(cols * rows):
        for _ in range(PER):
            assert v(s, "dd_cell") == n
            s.step()
        lit = s.page_pixels()
        assert lit >= before                           # nothing drawn is taken away
        new = lit - before
        assert new, f"cell {n} got no doodle"
        assert inside(new, cols, rows, n), f"cell {n}'s doodle leaves its cell"
        before = lit
    assert v(s, "dd_cell") == cols * rows
    assert v(s, "dd_mode") == HOLDING


def test_every_dot_of_a_doodle_stays_inside_its_cell(built):
    for seed in (0x4D2A, 0xBEEF, 0x2468):
        s = start(FX, seed=seed)
        cols, rows = grid(s)
        before = set()
        for n in range(min(cols * rows, 10)):
            cx, cy, ax, ay = cell_box(cols, rows, n)[4:]
            run(s, PER)
            lit = s.page_pixels()
            new = lit - before
            assert inside(new, cols, rows, n)
            assert all(abs(x - cx) <= ax + 1.5 and abs(y - cy) <= ay + 1.5 for x, y in new)
            before = lit


def test_a_doodle_is_one_connected_stroke(built):
    points = []
    s = start(FX, seed=0x4D2A, prepare=recording(points))
    before = set()
    for n in range(6):
        assert len(points) == n * PTS + 1              # point 0, worked out when the doodle starts
        run(s, PER)
        assert len(points) == (n + 1) * PTS + 1        # 40 more, two lines a step
        lit = s.page_pixels()
        new = lit - before
        assert components(new) == 1
        stroke = points[n * PTS:(n + 1) * PTS]
        assert all(p in new for p in stroke)           # every point is on the stroke
        before = lit


def test_doodles_follow_the_samples_two_wobbles(built):
    for seed in (0x4D2A, 0x1357):
        points = []
        s = start(FX, seed=seed, prepare=recording(points))
        for n in range(4):
            want = expected_points(s, n)
            run(s, PER)
            got = points[n * PTS:(n + 1) * PTS]
            err = max(math.hypot(gx - wx, gy - wy) for (gx, gy), (wx, wy) in zip(got, want))
            assert err <= 2.0, f"doodle {n} is {err:.2f} dots off the sample's curve"


def test_doodle_shapes_vary_like_the_sample(built):
    fs, ends = [set(), set(), set(), set()], []
    s = start(FX, seed=0x2468)
    for _ in range(40):
        f, q, dt = params(s)
        for j in range(4):
            fs[j].add(f[j])
        ends.append((PTS - 1) * dt / 65536)
        for name in ("dd_cell", "dd_col", "dd_row"):   # keep the grid from filling up
            s.poke(s.addr(name), 0)
        run(s, PER)
    assert fs[0] == fs[2] == {1, 2, 3}                 # slow wobbles: 1-3 times round
    assert fs[1] == fs[3] == {2, 3, 4, 5}              # faster ones: 2-5
    assert all(0.75 <= e < 1.0 for e in ends)          # the pen goes 0.75 to 1 of the way round
    assert min(ends) < 0.8 and max(ends) > 0.95


def test_grid_size_is_in_range_and_changes(built):
    sizes = []
    for seed in (0x1111, 0x2222, 0x3333):
        s = start(FX, seed=seed)
        for _ in range(3):
            sizes.append(grid(s))
            to_last_cell(s)
            run(s, PER + HOLD + 1)
            for _ in range(40):
                if v(s, "dd_mode") == DRAW:
                    break
                s.step()
    print("grid sizes", sizes)
    assert all(4 <= c <= 8 and 3 <= r <= 6 for c, r in sizes)
    assert len({c for c, r in sizes}) >= 3 and len({r for c, r in sizes}) >= 3
    assert any(a != b for a, b in zip(sizes, sizes[1:]))


def test_full_grid_holds_then_clears_and_a_new_grid_starts(built):
    s = start(FX, seed=0x4D2A)
    to_last_cell(s)
    run(s, PER)
    assert any(s.page_bytes(PAGE1))
    s.fill_page(PAGE1, 0x55)                           # so any change shows, on every row
    picture = [row_bytes(s, y) for y in range(H)]
    for _ in range(HOLD):                              # 2.5 seconds with nothing moving
        s.step()
        assert [row_bytes(s, y) for y in range(H)] == picture
    steps, top = 0, 0
    while v(s, "dd_mode") != DRAW:                     # then cleared from the top down
        s.step()
        steps += 1
        assert steps <= 24
        now = [row_bytes(s, y) for y in range(H)]
        split = next(y for y in range(H + 1) if all(now[k] == picture[k] for k in range(y, H)))
        assert not any(any(now[k]) for k in range(split)), "only whole rows go, top down"
        assert top < split <= top + 32                 # a few rows every step
        top = split
    assert split == H and 6 <= steps <= 24             # not all at once
    assert v(s, "dd_cell") == 0
    cols, rows = grid(s)
    run(s, PER)
    lit = s.page_pixels()
    assert lit and inside(lit, cols, rows, 0)          # the new grid's first doodle, top left


def test_a_new_grid_never_runs_long(built):
    """The hold, the clearing and the new grid's start each fit the step's ticks."""
    for seed in (0x4D2A, 0x1357, 0xBEEF):
        s = start(FX, seed=seed)
        to_last_cell(s)
        worst = max(s.step() for _ in range(PER + HOLD + 40))
        print("worst step through a new grid", worst)
        assert worst < TICKS * TICK - OVERHEAD
