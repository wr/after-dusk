"""Fish! (effect 14), so far: init copies its art and floor out of FX2 into
place, builds its shift and bit-reverse tables, and draws the sea floor."""
import json
import random

import pytest

from conftest import BUILD
from fxcommon import ALLOWED, OVL, start
from sim import PAGE1, PAGE2, RNG, TICKS, row_base

FX = 14
FLOOR_TOP = 156
FLOOR_BYTES = (192 - FLOOR_TOP) * 40


def art():
    return json.loads((BUILD / "fish_art.json").read_text())


def junk(s):
    """Leftovers from other effects in FXRAM and on both pages, so init has to
    write everything it relies on."""
    rnd = random.Random(14)
    for lo, hi in ((0x0800, 0x2000), (0x2000, 0x6000)):
        s.mem.ram[lo:hi] = bytes(rnd.randrange(128) for _ in range(hi - lo))


def visible(s, page):
    """The 40 bytes of every row of a page, top to bottom (no screen holes)."""
    return b"".join(bytes(s.mem.ram[row_base(y, page):row_base(y, page) + 40]) for y in range(192))


def mem(s, name, n):
    a = s.addr(name)
    return bytes(s.mem.ram[a:a + n])


@pytest.fixture(scope="module")
def s(built):
    return start(FX, prepare=junk)


def test_init_copies_art_and_floor(s):
    data = (BUILD / "fx2.bin").read_bytes()
    a = s.addr("__FISHART_LOAD__") - 0x6000
    size = s.addr("__FISHART_SIZE__")
    assert mem(s, "__FISHART_RUN__", size) == data[a:a + size]
    # every frame is where the descriptor tables say
    for k, kind in enumerate(art()["kinds"]):
        n = kind["rows"] * kind["wb"]
        for f, frame in enumerate(kind["frames"]):
            at = s.peek(s.addr(f"fk_f{f}lo") + k) | s.peek(s.addr(f"fk_f{f}hi") + k) << 8
            want = bytes(b for part in ("lit", "mask") for row in frame[part] for b in row)
            assert len(want) == 2 * n
            assert bytes(s.mem.ram[at:at + 2 * n]) == want, (k, f)
    floor = bytes(b for row in art()["floor"] for b in row)
    assert len(floor) == FLOOR_BYTES
    assert mem(s, "FISH_FLOOR", FLOOR_BYTES) == floor


def test_tables(s):
    sht = s.addr("FISH_SHT")
    for k in range(7):
        for b in range(128):
            assert s.peek(sht + k * 256 + b) == (b << k) & 0x7F, (k, b)
            assert s.peek(sht + k * 256 + 128 + b) == b >> (7 - k), (k, b)
    rev = s.addr("FISH_REV")
    for b in range(128):
        assert s.peek(rev + b) == int(f"{b:07b}"[::-1], 2), b


def test_floor_on_screen(s):
    assert s.addr("FLOOR_TOP") == FLOOR_TOP
    floor = art()["floor"]
    for r in range(192 - FLOOR_TOP):
        a = row_base(FLOOR_TOP + r)
        assert bytes(s.mem.ram[a:a + 40]) == bytes(floor[r]), FLOOR_TOP + r
    assert visible(s, PAGE1)[:FLOOR_TOP * 40] == bytes(FLOOR_TOP * 40)
    assert mem(s, "FISH_BG", FLOOR_BYTES) == mem(s, "FISH_FLOOR", FLOOR_BYTES)


def test_init_writes_only_its_own_memory(built):
    def track(s):
        junk(s)
        s.start_tracking()
    s = start(FX, prepare=track)
    assert s.writes_outside(*ALLOWED) == []
    assert not s.mem.rd_aux and not s.mem.wr_aux


@pytest.mark.parametrize("fx", (0, 3))
def test_effects_after_fish_dont_show_its_art(built, fx):
    """Fish! leaves its art on page 2. Flying Toasters (which clears page 2)
    and Zot! (which fills it with page 1 inverted) show page 2: what they show
    must be what they would show had Fish! never run."""
    def run(fish_first):
        shown = []

        def prepare(s):
            if fish_first:
                seed, ticks = s.peek16(RNG), s.peek16(TICKS)
                s.call("load_fx", a=FX)
                s.call("wipe_to_black", max_cycles=2_000_000)
                s.call(OVL, max_cycles=3_000_000)
                assert any(visible(s, PAGE2)), "Fish!'s art is on page 2"
                s.call("load_fx", a=fx)
                s.poke16(RNG, seed)
                s.poke16(TICKS, ticks)
            s.mem.write_hooks[0xC055] = lambda v: shown.append(visible(s, PAGE2))

        s = start(fx, prepare=prepare)
        at_init = visible(s, PAGE1), visible(s, PAGE2)
        for _ in range(3):
            s.step()
        return at_init, shown

    (page1, page2), shown = run(True)
    if fx == 0:
        assert page2 == bytes(len(page2))
        assert shown, "the toasters showed page 2"
    else:
        assert page2 == bytes(b ^ 0x7F for b in page1)
    assert shown == run(False)[1]
