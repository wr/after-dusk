"""The boot splash: HELLO's machine code, which draws the title picture from a
hook on DOS's disk routine while the effects files load."""
import json
import random
import sys

import pytest

from conftest import ROOT, labels
from sim import Sim

sys.path.insert(0, str(ROOT / "tools"))
import gen_splash  # noqa: E402

SPLASH = 0x0B00
TOTAL_OPS = 280
# DOS's reads for SEED, PAINT, FX, FX3, FX2 and AFTERDUSK, measured in the emulator
READS_PER_FILE = (21, 33, 73, 30, 75, 48)
LOAD_ORDER = ["Flying Toasters", "Warp", "Starry Night", "Zot!", "Can of Worms", "Lissajous", "Nightlines",
              "String Theory", "Rose", "Doodles", "Shapes", "Spheres", "Bouncing Ball", "Rainstorm",
              "Hard Rain", "Snake", "Life II", "Fish!"]
RWTS_CALL = 0xB7B8
HELLO_END_MAX = 0x1E00 - 64   # the row tables start here; BASIC's variables sit after the file


@pytest.fixture
def s(built):
    sim = Sim(build=built)
    sim.mem.ram[SPLASH:SPLASH + (built / "splash.bin").stat().st_size] = (built / "splash.bin").read_bytes()
    paint = (built / "paint.bin").read_bytes()
    sim.mem.ram[0x8000:0x8000 + len(paint)] = paint
    sim.poke(0xFC22, 0x60)     # the Monitor's VTAB: an RTS is enough here
    return sim


def art():
    return json.loads(gen_splash.ART.read_text())


def row_addr(y):
    return 0x2000 + ((y & 7) << 10) + (((y >> 3) & 7) << 7) + ((y >> 6) * 40)


def expected_page(art):
    """The whole picture with every icon drawn, as hi-res bytes by row."""
    pic, _ = gen_splash.decode(art)
    W = gen_splash.W
    order = list(range(14)) + [15, 16, 17, 14]         # the order the files load
    for slot, ic in enumerate(order):
        for r, row in enumerate(art["icons"][ic]):
            for x, ch in enumerate(row):
                if ch == "#":
                    pic[(art["icon_y"] + r) * W + 14 + 14 * slot + x] = 1
    return {y: bytes(sum(pic[y * W + c * 7 + b] << b for b in range(7)) for c in range(40)) for y in range(gen_splash.H)}


def page_row(s, y):
    return bytes(s.mem.ram[row_addr(y):row_addr(y) + 40])


def text_row(s, base):
    return "".join(chr(s.peek(base + c) & 0x7F) for c in range(40)).strip()


def test_hello_entry_points(s):
    for offset, name in enumerate(("splash_init", "splash_next", "stash_fx", "stash_fx3", "stash_fx2", "splash_done")):
        assert s.peek(SPLASH + 3 * offset) == 0x4C
        assert s.peek16(SPLASH + 3 * offset + 1) == labels()[name]


def test_hello_stays_below_the_row_tables(built):
    assert SPLASH + (built / "splash.bin").stat().st_size <= HELLO_END_MAX


def test_init_shows_a_black_page_and_hooks_dos(s):
    s.mem.ram[0x2000:0x4000] = bytes([0x55]) * 0x2000
    s.call("splash_init", max_cycles=2_000_000)
    assert bytes(s.mem.ram[0x2000:0x4000]) == bytes(0x2000)
    assert s.peek16(RWTS_CALL) == labels()["hook"]
    assert s.peek(0x23) == 20, "BASIC's carriage returns stay off the status strip"
    assert text_row(s, 0x06D0) == "Shuffling the screen savers"


def test_the_whole_picture_gets_painted(s):
    s.call("splash_init", max_cycles=2_000_000)
    for _ in range(TOTAL_OPS):
        s.call("tick", max_cycles=200_000)
    s.call("splash_done", max_cycles=2_000_000)
    want = expected_page(art())
    # every icon's stage has to have been reached for the icons to be whole
    for name in ("splash_next",) * 20:
        s.call(name, max_cycles=200_000)
    s.call("splash_done", max_cycles=2_000_000)
    for y, row in want.items():
        assert page_row(s, y) == row, f"row {y}"


def play(s, stop_after=None):
    """As DOS does: HELLO's reads, file by file, with HELLO moving on between
    files. Returns the status line seen at each read."""
    s.call("splash_init", max_cycles=2_000_000)
    seen, reads = [], 0
    for i, n in enumerate(READS_PER_FILE):
        if i:
            s.call("splash_next", max_cycles=200_000)
        for _ in range(n):
            if stop_after is not None and reads == stop_after:
                return seen
            s.call("tick", max_cycles=200_000)
            reads += 1
            seen.append(text_row(s, 0x06D0))
    return seen


def lit_dots(s):
    return sum(bin(b).count("1") for y in range(gen_splash.H) for b in page_row(s, y))


def test_every_screen_saver_gets_its_turn(s):
    seen = [line.split("   ")[0] for line in play(s)]
    names = list(dict.fromkeys(seen))
    assert names == ["Shuffling the screen savers", "Loading the picture"] + [f"Loading {n}" for n in LOAD_ORDER] + ["Almost ready"]
    # a file's first read or so finds its data late, so its first caption stays longest
    assert seen.count("Loading Flying Toasters") >= 9
    assert seen.count("Loading Hard Rain") >= 9


def test_each_stage_has_reads(s):
    table = labels()["stage_ops"]
    assert all(s.peek(table + i) > 0 for i in range(21))


def test_the_picture_is_part_drawn_half_way(s):
    total = sum(gen_splash.decode(art())[0])
    play(s, stop_after=140)
    assert 0.4 * total < lit_dots(s) < 0.95 * total


def test_the_reads_alone_nearly_finish_the_picture(s):
    total = sum(gen_splash.decode(art())[0])
    play(s)
    assert lit_dots(s) > 0.97 * total


def test_icons_are_whole_after_the_reads(s):
    a = art()
    play(s)
    want = expected_page(a)
    for r in range(14):
        y = a["icon_y"] + r
        assert page_row(s, y) == want[y], f"row {y}"


def test_no_step_takes_too_long(s):
    """A tick has to fit the gap between sector reads (about 20 ms costs under
    6 seconds over the whole load)."""
    s.call("splash_init", max_cycles=2_000_000)
    worst = 0
    for _ in range(TOTAL_OPS):
        worst = max(worst, s.call("tick", max_cycles=200_000))
    assert worst < 20_000


def test_done_restores_the_call_to_dos(s):
    s.call("splash_init", max_cycles=2_000_000)
    s.call("splash_done", max_cycles=2_000_000)
    assert s.peek16(RWTS_CALL) == 0xBD00


def test_next_walks_the_files_in_order(s):
    s.call("splash_init", max_cycles=2_000_000)
    seen = []
    for _ in range(6):
        s.call("splash_next", max_cycles=200_000)
        seen.append(text_row(s, 0x06D0).split("   ")[0])
    assert seen == ["Loading the picture", "Loading Flying Toasters", "Loading Hard Rain", "Loading Fish!", "Almost ready", "Almost ready"]


@pytest.mark.parametrize("name,home,pages", [("stash_fx", 0x2000, 0x40), ("stash_fx2", 0x6000, 0x40), ("stash_fx3", 0xA000, 0x20)])
def test_stash_copies_to_its_home_in_aux(s, name, home, pages):
    """HELLO calls these from BASIC, so they use only zero page $06-$09 and
    leave main memory alone and writes on main."""
    rnd = random.Random(home)
    junk = bytes(rnd.randrange(256) for _ in range(pages * 256))
    s.mem.ram[0x4000:0x4000 + len(junk)] = junk
    zp = bytes(s.mem.ram[0:256])
    s.call(name, max_cycles=2_000_000)
    assert bytes(s.mem.aux[home:home + len(junk)]) == junk
    assert bytes(s.mem.ram[0x4000:0x4000 + len(junk)]) == junk
    assert not s.mem.wr_aux and not s.mem.rd_aux
    changed = [i for i in range(256) if s.mem.ram[i] != zp[i]]
    assert all(0x06 <= i <= 0x09 for i in changed), changed


def test_the_stream_decodes_to_the_picture():
    """The generator's stream, read back in Python."""
    pic, steps = gen_splash.decode(art())
    stream = b"".join(gen_splash.encode(gen_splash.fragments(pic, steps)))
    page = {y: bytearray(40) for y in range(gen_splash.H)}
    i = cury = 0
    while i < len(stream):
        b = stream[i]
        i += 1
        if b == 0x80:
            continue
        col = b & 0x3F
        if b & 0x40:
            cury += 1
        else:
            cury = stream[i]
            i += 1
        mode, n = stream[i] & 0xC0, stream[i] & 0x3F
        i += 1
        vals = stream[i:i + (n if mode == 0 else 1 if mode == 0x40 else 2)]
        i += len(vals)
        for k in range(n):
            v = vals[k] if mode == 0 else vals[0] if mode == 0x40 else vals[k % 2]
            page[cury][col + k] |= v
    for y in range(gen_splash.H):
        want = bytes(sum(pic[y * gen_splash.W + c * 7 + b] << b for b in range(7)) for c in range(40))
        assert bytes(page[y]) == want, f"row {y}"
