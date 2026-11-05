"""Rose, after the original After Dark module's method. Each original frame has 16 dots,
k = 1..16, u = 22.5k degrees:
    x = 140 + floor(1.1 C (B sin(A u) + sin(t + u))),  y = 96 + floor(C (B cos(A u) + cos(t + u)))
and t turns 1.5 degrees a frame; sin(A u) comes from a 128-step table, index floor(8 k A) & 127.
A, B and C glide from table values to new random table values over 250 frames. A step is two
frames (30 steps a second are the original's 60 frames): t and the glide go on two frames, and
only the second frame's dots are drawn. The last 368 dots (23 steps) stay. Dots whose 2 x 2
block would fall off the top or bottom are skipped."""
import math
from fractions import Fraction

import pytest

from fxcommon import ALLOWED, TICK, OVERHEAD, check_bit7, check_budget, check_in_bounds, run, start

FX = 8
PER_STEP = 16                   # dots drawn each step
SLOTS = 23                      # steps kept
KEEP = PER_STEP * SLOTS         # 368 dots kept
SLOT_BYTES = 64                 # a step's dots in the ring: 16 x (x low, x high, y), padded
SKIPPED = 0x80                  # x high for a dot that was off the screen, so not drawn
GLIDE = 250                     # frames from one value to the next
FRAMES = 2                      # frames a step
XA = 1.1
A_TAB = (0, 1, 4, 9, 16)
B_TAB = ([(-128 + 16 * (i >> 1) + 4 * (i & 1)) / 100 for i in range(32)]
         + [(-120 + 16 * (i >> 1) + 4 * (i & 1)) / 100 for i in range(32)])
C_TAB = [54 * math.sqrt(i) * 10 / 57 for i in range(32)]
B_ONE = 8192                    # the program's B: 8192 = 1
C_ONE = 256 * 256 / 255         # its C: 8.8, with the sines' 256/255 folded in
GA, GB, GC, GX = range(4)       # its gliding values: 8 A, B, C, 1.1 C
BIG = [(a, b) for a in range(len(A_TAB)) for b in (0, len(B_TAB) - 1)]  # with C at its biggest


@pytest.fixture
def s(built):
    return start(FX)


def state(s):
    p = s.peek
    frm, to = s.addr("rose_from"), s.addr("rose_to")
    return {"from": tuple(p(frm + i) for i in range(3)), "to": tuple(p(to + i) for i in range(3)),
            "n": p(s.addr("rose_n")), "t": p(s.addr("rose_t"))}


def cur(s, g):
    v = s.peek(s.addr("rose_curl") + g) | (s.peek(s.addr("rose_curh") + g) << 8)
    return v - 0x10000 if v & 0x8000 else v


def rem(s, g):
    return s.peek(s.addr("rose_rem") + g)


def eight_a(s):
    """8 A as the program holds it: a whole number plus 250ths, exactly."""
    return cur(s, GA) + Fraction(rem(s, GA), GLIDE)


def glide(frm, to, n):
    """A (exact), B and C as the original has them n frames into the glide."""
    (a0, b0, c0), (a1, b1, c1) = frm, to
    A = A_TAB[a0] + (A_TAB[a1] - A_TAB[a0]) * Fraction(n, GLIDE)
    B = B_TAB[b0] + (B_TAB[b1] - B_TAB[b0]) * n / GLIDE
    C = C_TAB[c0] + (C_TAB[c1] - C_TAB[c0]) * n / GLIDE
    return A, B, C


def expected(st):
    """The original's 16 dots for the step that starts at state st: those of its second frame,
    one frame on in t and in the glide."""
    A, B, C = glide(st["from"], st["to"], st["n"] + 1)
    t = st["t"] + 1
    out = []
    for k in range(1, PER_STEP + 1):
        ang = (math.floor(8 * k * A) & 127) * 2 * math.pi / 128
        tu = (t + 15 * k) % 240 * math.pi / 120
        out.append((140 + math.floor(C * (B * math.sin(ang) + math.sin(tu)) * XA),
                    96 + math.floor(C * (B * math.cos(ang) + math.cos(tu)))))
    return out


def slot_dots(s, slot):
    """A step's dots: (x, y, drawn)."""
    base = s.addr("rose_ring") + SLOT_BYTES * slot
    out = []
    for i in range(PER_STEP):
        xl, xh, y = (s.peek(base + 3 * i + j) for j in range(3))
        out.append((xl + 256 * (xh & 1), y, xh & SKIPPED == 0))
    return out


def newest(s):
    return slot_dots(s, (s.peek(s.addr("rose_slot")) - 1) % SLOTS)


def kept(s):
    """Every kept dot, newest first."""
    slot, full = s.peek(s.addr("rose_slot")), s.peek(s.addr("rose_full"))
    return [d for i in range(full) for d in slot_dots(s, (slot - 1 - i) % SLOTS)]


def drawn(dots):
    return [(x, y) for x, y, on in dots if on]


def block(x, y):
    return {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)}


def blocks(dots):
    return set().union(set(), *(block(x, y) for x, y in dots))


def check_dots(got, want, st):
    """Each dot within one dot of the original's, and skipped only when the original's block
    falls off the top or bottom (or is within a dot of doing so)."""
    for (gx, gy, on), (wx, wy) in zip(got, want):
        if on:
            assert abs(gx - wx) <= 1 and abs(gy - wy) <= 1, (st, (gx, gy), (wx, wy))
            assert 0 <= gy <= 190 and 0 <= gx <= 278, (st, (gx, gy))
        else:
            assert wy <= 0 or wy >= 190, (st, (gx, gy), (wx, wy))


def force(s, a, b, c=len(C_TAB) - 1, step=None):
    """End the glide at A_TAB[a], B_TAB[b], C_TAB[c] (one step), then hold them there: the
    next glide goes from them to them."""
    step = step or s.step
    to = s.addr("rose_to")
    for i, v in enumerate((a, b, c)):
        s.poke(to + i, v)
    s.call("rose_targets")
    s.poke(s.addr("rose_n"), GLIDE - FRAMES)
    step()
    for i, v in enumerate((a, b, c)):
        s.poke(to + i, v)
    for g in range(4):
        for name in ("rose_dwl", "rose_dwh", "rose_dr"):
            s.poke(s.addr(name) + g, 0)
    st = state(s)
    assert st["from"] == st["to"] == (a, b, c) and st["n"] == 0


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_budget_with_the_biggest_figures(built):
    cycles = []
    for seed, (a, b) in zip(range(0x1234, 0x9999, 0x0777), BIG):
        s = start(FX, seed=seed)
        force(s, a, b)
        cycles += [s.step() for _ in range(40)]
    worst, median = max(cycles), sorted(cycles)[len(cycles) // 2]
    print("biggest figures: worst step", worst, "median", median)
    assert worst < 2 * TICK - OVERHEAD
    assert median < 2 * TICK * 0.85


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_stays_in_bounds_with_the_biggest_figures(built):
    """At the biggest sizes the figure reaches past the top and bottom of the screen (those dots
    are skipped) and past x = 255 (still on screen)."""
    skipped = 0
    widest = 0
    for a, b in BIG:
        s = start(FX)
        force(s, a, b)
        s.start_tracking()
        for _ in range(30):
            s.step()
            dots = newest(s)
            skipped += sum(not on for _, _, on in dots)
            for x, y in drawn(dots):
                assert 0 <= x <= 278 and 0 <= y <= 190
                widest = max(widest, x)
        assert s.writes_outside(*ALLOWED) == []
        check_bit7(s)
        assert s.page_pixels() <= blocks(drawn(kept(s)))
    assert skipped > 0
    assert widest >= 256


def test_draws_16_dots_a_step_and_keeps_the_last_368(s):
    s.step()
    assert s.peek(s.addr("rose_full")) == 1
    run(s, SLOTS - 2)
    assert s.peek(s.addr("rose_full")) == SLOTS - 1
    run(s, 1)
    assert len(kept(s)) == KEEP
    run(s, 60)
    assert len(kept(s)) == KEEP
    assert s.peek(s.addr("rose_full")) == SLOTS


def test_dots_follow_the_formula_two_frames_a_step(built):
    """Every dot lands within one dot of the original's second frame, through a whole glide and
    into the next."""
    for seed in (0x4D2A, 0x2468):
        s = start(FX, seed=seed)
        for _ in range(GLIDE // FRAMES + 15):
            st = state(s)
            s.step()
            check_dots(newest(s), expected(st), st)


def test_dots_follow_the_formula_at_the_biggest_sizes_and_off_screen_ones_are_skipped(built):
    skipped = 0
    for a, b in BIG:
        s = start(FX)
        force(s, a, b)
        for _ in range(25):
            st = state(s)
            s.step()
            got = newest(s)
            check_dots(got, expected(st), st)
            skipped += sum(not on for _, _, on in got)
    assert skipped > 0


def test_size_starts_at_0(built):
    for seed in (0x1111, 0x2222, 0x3333):
        s = start(FX, seed=seed)
        assert state(s)["from"][2] == 0
        assert cur(s, GC) == 0 and cur(s, GX) == 0
        s.step()                        # the second frame: one 250th of the way to the new size
        for x, y, on in newest(s):
            assert on and abs(x - 140) <= 1 and abs(y - 96) <= 1


def test_values_glide_from_table_value_to_table_value_over_125_steps(built):
    s = start(FX, seed=0x5A5A)
    st0 = state(s)
    a0, b0, c0 = st0["from"]
    assert st0["n"] == 0
    assert eight_a(s) == 8 * A_TAB[a0]
    assert cur(s, GB) == round(B_TAB[b0] * B_ONE) and rem(s, GB) == 0
    for m in range(1, GLIDE // FRAMES):
        s.step()
        st = state(s)
        assert st["n"] == FRAMES * m and st["from"] == st0["from"] and st["to"] == st0["to"]
        A, B, C = glide(st["from"], st["to"], st["n"])
        assert eight_a(s) == 8 * A                          # exact: the angle index floors on it
        assert abs(cur(s, GB) - B * B_ONE) <= 1.5
        assert abs(cur(s, GC) - C * C_ONE) <= 1.5
        assert abs(cur(s, GX) - XA * C * C_ONE) <= 1.5
    s.step()                                                # the 125th: the targets are reached
    st = state(s)
    a1, b1, c1 = st0["to"]
    assert st["n"] == 0 and st["from"] == st0["to"]
    assert eight_a(s) == 8 * A_TAB[a1]
    assert cur(s, GB) == round(B_TAB[b1] * B_ONE) and rem(s, GB) == 0
    assert abs(cur(s, GC) - C_TAB[c1] * C_ONE) <= 0.5 and rem(s, GC) == 0
    assert abs(cur(s, GX) - XA * C_TAB[c1] * C_ONE) <= 0.5 and rem(s, GX) == 0


def test_new_targets_come_from_the_tables(built):
    s = start(FX, seed=0x0BAD)
    seen = [set(), set(), set()]
    for _ in range(40):
        before = state(s)["to"]
        s.poke(s.addr("rose_n"), GLIDE - FRAMES)
        s.step()
        st = state(s)
        assert st["n"] == 0 and st["from"] == before
        a, b, c = st["to"]
        assert a < len(A_TAB) and b < len(B_TAB) and c < len(C_TAB)
        for i in range(3):
            seen[i].add(st["to"][i])
    assert len(seen[0]) == len(A_TAB) and len(seen[1]) > 20 and len(seen[2]) > 15


def test_turns_3_degrees_a_step(s):
    t0 = state(s)["t"]
    run(s, 10)
    assert state(s)["t"] == (t0 + 2 * 10) % 240
    s.poke(s.addr("rose_t"), 238)
    s.step()
    assert state(s)["t"] == 0


def test_dots_are_2x2_blocks(s):
    """The newest dots are whole, but for what the rubbing out of later dots in the same step
    takes off them (as in the original, where dots overlap)."""
    for _ in range(8):
        run(s, 9)
        slot = s.peek(s.addr("rose_slot"))
        old = slot_dots(s, slot) if s.peek(s.addr("rose_full")) == SLOTS else []
        s.step()
        lit = s.page_pixels()
        for i, (x, y, on) in enumerate(slot_dots(s, slot)):
            if on:
                later = blocks(drawn(old[i + 1:]))
                assert block(x, y) - lit <= later, (i, x, y)


def test_screen_is_each_new_dot_drawn_over_the_one_it_replaces(built):
    """Each new dot first rubs out the one it replaces, then is drawn; a skipped dot is neither
    drawn nor rubbed out later. The screen is exactly that, step after step."""
    for big in (None, (2, 0), (4, len(B_TAB) - 1)):
        s = start(FX, seed=0x6C6C)
        model = set()

        def step():
            full, slot = s.peek(s.addr("rose_full")), s.peek(s.addr("rose_slot"))
            old = slot_dots(s, slot) if full == SLOTS else [(0, 0, False)] * PER_STEP
            s.step()
            for (ox, oy, was), (nx, ny, on) in zip(old, slot_dots(s, slot)):
                if was:
                    model.difference_update(block(ox, oy))
                if on:
                    model.update(block(nx, ny))

        if big:
            force(s, *big, step=step)
        for _ in range(SLOTS * 3):
            step()
            assert s.page_pixels() == model
        assert model


def test_ring_wraps(s):
    s.start_tracking()
    run(s, SLOTS * 2 + 7)
    assert s.writes_outside(*ALLOWED) == []
    assert s.peek(s.addr("rose_slot")) == (SLOTS * 2 + 7) % SLOTS
    assert s.page_pixels() <= blocks(drawn(kept(s)))
