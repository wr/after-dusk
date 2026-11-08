import sys

import pytest

from conftest import ROOT
from sim import PAGE, PAGE1, PAGE2, Sim

sys.path.insert(0, str(ROOT / "tools"))
import gen_art  # noqa: E402

SPRITES = gen_art.sprites()
BLK, LC_END = gen_art.layout(SPRITES)
VECTORS = bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
SCRATCH = [(0x2000, 0x4000), (0x30, 0x40), (0x90, 0xA0), (0x10, 0x20), (0x100, 0x200)]


def patch_sites(s):
    """The fast loops' operands, which the engine rewrites per sprite."""
    return (s.addr("fd_row"), s.addr("rebase"))


@pytest.fixture
def s(built):
    s = Sim()
    s.mem.ram[0xFFFA:0x10000] = VECTORS          # stands in for the ROM's vectors
    s.call("sprite_setup", max_cycles=3_000_000)
    s.call("sprite_tables", max_cycles=1_000_000)
    return s


def draw(s, sid, x, y, page=PAGE1, routine="sprite_draw"):
    s.set_point(x, y)
    s.call(routine, a=sid, zp={PAGE: page})


def expected(sid, x, y):
    sp = SPRITES[sid]
    return {(x + dx, y + dy) for dx, dy in sp.lit if 0 <= x + dx < 280 and 0 <= y + dy < 192}


def checker():
    return {(x, y) for y in range(192) for x in range(280) if (x + y) & 1}


def test_row_descriptors():
    for sp in SPRITES:
        for r, (a, e, fa, fe) in enumerate(sp.rows_desc()):
            xs = sp.row_dots(sp.mask, r)
            assert (a, e) == (xs[0], xs[-1] + 1)
            assert all(x in xs for x in range(fa, fe))
            runs, start = [], xs[0]
            for i in range(1, len(xs) + 1):
                if i == len(xs) or xs[i] != xs[i - 1] + 1:
                    runs.append(xs[i - 1] + 1 - start)
                    if i < len(xs):
                        start = xs[i]
            assert fe - fa == max(runs)


def test_packed_format():
    sp = gen_art.Sprite([[1] * 7], [[1] * 7])     # one row of 7 covered dots
    assert sp.packed(0) == [0x7F]
    assert sp.packed(1) == [0x7E, 0x01, 0x01, 0x7E]


def test_lc_fits():
    total = LC_END - gen_art.LC_START
    print(f"packed sprites: ${gen_art.LC_START:04X}-${LC_END - 1:04X} ({total} bytes)")
    assert LC_END <= gen_art.LC_LIMIT


def test_packed_blocks(s):
    for sid, sp in enumerate(SPRITES):
        for k in range(7):
            want = sp.packed(k)
            a = BLK[sid * 7 + k]
            assert list(s.mem.ram[a:a + len(want)]) == want, (sid, k)


def test_row_tables(s):
    for sid, sp in enumerate(SPRITES):
        for k in range(7):
            a = gen_art.row_tables(SPRITES)[sid * 7 + k]
            got = list(s.mem.ram[a:a + 4 * sp.h])
            want = [list(col) for col in zip(*sp.columns(k))]
            assert got == sum(want, []), (sid, k)


def test_tables_time(s):
    cycles = s.call("sprite_tables", max_cycles=1_000_000)
    print("sprite_tables", cycles, "cycles")
    assert cycles < 300_000


def test_vectors_kept(s):
    assert bytes(s.mem.ram[0xFFFA:0x10000]) == VECTORS


def test_setup_time(built):
    s = Sim()
    cycles = s.call("sprite_setup", max_cycles=3_000_000)
    print("sprite_setup", cycles, "cycles")
    assert cycles < 1_500_000


@pytest.mark.parametrize("sid", range(5))
def test_draw_matches_reference(s, sid):
    for x in range(3, 10):                        # all seven shifts
        s.fill_page(PAGE1, 0)
        draw(s, sid, x, 20)
        assert s.page_pixels() == expected(sid, x, 20), x


def test_draw_over_picture(s):
    s.set_pixels(checker(), PAGE1)
    draw(s, 0, 100, 60)
    sp = SPRITES[0]
    masked = checker() - {(100 + dx, 60 + dy) for dx, dy in sp.mask}
    assert s.page_pixels() == masked | expected(0, 100, 60)
    draw(s, 0, 100, 60, routine="sprite_erase")
    covered = {(bx * 7 + bit, y) for x, y in ((100 + dx, 60 + dy) for dx, dy in sp.mask)
               for bx in [x // 7] for bit in range(7)}
    assert s.page_pixels() == masked - covered


@pytest.mark.parametrize("x,y", [(-39, 50), (-5, 50), (275, 50), (250, 50), (100, -39), (100, -10),
                                 (100, 190), (100, 170), (-30, -30), (270, 180),
                                 (300, -40), (285, 100), (-38, 185), (-41, 150)])
@pytest.mark.parametrize("sid", [0, 3, 4])
def test_draw_clips(s, sid, x, y):
    s.fill_page(PAGE1, 0)
    s.start_tracking()
    draw(s, sid, x, y)
    assert s.writes_outside(*SCRATCH, patch_sites(s)) == []
    assert s.page_pixels() == expected(sid, x, y)
    s.start_tracking()
    draw(s, sid, x, y, routine="sprite_erase")
    assert s.writes_outside(*SCRATCH, patch_sites(s)) == []
    assert s.page_pixels() == set()


@pytest.mark.parametrize("x,y", [(-60, 50), (300, 50), (100, -60), (100, 200)])
@pytest.mark.parametrize("sid", [0, 4])
def test_draw_fully_off_screen(s, sid, x, y):
    s.fill_page(PAGE1, 0)
    draw(s, sid, x, y)
    assert s.page_pixels() == set()


@pytest.mark.parametrize("sid", [0, 4])
def test_erase(s, sid):
    s.fill_page(PAGE1, 0)
    draw(s, sid, 50, 60)
    draw(s, sid, 50, 60, routine="sprite_erase")
    assert s.page_pixels() == set()


def test_page2(s):
    draw(s, 4, 10, 10, page=PAGE2)
    assert s.page_pixels(PAGE2) == expected(4, 10, 10)
    assert s.page_pixels(PAGE1) == set()
