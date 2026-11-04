import sys

import pytest

from conftest import ROOT
from sim import PAGE, PAGE1, PAGE2, Sim

sys.path.insert(0, str(ROOT / "tools"))
import gen_art  # noqa: E402

SPRITES = gen_art.sprites()
PIX, MSK, LC_END = gen_art.layout(SPRITES)
VECTORS = bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66])


@pytest.fixture
def s(built):
    s = Sim()
    s.mem.ram[0xFFFA:0x10000] = VECTORS          # stands in for the ROM's vectors
    s.call("sprite_setup", max_cycles=3_000_000)
    return s


def draw(s, sid, x, y, page=PAGE1, routine="sprite_draw"):
    s.set_point(x, y)
    s.call(routine, a=sid, zp={PAGE: page})


def expected(sid, x, y):
    sp = SPRITES[sid]
    return {(x + dx, y + dy) for dx, dy in sp.lit if 0 <= x + dx < 280 and 0 <= y + dy < 192}


def test_shift_format():
    sp = gen_art.Sprite([[1] * 7], [[1] * 7])     # one row of 7 lit dots
    assert sp.rows(sp.lit, 0)[:2] == [0x7F, 0x00]
    assert sp.rows(sp.lit, 1)[:2] == [0x7E, 0x01]


def test_preshifted_blocks(s):
    for sid, sp in enumerate(SPRITES):
        size = sp.bpr * sp.h
        for k in range(7):
            pix = PIX[sid * 7 + k]
            msk = MSK[sid * 7 + k]
            assert list(s.mem.ram[pix:pix + size]) == sp.rows(sp.lit, k), (sid, k)
            want_mask = [~b & 0x7F for b in sp.rows(sp.mask, k)]
            assert list(s.mem.ram[msk:msk + size]) == want_mask, (sid, k)


@pytest.mark.parametrize("sid", range(4))
def test_draw_matches_reference(s, sid):
    for x in range(3, 10):                        # all seven shifts
        s.fill_page(PAGE1, 0)
        draw(s, sid, x, 20)
        assert s.page_pixels() == expected(sid, x, 20), x


@pytest.mark.parametrize("x,y", [(-39, 50), (-5, 50), (275, 50), (250, 50), (100, -39), (100, -10), (100, 190), (100, 170), (-30, -30), (270, 180)])
@pytest.mark.parametrize("sid", [0, 2, 3])
def test_draw_clips(s, sid, x, y):
    s.fill_page(PAGE1, 0)
    s.start_tracking()
    draw(s, sid, x, y)
    assert s.writes_outside((0x2000, 0x4000), (0x30, 0x40), (0x10, 0x20), (0x100, 0x200)) == []
    assert s.page_pixels() == expected(sid, x, y)


@pytest.mark.parametrize("x,y", [(-60, 50), (300, 50), (100, -60), (100, 200)])
def test_draw_fully_off_screen(s, x, y):
    s.fill_page(PAGE1, 0)
    draw(s, 0, x, y)
    assert s.page_pixels() == set()


def test_erase(s):
    s.fill_page(PAGE1, 0)
    draw(s, 1, 50, 60)
    draw(s, 1, 50, 60, routine="sprite_erase")
    assert s.page_pixels() == set()


def test_page2(s):
    draw(s, 3, 10, 10, page=PAGE2)
    assert s.page_pixels(PAGE2) == expected(3, 10, 10)
    assert s.page_pixels(PAGE1) == set()


def test_overlap_outline(s):
    s.fill_page(PAGE1, 0x7F)
    draw(s, 3, 100, 100)
    sp = SPRITES[3]
    px = s.page_pixels()
    for dx, dy in sp.mask:
        lit = (100 + dx, 100 + dy) in px
        assert lit == ((dx, dy) in sp.lit), (dx, dy)


def test_vectors_kept(s):
    assert bytes(s.mem.ram[0xFFFA:0x10000]) == VECTORS
    assert LC_END <= 0xFFF0


def test_fits():
    print(f"pre-shifted sprites: ${0xD000:04X}-${LC_END - 1:04X} ({LC_END - 0xD000} bytes)")
    assert LC_END <= 0xFFF0
