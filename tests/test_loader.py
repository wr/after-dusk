"""The effect loader. HELLO loads each effects file at $4000 and puts it in its
home in aux memory (see test_splash.py); start moves FX3 on to main $A000-$BFFF.
Each effect's code is copied into the overlay slot at $8800 when its turn
comes."""
import random

import pytest

from conftest import BUILD
from fxcommon import NFX
from sim import Sim

OVL, OVL_END = 0x8800, 0x9600
FX_BASE, FX_END = 0x2000, 0x6000
FX2_BASE, FX2_END = 0x6000, 0xA000
FX3_BASE, FX3_END = 0xA000, 0xC000
FX2_FIRST = 14                  # the first effect in FX2
FX3_FIRST = 15                  # the first effect in FX3


def fx_file():
    return (BUILD / "fx.bin").read_bytes()


def fx2_file():
    return (BUILD / "fx2.bin").read_bytes()


def fx3_file():
    return (BUILD / "fx3.bin").read_bytes()


def code(a, size):
    """An effect's code, from whichever file holds address a."""
    if FX3_BASE <= a < FX3_END:
        return fx3_file()[a - FX3_BASE:a - FX3_BASE + size]
    if FX2_BASE <= a < FX2_END:
        return fx2_file()[a - FX2_BASE:a - FX2_BASE + size]
    return fx_file()[a - FX_BASE:a - FX_BASE + size]


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


def test_fx2_file_fits(built):
    assert 0 < len(fx2_file()) <= FX2_END - FX2_BASE


def test_table_matches_the_files(s):
    def back_to_back(effects, base):
        addr = base
        for a, size in effects:
            assert a == addr, "effects sit one after another in their file"
            assert 6 < size <= OVL_END - OVL
            addr += size
        return addr - base

    ents = entries(s)
    assert back_to_back(ents[:FX2_FIRST], FX_BASE) == len(fx_file())
    # FX2 holds effect 14, then Fish!'s art and floor
    assert 0 < back_to_back(ents[FX2_FIRST:FX3_FIRST], FX2_BASE) < len(fx2_file())
    assert back_to_back(ents[FX3_FIRST:], FX3_BASE) <= len(fx3_file())


def test_fx3_file_fits(built):
    assert 0 < len(fx3_file()) <= FX3_END - FX3_BASE


def test_fx3_restore_copies_to_main(built):
    s = Sim()
    s.call("lc_install")
    rnd = random.Random(8)
    junk = bytes(rnd.randrange(256) for _ in range(FX3_END - FX3_BASE))
    s.mem.aux[FX3_BASE:FX3_END] = junk
    s.call("fx3_restore", max_cycles=2_000_000)
    assert bytes(s.mem.ram[FX3_BASE:FX3_END]) == junk
    assert not s.mem.rd_aux and not s.mem.wr_aux


def test_fx3_effect_survives_aux_overwrite(s):
    """Fish! builds tables over aux $A000 up; FX3's effects load from main."""
    s.mem.aux[FX3_BASE:FX3_END] = bytes([0xA5]) * (FX3_END - FX3_BASE)
    a, size = entries(s)[FX3_FIRST]
    s.mem.ram[OVL:OVL_END] = bytes(OVL_END - OVL)
    s.call("load_fx", a=FX3_FIRST)
    assert bytes(s.mem.ram[OVL:OVL + size]) == code(a, size)


def test_setup_leaves_fx3_alone(s):
    """Ctrl-Reset runs setup again. Fish! may have overwritten the aux copy by
    then, so main $A000-$BFFF must simply be left as it is."""
    s.mem.aux[FX3_BASE:FX3_END] = bytes([0xA5]) * (FX3_END - FX3_BASE)
    before = bytes(s.mem.ram[FX3_BASE:FX3_END])
    s.call("setup", max_cycles=40_000_000)
    assert bytes(s.mem.ram[FX3_BASE:FX3_END]) == before
    assert s.addr("restart")


def test_load_each_effect(s):
    for fx, (a, size) in enumerate(entries(s)):
        s.mem.ram[OVL:OVL_END] = bytes(OVL_END - OVL)
        s.start_tracking()
        s.call("load_fx", a=fx)
        assert bytes(s.mem.ram[OVL:OVL + size]) == code(a, size)
        assert not s.mem.rd_aux and not s.mem.wr_aux
        assert s.writes_outside((0x00, 0x200), (OVL, OVL_END)) == []


def test_overlays_start_with_init_and_step(s):
    for a, size in entries(s):
        c = code(a, size)
        for off in (0, 3):
            assert c[off] == 0x4C, "jmp init, jmp step"
            target = c[off + 1] | c[off + 2] << 8
            assert OVL + 6 <= target < OVL + size


def test_load_is_quick(s):
    """Copying even a full slot takes a few frames: nothing anyone would see
    (the last effect's final picture just stays a moment longer)."""
    biggest = max(range(len(entries(s))), key=lambda i: entries(s)[i][1])
    pages = (entries(s)[biggest][1] + 255) // 256
    cycles = s.call("load_fx", a=biggest)
    # 16-17 cycles a byte: one more whenever the source crosses a page, which
    # it does on every page unless the effect starts on a page boundary
    assert cycles < 4_400 * pages + 300
    assert 4_400 * 14 < 6 * 17_030          # a full slot: under 6 frames, 0.1 s
