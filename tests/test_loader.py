"""The effect loader. HELLO loads every effect (the FX file) at $2000; start copies
$2000-$5FFF to aux memory; each effect's code is copied from aux into the overlay
slot at $8800 when its turn comes."""
import random

import pytest

from conftest import BUILD
from fxcommon import NFX
from sim import Sim

OVL, OVL_END = 0x8800, 0x9600
FX_BASE, FX_END = 0x2000, 0x6000


def fx_file():
    return (BUILD / "fx.bin").read_bytes()


def entries(s):
    n = s.peek(s.addr("fx_count"))
    base = s.addr("fx_table")
    return [(s.peek16(base + i * 6), s.peek16(base + i * 6 + 2)) for i in range(n)]


def booted():
    """A Sim as After Dusk leaves it after start-up: effects in aux, copy loop installed."""
    return Sim().load_effects()


@pytest.fixture
def s(built):
    return booted()


def test_count(s):
    assert s.peek(s.addr("fx_count")) == NFX


def test_fx_file_fits(built):
    assert 0 < len(fx_file()) <= FX_END - FX_BASE


def test_table_matches_the_file(s):
    data = fx_file()
    addr = FX_BASE
    for a, size in entries(s):
        assert a == addr, "effects sit one after another in the FX file"
        assert 6 < size <= OVL_END - OVL
        addr += size
    assert addr - FX_BASE == len(data)


def test_stash_copies_to_aux(built):
    s = Sim()
    rnd = random.Random(5)
    junk = bytes(rnd.randrange(256) for _ in range(FX_END - FX_BASE))
    s.mem.ram[FX_BASE:FX_END] = junk
    s.call("fx_stash", max_cycles=2_000_000)
    assert bytes(s.mem.aux[FX_BASE:FX_END]) == junk
    assert bytes(s.mem.ram[FX_BASE:FX_END]) == junk
    assert not s.mem.rd_aux and not s.mem.wr_aux


def test_load_each_effect(s):
    data = fx_file()
    for fx, (a, size) in enumerate(entries(s)):
        s.mem.ram[OVL:OVL_END] = bytes(OVL_END - OVL)
        s.start_tracking()
        s.call("load_fx", a=fx)
        assert bytes(s.mem.ram[OVL:OVL + size]) == data[a - FX_BASE:a - FX_BASE + size]
        assert not s.mem.rd_aux and not s.mem.wr_aux
        assert s.writes_outside((0x00, 0x200), (OVL, OVL_END)) == []


def test_overlays_start_with_init_and_step(s):
    data = fx_file()
    for a, size in entries(s):
        code = data[a - FX_BASE:a - FX_BASE + size]
        for off in (0, 3):
            assert code[off] == 0x4C, "jmp init, jmp step"
            target = code[off + 1] | code[off + 2] << 8
            assert OVL + 6 <= target < OVL + size


def test_load_is_quick(s):
    """Copying even a full slot takes a few frames: nothing anyone would see
    (the last effect's final picture just stays a moment longer)."""
    biggest = max(range(len(entries(s))), key=lambda i: entries(s)[i][1])
    pages = (entries(s)[biggest][1] + 255) // 256
    cycles = s.call("load_fx", a=biggest)
    assert cycles < 4_200 * pages + 300
    assert 4_200 * 14 < 6 * 17_030          # a full slot: under 6 frames, 0.1 s
