import pytest

from fxcommon import ALLOWED, check_bit7, check_budget, check_in_bounds, run, start
from sim import Sim

FX = 2


def top(s):
    base = s.addr("str_top")
    return [s.peek(base + x) for x in range(280)]


def windows(s):
    n = s.peek16(s.addr("str_nwin"))
    base = s.addr("str_win")
    out = []
    for i in range(n):
        a = base + i * 4
        out.append((s.peek(a) | (s.peek(a + 1) << 8), s.peek(a + 2), s.peek(a + 3)))
    return out


def stars(s):
    n = s.peek(s.addr("str_nstar"))
    base = s.addr("str_star")
    return [(s.peek(base + i * 3) | (s.peek(base + i * 3 + 1) << 8), s.peek(base + i * 3 + 2)) for i in range(n)]


def lights(s):
    n = s.peek(s.addr("str_nant"))
    base = s.addr("str_ant")
    return [(s.peek(base + i * 3) | (s.peek(base + i * 3 + 1) << 8), s.peek(base + i * 3 + 2)) for i in range(n)]


@pytest.fixture
def s(built):
    return start(FX)


def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_init_time(built):
    for seed in (0x1111, 0x2468, 0xACE1):
        s = Sim()
        s.mem.ram[0xFFFA:0x10000] = bytes(6)
        s.poke16(0x20, seed)
        cycles = s.call("fx_starry_init", max_cycles=3_000_000)
        assert cycles < 1_021_800, cycles


def test_skyline(s):
    px = s.page_pixels()
    roofs = [x for x in range(280) if any((x, y) in px for y in range(92, 165))]
    missing = sorted(set(range(280)) - set(roofs))
    # the only columns without a building are the one-dot gaps between buildings
    for x in missing:
        assert x - 1 in roofs and x + 1 in roofs, x
    assert len(missing) <= 20
    t = top(s)
    for x in roofs:
        assert 92 <= t[x] <= 164
        assert (x, t[x]) in px, x                      # the roofline is drawn


def test_windows_start(s):
    w = windows(s)
    assert len(w) >= 200
    lit = sum(1 for _, _, on in w if on)
    assert 0.05 * len(w) <= lit <= 0.20 * len(w)
    px = s.page_pixels()
    for x, y, on in w[:50]:
        cell = {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)}
        assert (cell <= px) if on else not (cell & px), (x, y, on)


def test_stars_above(s):
    t = top(s)
    st = stars(s)
    assert len(st) >= 60
    for x, y in st:
        assert y <= t[x] - 8, (x, y, t[x])


def test_windows_change(s):
    before = sum(on for _, _, on in windows(s))
    run(s, 200)
    after = sum(on for _, _, on in windows(s))
    assert after > before                              # the city comes to life


def test_shooting_star_restores(s):
    run(s, 5)
    while s.peek(s.addr("str_slife")):                  # let any shooting star finish
        s.step()
    before = s.page_pixels()
    s.poke(s.addr("str_slife"), 16)                     # start one by hand
    s.poke16(s.addr("str_sx"), 60)
    s.poke(s.addr("str_sy"), 10)
    s.poke(s.addr("str_sfy"), 0)
    s.poke(s.addr("str_sdir"), 1)                       # rightwards
    s.poke(s.addr("str_nseg"), 0)
    seen_streak = False
    for _ in range(40):
        s.step()
        if any(60 <= x < 140 and 8 <= y < 40 for x, y in s.page_pixels() - before):
            seen_streak = True
        if not s.peek(s.addr("str_slife")) and not s.peek(s.addr("str_nseg")):
            break
    assert seen_streak
    after = s.page_pixels()
    allowed = set()                                     # what may change meanwhile
    for x, y, _ in windows(s):
        allowed |= {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)}
    allowed |= set(stars(s)) | set(lights(s))
    assert (before ^ after) <= allowed


def test_near_wrap(s):
    s.poke(s.addr("str_tick"), 0xFE)
    s.start_tracking()
    run(s, 50)
    assert s.writes_outside(*ALLOWED) == []


@pytest.mark.parametrize("seed", [0xBB9C, 0x634A])
def test_big_city_keeps_all_windows(built, seed):
    """A tall, wide city has more than 800 windows; every one is kept."""
    s = Sim()
    s.poke16(0x20, seed)
    s.call("fx_starry_init", max_cycles=3_000_000)
    w = windows(s)
    assert len(w) > 800
    assert max(x for x, _, _ in w) > 240              # the rightmost buildings have windows
