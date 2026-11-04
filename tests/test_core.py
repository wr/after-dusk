from collections import Counter

import pytest

from sim import KBD, KBDSTRB, RNG, SEED, ST_FAST, ST_TIMING, TICKS, Sim

TICK = 17030


@pytest.fixture
def s(built):
    return Sim()


def xorshift(x):
    """16-bit xorshift with shifts 7, 9, 8 (John Metcalf's 798)."""
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x


def test_rng_matches_reference(s):
    s.poke16(RNG, 0x1234)
    x = 0x1234
    for _ in range(1000):
        s.call("rng_next")
        x = xorshift(x)
        assert s.peek16(RNG) == x
        assert s.mpu.a == x & 0xFF
        assert x != 0


def test_rng_seed_zero(s):
    s.poke16(SEED, 0)
    s.call("rng_seed")
    assert s.peek16(RNG) != 0


def test_rng_seed_varies(s):
    states = set()
    for seed in range(1, 21):
        s.poke16(SEED, seed)
        s.call("rng_seed")
        states.add(s.peek16(RNG))
    assert len(states) == 20


def test_rng_below(s):
    s.poke16(RNG, 0xBEEF)
    counts = Counter()
    for _ in range(6000):
        s.call("rng_below", a=6)
        counts[s.mpu.a] += 1
    assert set(counts) <= set(range(6))
    assert min(counts[i] for i in range(6)) >= 800


def test_rng_below_one(s):
    s.poke16(RNG, 0x0101)
    for _ in range(20):
        s.call("rng_below", a=1)
        assert s.mpu.a == 0


def test_key_waiting(s):
    s.poke(KBD, 0xC1)
    s.mem.watch_reads = {KBDSTRB}
    s.call("key_pressed")
    assert s.carry()
    assert KBDSTRB in s.mem.reads


def test_no_key(s):
    s.poke(KBD, 0x41)
    s.mem.watch_reads = {KBDSTRB}
    s.call("key_pressed")
    assert not s.carry()
    assert KBDSTRB not in s.mem.reads


@pytest.mark.parametrize("fast,factor", [(0, 1), (1, 4)])
def test_wait_ticks_fallback(s, fast, factor):
    s.poke(ST_TIMING, 0)
    s.poke(ST_FAST, fast)
    s.poke16(TICKS, 100)
    cycles = s.call("wait_ticks", a=2)
    want = 2 * TICK * factor
    assert abs(cycles - want) <= want * 0.01, cycles
    assert s.peek16(TICKS) == 102


def test_timing_init_detects_plus(s):
    s.poke(0xFBBF, 0x05)
    s.call("timing_init", max_cycles=2_000_000)
    assert s.peek(ST_FAST) == 1
    assert s.peek(ST_TIMING) == 0          # the simulator has no vertical blank


def test_timing_init_plain_iic(s):
    s.poke(0xFBBF, 0xFF)
    s.call("timing_init", max_cycles=2_000_000)
    assert s.peek(ST_FAST) == 0
