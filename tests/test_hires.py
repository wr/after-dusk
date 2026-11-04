import pytest

from sim import PAGE, PAGE1, PAGE2, PCOL, PX2, PY2, RAD, ST_TIMING, Sim, VblLatch, row_base

FRAMES = 0x2C                   # timing.s: vertical blanks counted

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


# ---- fline: the fast line, for lines wholly on screen ----

def fline(s, x0, y0, x1, y1, col=SET, page=PAGE1):
    s.set_point(x0, y0)
    s.set_point(x1, y1, PX2, PY2)
    return s.call("fline", zp={PCOL: col, PAGE: page})


FLINES = [
    (0, 0, 279, 191), (279, 0, 0, 191), (0, 191, 279, 0), (10, 5, 10, 180), (10, 180, 10, 5),
    (3, 100, 270, 100), (140, 96, 140, 96), (13, 10, 267, 182), (200, 50, 30, 120),
    (50, 20, 60, 190), (277, 3, 279, 191), (0, 0, 255, 1), (0, 0, 256, 0), (6, 7, 8, 9),
]


def straight(dots, x0, y0, x1, y1):
    """One dot per step along the longer axis, each within half a dot of the true line."""
    dx, dy = x1 - x0, y1 - y0
    assert len(dots) == max(abs(dx), abs(dy)) + 1
    assert (x0, y0) in dots and (x1, y1) in dots
    if abs(dx) >= abs(dy):
        assert sorted(x for x, _ in dots) == list(range(min(x0, x1), max(x0, x1) + 1))
        for x, y in dots:
            assert abs(y - (y0 + dy * (x - x0) / dx if dx else y0)) <= 0.5
    else:
        assert sorted(y for _, y in dots) == list(range(min(y0, y1), max(y0, y1) + 1))
        for x, y in dots:
            assert abs(x - (x0 + dx * (y - y0) / dy)) <= 0.5


@pytest.mark.parametrize("x0,y0,x1,y1", FLINES)
def test_fline_draws_the_line(s, x0, y0, x1, y1):
    fline(s, x0, y0, x1, y1)
    straight(s.page_pixels(), x0, y0, x1, y1)


def test_fline_random_lines(built):
    import random
    rnd = random.Random(7)
    for _ in range(40):
        s = Sim()
        x0, x1 = rnd.randrange(280), rnd.randrange(280)
        y0, y1 = rnd.randrange(192), rnd.randrange(192)
        fline(s, x0, y0, x1, y1)
        straight(s.page_pixels(), x0, y0, x1, y1)


@pytest.mark.parametrize("x0,y0,x1,y1", FLINES)
def test_fline_same_dots_both_ways(built, x0, y0, x1, y1):
    a, b = Sim(), Sim()
    fline(a, x0, y0, x1, y1)
    fline(b, x1, y1, x0, y0)
    assert a.page_pixels() == b.page_pixels()


def test_fline_clear_takes_out_only_its_dots(built):
    import random
    rnd = random.Random(3)
    blank = Sim()
    fline(blank, 13, 10, 267, 182)
    dots = blank.page_pixels()
    s = Sim()
    for a in range(0x2000, 0x4000):
        s.poke(a, rnd.randrange(0x80))
    before = s.page_pixels()
    fline(s, 13, 10, 267, 182, SET)
    assert s.page_pixels() == before | dots
    fline(s, 267, 182, 13, 10, CLEAR)
    assert s.page_pixels() == before - dots
    assert all(b & 0x80 == 0 for b in s.page_bytes(PAGE1))


def test_fline_page2(s):
    fline(s, 0, 0, 279, 191, SET, PAGE2)
    assert s.page_pixels(PAGE1) == set()
    straight(s.page_pixels(PAGE2), 0, 0, 279, 191)


@pytest.mark.parametrize("x0,y0,x1,y1", [(0, 0, 190, 191), (10, 5, 10, 180), (279, 0, 100, 191)])
def test_fline_tall_lines_fit_in_a_frame(s, x0, y0, x1, y1):
    """Lines taller than wide don't count vertical blanks, so they must take under a frame."""
    assert fline(s, x0, y0, x1, y1) < 15_000


def test_fline_wide_lines_are_quick(s):
    assert fline(s, 30, 20, 250, 170) < 16_000          # the longest Lissajous lines
    assert fline(s, 0, 96, 279, 96) < 17_000


def test_fline_counts_blanks_on_long_lines(built):
    """Lines wider than tall can take more than a frame; they count the blanks they cross."""
    s = Sim()
    VblLatch(s)
    s.poke(ST_TIMING, 1)
    s.poke16(FRAMES, 0)
    first = s.mpu.processorCycles // 17030
    for _ in range(4):
        fline(s, 0, 0, 279, 191)
        fline(s, 0, 191, 279, 0, CLEAR)
    crossed = s.mpu.processorCycles // 17030 - first
    assert crossed >= 5
    assert crossed - 1 <= s.peek16(FRAMES) <= crossed
