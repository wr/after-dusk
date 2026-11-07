"""Fish! (effect 14), so far: init copies its art and floor out of FX2 into
place, builds its shift and bit-reverse tables, and draws the sea floor."""
import json
import random
from functools import reduce

import pytest

import fishref
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


# ---------------------------------------------------------------- the row renderer
# Creatures are (kind, frame, dir, x, y), x and y the top-left of the cell.

FR = ("FR_C0", "FR_C1", "FR_R0", "FR_R1")
ROLE_STILL, ROLE_RISE = 4, 5
HOP_LIMIT = 15_500              # one creature's hop must leave the rest of the tick


@pytest.fixture(scope="module")
def r(built):
    """Fish! after init, with a snapshot of its empty sea to go back to."""
    s = start(FX, prepare=junk)
    s.empty = (s.page_bytes(PAGE1), fishref.fish_bg(s))
    return s


def clear(s):
    """Back to the empty sea: floor only, no creatures."""
    page, bg = s.empty
    s.mem.ram[0x2000:0x4000] = page
    a = s.addr("FISH_BG")
    s.mem.ram[a:a + FLOOR_BYTES] = bg
    s.poke(s.addr("fish_n"), 0)


def place(s, specs):
    s.poke(s.addr("fish_n"), len(specs))
    for i, (kind, frame, d, x, y) in enumerate(specs):
        for name, v in (("fish_kind", kind), ("fish_frame", frame), ("fish_dir", d),
                        ("fish_xl", x), ("fish_xh", x >> 8), ("fish_yl", y), ("fish_yh", y >> 8)):
            s.poke(s.addr(name) + i, v)


def kind_of(kind):
    return art()["kinds"][kind]


def box(s, slot):
    s.call("fish_box", x=slot)
    return s.carry(), tuple(s.peek(s.addr(n)) for n in FR)


def set_rect(s, rect):
    for n, v in zip(FR, rect):
        s.poke(s.addr(n), v)


def union(a, b):
    return min(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), max(a[3], b[3])


def redraw(s, rect, left=0xFFFF):
    """fish_rect_begin, then fish_rect_rows with budget `left`: (cycles, finished)."""
    set_rect(s, rect)
    cycles = s.call("fish_rect_begin")
    assert s.peek(s.addr("FR_ROW")) == rect[2]
    s.poke16(s.addr("FR_LEFT"), left)
    cycles += s.call("fish_rect_rows", max_cycles=200_000)
    return cycles, s.carry()


def rebuild_bg(s, rect):
    set_rect(s, rect)
    return s.call("fish_bg_rect", max_cycles=200_000)


def redraw_all(s):
    """Rebuild FISH_BG under every Seaweed and redraw every creature's box,
    in strips no wider than 8 bytes."""
    boxes = [b for v, b in (box(s, i) for i in range(s.peek(s.addr("fish_n")))) if v]
    for c0, c1, r0, r1 in boxes:
        for c in range(c0, c1, 8):
            rebuild_bg(s, (c, min(c + 8, c1), r0, r1))
    for c0, c1, r0, r1 in boxes:
        for c in range(c0, c1, 8):
            assert redraw(s, (c, min(c + 8, c1), r0, r1))[1]


def expected_box(c):
    """The clipped bytes and rows a creature can change: those holding the bw
    dots of its drawing (the frame's 7wb dots less the padding, which is on
    the left when it faces left), or None."""
    k = kind_of(c["kind"])
    top, _, rows = fishref.placed(c)
    if fishref.mirrored(c):
        x = c["x"] + k["cw"] - k["bx"] - k["bw"]
    else:
        x = c["x"] + k["bx"]
    b = (max(x // 7, 0), min((x + k["bw"] - 1) // 7 + 1, 40), max(top, 0), min(top + len(rows), 192))
    return b if b[0] < b[1] and b[2] < b[3] else None


def check(s, *why):
    assert s.page_bytes(PAGE1) == fishref.expected_page(s), why


def test_box(r):
    for kind in range(14):
        for d in (0, 1):
            for x, y in ((-60, 50), (-40, 50), (-3, 50), (40, 50), (43, 50), (270, 50),
                         (279, 50), (300, 50), (100, -40), (100, -10), (100, 180), (100, 192)):
                clear(r)
                place(r, [(kind, 0, d, x, y)])
                vis, b = box(r, 0)
                want = expected_box(fishref.creatures(r)[0])
                assert vis == (want is not None), (kind, d, x, y)
                if vis:
                    assert b == want, (kind, d, x, y)


@pytest.mark.parametrize("kind", range(14))
def test_one_creature_every_shift_both_ways(r, kind):
    k = kind_of(kind)
    ys = (192 - k["ch"],) if k["role"] == ROLE_STILL else (60, 192 - k["ch"] - 2)
    for y in ys:
        for frame in (0, 1):
            for d in (0, 1):
                for x in range(40, 47):
                    clear(r)
                    place(r, [(kind, frame, d, x, y)])
                    vis, rect = box(r, 0)
                    assert vis
                    if k["role"] == ROLE_STILL:
                        rebuild_bg(r, rect)
                        assert fishref.fish_bg(r) == fishref.expected_bg(r), (y, frame, d, x)
                    assert redraw(r, rect)[1]
                    check(r, y, frame, d, x)


def test_clipping_at_every_edge(r):
    cases = [[(kind, f, d, x, 80)] for kind in (0, 2, 8, 13) for f in (0, 1) for d in (0, 1)
             for x in (-30, -3, 250, 275)]
    cases += [[(11, f, 0, x, -10)] for f in (0, 1) for x in (-3, 100, 270)]   # Bubbles off the top
    cases += [[(5, f, d, x, 192 - 31 - 1)] for f in (0, 1) for d in (0, 1)
              for x in (-30, -3, 250, 275)]                                   # Crab at the bottom
    cases += [[(10, f, 0, x, 192 - 36)] for f in (0, 1) for x in (-30, -3, 250, 275)]  # Seaweed
    cases += [[(12, f, d, x, y)] for f in (0, 1) for d in (0, 1)
              for x, y in ((-3, -20), (275, 175), (100, 180))]                 # corners, bottom
    for specs in cases:
        clear(r)
        place(r, specs)
        redraw_all(r)
        check(r, specs)
    for x, y in ((300, 50), (-60, 50), (100, 192), (100, -40)):                 # off-screen
        clear(r)
        place(r, [(0, 0, 0, x, y)])
        assert not box(r, 0)[0], (x, y)


def test_overlaps_compose_in_slot_order(r):
    sea = [(0, 0, 0, 100, 60), (8, 1, 1, 108, 66), (11, 0, 0, 112, 75)]       # three in rows 75-89
    floor = [(5, 1, 0, 100, 158), (3, 0, 1, 104, 136), (11, 1, 0, 108, 150)]
    pair = [(12, 0, 1, 50, 20), (13, 1, 0, 60, 10)]
    many = [(1, i & 1, i % 2, 90 + 4 * i, 100 + 3 * i) for i in range(5)]       # five in some rows
    for specs in (sea, floor, pair, many):
        pages = []
        for order in (specs, specs[::-1]):
            clear(r)
            place(r, order)
            redraw_all(r)
            check(r, order)
            pages.append(r.page_bytes(PAGE1))
        assert pages[0] != pages[1], "slot order decides which is in front"


def test_seaweed_is_background(r):
    weeds = [(10, 0, 0, 100, 156), (10, 1, 0, 110, 156), (10, 0, 1, 118, 156)]
    for specs in (weeds, weeds[::-1]):
        clear(r)
        place(r, specs + [(5, 1, 1, 105, 158), (11, 0, 0, 120, 150)])
        bg = fishref.fish_bg(r)
        a = r.addr("FISH_BG")
        r.start_tracking()
        rect = (16, 22, 150, 192)
        rebuild_bg(r, rect)
        r.mem.track = False
        for w in r.writes_outside((0, 0x0800), (0x0D9F, 0x10000)):     # FISH_BG only in the rect
            row, col = divmod(w - a, 40)
            assert 16 <= col < 22 and row + 156 >= 150, hex(w)
        assert not r.writes_outside((0, 0x2000), (0x4000, 0x10000)), "nothing on screen"
        got, want = fishref.fish_bg(r), fishref.expected_bg(r)
        for row in range(36):
            for col in range(40):
                i = row * 40 + col
                assert got[i] == (want[i] if 16 <= col < 22 else bg[i]), (row, col)
        redraw_all(r)
        assert fishref.fish_bg(r) == fishref.expected_bg(r)
        check(r, specs)


def test_budget_stops_between_rows(r):
    specs = [(2, 0, 1, 120, 130), (8, 1, 0, 126, 140), (11, 0, 0, 130, 150)]
    clear(r)
    place(r, specs)
    boxes = [box(r, i)[1] for i in range(3)]
    area = reduce(union, boxes)
    stops = 0
    for c in range(area[0], area[1], 8):
        rect = (c, min(c + 8, area[1]), area[2], area[3])
        set_rect(r, rect)
        r.call("fish_rect_begin")
        r.poke16(r.addr("FR_LEFT"), 1)          # not even one row
        cycles = r.call("fish_rect_rows")
        assert not r.carry() and r.peek(r.addr("FR_ROW")) == rect[2]
        assert r.peek16(r.addr("FR_LEFT")) == 0
        assert cycles <= 16 * r.addr("FC_CALL")
        left = 60
        while True:
            r.poke16(r.addr("FR_LEFT"), left)
            row = r.peek(r.addr("FR_ROW"))
            cycles = r.call("fish_rect_rows", max_cycles=200_000)
            charged = left - r.peek16(r.addr("FR_LEFT"))
            assert 0 <= charged <= left
            assert cycles <= 16 * charged, (cycles, charged)
            if r.carry():
                assert r.peek(r.addr("FR_ROW")) == rect[3]
                break
            stops += 1
            assert row <= r.peek(r.addr("FR_ROW")) < rect[3]
            # a row of three costs more than 60: give it what it needs
            left = 60 if r.peek(r.addr("FR_ROW")) > row else 400
    assert stops > 6
    check(r, "resumed")


def hop_cases(kind):
    """(where, y) the creature's band allows: on open water and over the floor."""
    k = kind_of(kind)
    h = k["ch"]
    return {0: (("sea", 60), ("floor", 182 - h)),
            1: (("sea", 10),),
            2: (("floor", 192 - h - 1),),
            3: (("sea", 156 - h + 4), ("floor", 156 - h + 12)),
            4: (("floor", 192 - h),),
            5: (("sea", 60), ("floor", 152))}[k["role"]]


def hops(kind, y):
    """(old, new) for every frame, shift and direction, turning or not."""
    role = kind_of(kind)["role"]
    for frame in (0, 1):
        for d in ((0,) if role >= ROLE_STILL else (0, 1)):
            for turn in ((0,) if role >= ROLE_STILL else (0, 1)):
                for x in range(40, 47):
                    old = (kind, frame, d, x, y)
                    nd = d ^ turn
                    if role == ROLE_STILL:
                        new = (kind, frame ^ 1, d, x, y)
                    elif role == ROLE_RISE:
                        new = (kind, frame ^ 1, d, x, y - 2)
                    else:
                        new = (kind, frame ^ 1, nd, x + (2 if nd == 0 else -2), y)
                    yield old, new


def shift_of(spec):
    """The shift the contract gives a creature: X mod 7."""
    kind, _, d, x, _ = spec
    k = kind_of(kind)
    mirror = d and k["role"] < ROLE_STILL
    return (x + (k["cw"] - k["bx"] - 7 * k["wb"] if mirror else k["bx"])) % 7


def test_a_lone_hop_fits_a_step(r):
    """One creature's hop: its old box joined with its new one, redrawn by
    fish_rect_begin and fish_rect_rows. A Seaweed's sway (a frame swap) also
    rebuilds FISH_BG under it first; that is shown, not held to the limit."""
    rows = []
    worst = 0
    for kind in range(14):
        for where, y in hop_cases(kind):
            most, bg = (0, None), 0
            for old, new in hops(kind, y):
                clear(r)
                place(r, [old])
                redraw_all(r)
                rect = box(r, 0)[1]
                place(r, [new])
                rect = union(rect, box(r, 0)[1])
                assert rect[1] - rect[0] <= 8
                if kind_of(kind)["role"] == ROLE_STILL:
                    bg = max(bg, rebuild_bg(r, rect))
                cycles, done = redraw(r, rect)
                assert done
                check(r, old, new)
                if cycles > most[0]:
                    most = (cycles, new)
            worst = max(worst, most[0])
            new = most[1]
            facing = "left " if new[2] and kind_of(kind)["role"] < ROLE_STILL else "right"
            rows.append(f"{kind:2} {kind_of(kind)['name']:<20} {where:<6} {most[0]:6}  "
                        f"{facing} shift {shift_of(new)}" + (f"   (FISH_BG first: {bg})" if bg else ""))
    print("\nworst hop redraw, one creature (cycles):\n" + "\n".join(rows))
    assert worst < HOP_LIMIT


def test_rows_never_cost_more_than_they_charge(r):
    """Random scenes of 1-5 creatures, drawn a strip at a time on random
    budgets: no call of fish_rect_rows takes longer than 16 cycles for each
    unit it charges, and the screen comes out right."""
    rnd = random.Random(31)
    kinds = [k for k in range(14) if k != 10]
    for trial in range(120):
        n = rnd.choice((1, 1, 2, 2, 3, 4, 5))
        y0 = rnd.choice((30, 120, 150, 160))
        specs = [(rnd.choice(kinds), rnd.randrange(2), rnd.randrange(2),
                  rnd.randrange(60, 120), y0 + rnd.randrange(-6, 7)) for _ in range(n)]
        if rnd.random() < 0.3:
            specs.insert(rnd.randrange(n + 1), (10, rnd.randrange(2), 0, rnd.randrange(60, 110), 156))
        clear(r)
        place(r, specs)
        for i in range(len(specs)):
            vis, b = box(r, i)
            if vis and specs[i][0] == 10:
                for c in range(b[0], b[1], 8):
                    rebuild_bg(r, (c, min(c + 8, b[1]), b[2], b[3]))
        area = reduce(union, [b for v, b in (box(r, i) for i in range(len(specs))) if v])
        c = area[0]
        while c < area[1]:
            w = rnd.randrange(1, 9)
            rect = (c, min(c + w, area[1]), area[2], area[3])
            c = rect[1]
            set_rect(r, rect)
            r.call("fish_rect_begin")
            while True:
                left = rnd.choice((rnd.randrange(1, 40), rnd.randrange(40, 300), 0xFFFF))
                r.poke16(r.addr("FR_LEFT"), left)
                cycles = r.call("fish_rect_rows", max_cycles=400_000)
                charged = left - r.peek16(r.addr("FR_LEFT"))
                if left >= r.addr("FC_CALL"):
                    assert cycles <= 16 * charged, (specs, rect, left, cycles, charged)
                else:
                    assert cycles <= 16 * r.addr("FC_CALL")
                if r.carry():
                    break
        check(r, specs)


def test_frames_never_cross_a_page(r):
    """The renderer patches one high byte for a frame row's wb source bytes
    (gen_fish.py pads to keep it so)."""
    for k, kind in enumerate(art()["kinds"]):
        for f in (0, 1):
            lit = r.addr(f"fk_frame{k}_{f}")
            for a in (lit, lit + kind["rows"] * kind["wb"]):
                assert (a & 0xFF) + kind["wb"] <= 0x100, (k, f, hex(a))
