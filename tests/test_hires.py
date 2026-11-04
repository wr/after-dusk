import pytest

from sim import PAGE, PAGE1, PAGE2, PCOL, PX2, PY2, RAD, Sim, row_base

SET, CLEAR, INVERT = 1, 0, 2


@pytest.fixture
def s(built):
    return Sim()


def plot(s, x, y, col=SET, page=PAGE1):
    s.set_point(x, y)
    s.call("plot", zp={PCOL: col, PAGE: page})


def test_plot_corners(s):
    plot(s, 0, 0)
    plot(s, 279, 191)
    plot(s, 7, 1)
    assert s.peek(0x2000) == 0x01
    assert s.peek(0x3FF7) == 0x40
    assert s.peek(0x2401) == 0x01
    assert s.page_pixels() == {(0, 0), (279, 191), (7, 1)}


@pytest.mark.parametrize("x,y", [(280, 0), (-1, 0), (0, 192), (0, -1), (-300, 5), (600, 600)])
def test_plot_clips(s, x, y):
    before = bytes(s.mem.ram[0x2000:0x6000])
    plot(s, x, y)
    assert bytes(s.mem.ram[0x2000:0x6000]) == before


def test_plot_modes(s):
    s.poke(row_base(50) + 14, 0x55)
    plot(s, 100, 50, INVERT)              # x 100 = byte 14, bit 2
    assert s.peek(row_base(50) + 14) == 0x51
    plot(s, 100, 50, INVERT)
    assert s.peek(row_base(50) + 14) == 0x55
    plot(s, 100, 50, SET)
    plot(s, 100, 50, CLEAR)
    assert s.peek(row_base(50) + 14) == 0x51


def line(s, x0, y0, x1, y1, col=SET, page=PAGE1):
    s.set_point(x0, y0)
    s.set_point(x1, y1, PX2, PY2)
    s.call("line", zp={PCOL: col, PAGE: page})


def test_line_horizontal(s):
    line(s, 0, 0, 6, 0)
    assert s.peek(0x2000) == 0x7F
    assert s.page_pixels() == {(x, 0) for x in range(7)}


def test_line_vertical(s):
    line(s, 0, 0, 0, 7)
    for r in range(8):
        assert s.peek(0x2000 + r * 0x400) == 0x01


def test_line_diagonal(s):
    line(s, 0, 0, 9, 9)
    assert s.page_pixels() == {(i, i) for i in range(10)}


def test_line_backwards_and_clipped(s):
    line(s, 275, 3, 285, 3)               # runs off the right edge
    assert s.page_pixels() == {(x, 3) for x in range(275, 280)}
    s.fill_page(PAGE1, 0)
    line(s, 20, 30, 10, 25)               # right to left, upwards
    px = s.page_pixels()
    assert (20, 30) in px and (10, 25) in px and len(px) == 11


def test_disc_r2(s):
    s.set_point(10, 10)
    s.call("disc", zp={PCOL: SET, PAGE: PAGE1, RAD: 2})
    want = {(10 + dx, 10 + dy) for dx in range(-2, 3) for dy in range(-2, 3) if dx * dx + dy * dy <= 6}
    assert len(want) == 21
    assert s.page_pixels() == want


def test_disc_clips(s):
    s.set_point(1, 1)
    s.call("disc", zp={PCOL: SET, PAGE: PAGE1, RAD: 3})
    assert all(0 <= x < 280 and 0 <= y < 192 for x, y in s.page_pixels())
    before = bytes(s.mem.ram[0x4000:0x6000])
    assert before == bytes(0x2000)


def test_page2(s):
    plot(s, 0, 0, page=PAGE2)
    assert s.peek(0x4000) == 0x01
    assert s.peek(0x2000) == 0x00
    plot(s, 279, 191, page=PAGE2)
    assert s.peek(0x5FF7) == 0x40


def test_bit7_clear(s):
    for i in range(30):
        line(s, i * 9, 0, 279 - i * 9, 191)
        s.set_point(i * 9 + 4, i * 6)
        s.call("disc", zp={PCOL: INVERT, PAGE: PAGE1, RAD: 3})
        plot(s, i * 7 + 3, 191 - i * 5, INVERT)
    assert all(b & 0x80 == 0 for b in s.page_bytes(PAGE1))


def test_clear_invert_copy(s):
    s.fill_page(PAGE1, 0x2A)
    s.call("clear_page", zp={PAGE: PAGE1})
    assert s.page_bytes(PAGE1) == bytes(0x2000)
    s.call("invert_page", zp={PAGE: PAGE1})
    assert s.page_bytes(PAGE1) == bytes([0x7F]) * 0x2000
    s.fill_page(PAGE1, 0)
    for i in range(0, 0x2000, 37):
        s.poke(0x2000 + i, i & 0x7F)
    s.call("copy_page", a=PAGE1, zp={PAGE: PAGE2})
    assert s.page_bytes(PAGE2) == s.page_bytes(PAGE1)


def test_show_pages(s):
    s.call("show_page2")
    assert s.peek(0x24) == 1
    s.call("show_page1")
    assert s.peek(0x24) == 0


@pytest.mark.parametrize("x0,x1,y", [(0, 0, 0), (3, 17, 5), (6, 7, 9), (0, 279, 191), (-5, 4, 2), (270, 300, 3), (13, 13, 100)])
@pytest.mark.parametrize("col", [SET, CLEAR, INVERT])
def test_hspan(s, x0, x1, y, col):
    s.fill_page(PAGE1, 0x2A)
    before = s.page_pixels()
    s.set_point(x0, y)
    s.set_point(x1, y, PX2, PY2)
    s.call("hspan", zp={PCOL: col, PAGE: PAGE1})
    run = {(x, y) for x in range(max(0, x0), min(279, x1) + 1)}
    want = before | run if col == SET else before - run if col == CLEAR else before ^ run
    assert s.page_pixels() == want
    assert all(b & 0x80 == 0 for b in s.page_bytes(PAGE1))


def test_hspan_off_screen(s):
    s.fill_page(PAGE1, 0)
    for x0, x1, y in [(-9, -1, 5), (280, 290, 5), (10, 20, 192), (10, 20, -1), (20, 10, 5)]:
        s.set_point(x0, y)
        s.set_point(x1, y, PX2, PY2)
        s.call("hspan", zp={PCOL: SET, PAGE: PAGE1})
    assert s.page_pixels() == set()


def test_make_tables(s):
    s.call("make_tables", max_cycles=200_000)

    def sar(h, n):
        return ((h - 256 if h & 0x80 else h) >> n) & 0xFF
    want = {
        0xF000: [sar(h, 4) for h in range(256)],
        0xF100: [(h << 4) & 0xF0 for h in range(256)],
        0xF200: [h >> 4 for h in range(256)],
        0xF300: [sar(h, 5) for h in range(256)],
        0xF400: [(h << 3) & 0xF8 for h in range(256)],
        0xF500: [h >> 5 for h in range(256)],
    }
    for base, values in want.items():
        assert list(s.mem.ram[base:base + 256]) == values, hex(base)
