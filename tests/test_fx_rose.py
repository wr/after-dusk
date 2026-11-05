"""Rose, after the original After Dark module's method: each step draws 16 dots,
k = 1..16, u = 22.5k degrees:
    x = 140 + floor(1.1 C (B sin(A u) + sin(t + u))),  y = 96 + floor(C (B cos(A u) + cos(t + u)))
t turns 1.5 degrees a step; sin(A u) comes from a 128-step table, index floor(8 k A) & 127.
A, B and C glide from table values to new random table values over 250 steps. The last 720
dots stay."""
import math
from fractions import Fraction

import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start

FX = 8
PER_STEP = 16                   # dots drawn each step
SLOTS = 45                      # steps kept
KEEP = PER_STEP * SLOTS         # 720 dots kept
GLIDE = 250                     # steps from one value to the next
XA = 1.1
A_TAB = (0, 1, 4, 9, 16)
B_TAB = ([(-128 + 16 * (i >> 1) + 4 * (i & 1)) / 100 for i in range(32)]
         + [(-120 + 16 * (i >> 1) + 4 * (i & 1)) / 100 for i in range(32)])
C_TAB = [42 * math.sqrt(i) * 10 / 57 for i in range(32)]
B_ONE = 8192                    # the program's B: 8192 = 1
C_ONE = 256 * 256 / 255         # its C: 8.8, with the sines' 256/255 folded in
GA, GB, GC, GX = range(4)       # its gliding values: 8 A, B, C, 1.1 C


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


def glide(st):
    """A (exact), B and C as the sample has them at this step."""
    (a0, b0, c0), (a1, b1, c1), n = st["from"], st["to"], st["n"]
    A = A_TAB[a0] + (A_TAB[a1] - A_TAB[a0]) * Fraction(n, GLIDE)
    B = B_TAB[b0] + (B_TAB[b1] - B_TAB[b0]) * n / GLIDE
    C = C_TAB[c0] + (C_TAB[c1] - C_TAB[c0]) * n / GLIDE
    return A, B, C


def expected(st):
    """The sample's 16 dots for this step."""
    A, B, C = glide(st)
    out = []
    for k in range(1, PER_STEP + 1):
        ang = (math.floor(8 * k * A) & 127) * 2 * math.pi / 128
        tu = (st["t"] + 15 * k) % 240 * math.pi / 120
        out.append((140 + math.floor(C * (B * math.sin(ang) + math.sin(tu)) * XA),
                    96 + math.floor(C * (B * math.cos(ang) + math.cos(tu)))))
    return out


def slot_dots(s, slot):
    base = s.addr("rose_ring") + 2 * PER_STEP * slot
    return [(s.peek(base + 2 * i), s.peek(base + 2 * i + 1)) for i in range(PER_STEP)]


def newest(s):
    return slot_dots(s, (s.peek(s.addr("rose_slot")) - 1) % SLOTS)


def kept(s):
    """Every kept dot, as (x, y) of its top-left."""
    slot, full = s.peek(s.addr("rose_slot")), s.peek(s.addr("rose_full"))
    return [d for i in range(full) for d in slot_dots(s, (slot - 1 - i) % SLOTS)]


def block(x, y):
    return {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)}


def blocks(dots):
    return set().union(*(block(x, y) for x, y in dots))


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_draws_16_dots_a_step_and_keeps_the_last_720(s):
    s.step()
    assert s.peek(s.addr("rose_full")) == 1
    run(s, SLOTS - 2)
    assert s.peek(s.addr("rose_full")) == SLOTS - 1
    run(s, 1)
    assert len(kept(s)) == KEEP
    run(s, 60)
    assert len(kept(s)) == KEEP
    assert s.peek(s.addr("rose_full")) == SLOTS


def test_dots_follow_the_formula(built):
    """Every dot lands within one dot of the sample's, through a whole glide and into the next."""
    for seed in (0x4D2A, 0x2468):
        s = start(FX, seed=seed)
        for _ in range(GLIDE + 15):
            st = state(s)
            s.step()
            for got, want in zip(newest(s), expected(st)):
                assert abs(got[0] - want[0]) <= 1 and abs(got[1] - want[1]) <= 1, (st, got, want)


def test_size_starts_at_0(built):
    for seed in (0x1111, 0x2222, 0x3333):
        s = start(FX, seed=seed)
        assert state(s)["from"][2] == 0
        assert cur(s, GC) == 0 and cur(s, GX) == 0
        s.step()
        assert newest(s) == [(140, 96)] * PER_STEP


def test_values_glide_from_table_value_to_table_value_over_250_steps(built):
    s = start(FX, seed=0x5A5A)
    st0 = state(s)
    a0, b0, c0 = st0["from"]
    assert st0["n"] == 0
    assert eight_a(s) == 8 * A_TAB[a0]
    assert cur(s, GB) == round(B_TAB[b0] * B_ONE) and rem(s, GB) == 0
    for n in range(1, GLIDE):
        s.step()
        st = state(s)
        assert st["n"] == n and st["from"] == st0["from"] and st["to"] == st0["to"]
        A, B, C = glide(st)
        assert eight_a(s) == 8 * A                          # exact: the angle index floors on it
        assert abs(cur(s, GB) - B * B_ONE) <= 1.5
        assert abs(cur(s, GC) - C * C_ONE) <= 1.5
        assert abs(cur(s, GX) - XA * C * C_ONE) <= 1.5
    s.step()                                                # the 250th: the targets are reached
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
        s.poke(s.addr("rose_n"), GLIDE - 1)
        s.step()
        st = state(s)
        assert st["n"] == 0 and st["from"] == before
        a, b, c = st["to"]
        assert a < len(A_TAB) and b < len(B_TAB) and c < len(C_TAB)
        for i in range(3):
            seen[i].add(st["to"][i])
    assert len(seen[0]) == len(A_TAB) and len(seen[1]) > 20 and len(seen[2]) > 15


def test_turns_1_5_degrees_a_step(s):
    t0 = state(s)["t"]
    run(s, 10)
    assert state(s)["t"] == (t0 + 10) % 240
    s.poke(s.addr("rose_t"), 239)
    s.step()
    assert state(s)["t"] == 0


def test_dots_are_2x2_blocks(s):
    run(s, 80)
    assert blocks(newest(s)) <= s.page_pixels()        # the newest dots are always whole


def test_screen_holds_only_the_kept_dots(s):
    """Each new dot first rubs out the one it replaces, so the screen never holds more than the
    720 kept dots."""
    for _ in range(3):
        run(s, 100)
        lit = s.page_pixels()
        assert lit
        assert lit <= blocks(kept(s))


def test_ring_wraps(s):
    s.start_tracking()
    run(s, SLOTS * 2 + 7)
    assert s.writes_outside(*ALLOWED) == []
    assert s.peek(s.addr("rose_slot")) == (SLOTS * 2 + 7) % SLOTS
    assert s.page_pixels() <= blocks(kept(s))
