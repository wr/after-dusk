import pytest

from fxcommon import TICK, OVERHEAD, check_bit7, check_budget, check_in_bounds, start
from sim import PAGE1, ST_TIMING, VblLatch, row_base

FX = 17
COLS, ROWS = 40, 32             # the board: one screen byte wide, 6 dot rows tall
CELL = (0x1C, 0x3E, 0x3E, 0x3E, 0x1C)   # a live cell's five rows (the sixth is blank)
BOARD = 0x4000                  # row r in page $40 + r, cell c at offset c + 1
ALIVE = 0x10                    # bit 4 of a state byte; the low nibble counts neighbours
STILL_LIMIT = 40                # steady for more than this many generations: scatter
MIN_POP = 6                     # fewer cells than this: scatter
SEEDS = (0x4D2A, 0x1357, 0xBEEF)
STEP_LIMIT = 6 * TICK - OVERHEAD


# ---- the board, as the tests see it ----

def board(s):
    """The live cells, as a set of (row, col)."""
    ram = s.mem.ram
    return {(r, c) for r in range(ROWS) for c in range(COLS)
            if ram[BOARD + r * 256 + 1 + c] & ALIVE}


def counts(s):
    """Each cell's neighbour count as the effect keeps it, and the two wrap margins."""
    ram = s.mem.ram
    cells = {(r, c): ram[BOARD + r * 256 + 1 + c] & 0x0F for r in range(ROWS) for c in range(COLS)}
    margins = [(ram[BOARD + r * 256], ram[BOARD + r * 256 + 41]) for r in range(ROWS)]
    return cells, margins


def neighbours(alive):
    """How many live neighbours every cell has, on the torus."""
    n = {}
    for r, c in alive:
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if dr or dc:
                    k = ((r + dr) % ROWS, (c + dc) % COLS)
                    n[k] = n.get(k, 0) + 1
    return n


def next_gen(alive):
    """Conway's rules on the torus."""
    n = neighbours(alive)
    return {k for k, v in n.items() if v == 3 or (v == 2 and k in alive)}


def expected_page(alive):
    """Page 1 as it should look with these cells lit and nothing else."""
    page = bytearray(0x2000)
    for r, c in alive:
        for k, v in enumerate(CELL):
            page[row_base(6 * r + k, PAGE1) - (PAGE1 << 8) + c] = v
    return bytes(page)


def pop(s):
    return s.peek16(s.addr("lf_pop"))


def still(s):
    return s.peek(s.addr("lf_still"))


def prev(s):
    return s.peek16(s.addr("lf_prev"))


def set_board(s, alive):
    """Put a board in place as the effect would have left it after a
    generation: state bytes with counts, clean margins, the picture on page 1,
    and the population counters as if it had just been counted."""
    n = neighbours(alive)
    ram = s.mem.ram
    for r in range(ROWS):
        ram[BOARD + r * 256] = 0
        ram[BOARD + r * 256 + 41] = 0
        for c in range(COLS):
            ram[BOARD + r * 256 + 1 + c] = (ALIVE if (r, c) in alive else 0) | n.get((r, c), 0)
    ram[PAGE1 << 8:(PAGE1 << 8) + 0x2000] = expected_page(alive)
    s.poke16(s.addr("lf_pop"), len(alive))
    s.poke16(s.addr("lf_prev"), len(alive))
    s.poke(s.addr("lf_still"), 0)


def block(r, c):
    return {(r, c), (r, c + 1), (r + 1, c), (r + 1, c + 1)}


def check_consistent(s, alive):
    """The counts and margins are what the board says they should be."""
    cells, margins = counts(s)
    n = neighbours(alive)
    assert cells == {k: n.get(k, 0) for k in cells}
    assert margins == [(0, 0)] * ROWS


@pytest.fixture
def s(built):
    return start(FX)


# ---- budget and bounds ----

def test_budget(built):
    worst, median = check_budget(FX)
    print("worst step", worst, "median", median)


def test_stays_in_bounds(built):
    check_bit7(check_in_bounds(FX))


def test_polls_the_vertical_blank_every_row(s):
    """A step is longer than a frame, so it must poll the blank as it goes:
    once a board row in each of its two passes."""
    s.poke(ST_TIMING, 1)
    latch = VblLatch(s)
    polls = []
    read = latch.read
    s.mem.read_hooks[0xC019] = lambda: polls.append(1) or read()
    s.step()
    assert len(polls) >= 2 * ROWS


# ---- the start ----

def test_starts_with_a_quarter_of_the_cells(built):
    """Each cell comes alive on two random bits both set: a 25% scatter,
    counted into lf_pop."""
    pops = []
    for seed in range(1, 13):
        s = start(FX, seed=seed * 0x2F1)
        alive = board(s)
        assert pop(s) == len(alive)
        assert 250 <= len(alive) <= 390, seed
        pops.append(len(alive))
        assert s.page_bytes() == expected_page(alive)
        check_consistent(s, alive)
        assert still(s) == 0 and prev(s) == 0xFFFF
    assert 300 <= sum(pops) / len(pops) <= 340


def test_scatters_differ_by_seed(built):
    assert board(start(FX, seed=SEEDS[0])) != board(start(FX, seed=SEEDS[1]))


# ---- generations ----

def test_matches_conway(built):
    """Forty generations from three scatters follow Conway's rules on the
    torus, with the neighbour counts kept right as it goes."""
    for seed in SEEDS:
        s = start(FX, seed=seed)
        alive = board(s)
        for n in range(40):
            alive = next_gen(alive)
            s.step()
            assert prev(s) != 0xFFFF, "scattered again"
            assert board(s) == alive, (seed, n)
            assert pop(s) == len(alive)
            check_consistent(s, alive)


def test_picture_matches_board(built):
    """After every step, each cell's five bytes show its state and the
    rest of the page is dark."""
    for seed in SEEDS:
        s = start(FX, seed=seed)
        for n in range(40):
            s.step()
            assert s.page_bytes() == expected_page(board(s)), (seed, n)


def test_counts_steady_generations(s):
    """lf_still counts generations whose population moved by 2 or less;
    lf_prev remembers the last population."""
    alive = block(10, 10) | block(10, 20) | {(20, 10), (20, 11), (20, 12)}   # two blocks, a blinker
    set_board(s, alive)
    for n in range(1, 6):
        s.step()
        assert board(s) == next_gen(alive)
        alive = board(s)
        assert still(s) == n and prev(s) == 11
    # a population 2 away from the last one is still steady; 3 away is not
    set_board(s, alive)
    s.poke16(s.addr("lf_prev"), len(alive) + 2)
    s.poke(s.addr("lf_still"), 5)
    s.step()
    assert still(s) == 6
    set_board(s, board(s))
    s.poke16(s.addr("lf_prev"), len(alive) + 3)
    s.poke(s.addr("lf_still"), 6)
    s.step()
    assert still(s) == 0


# ---- the scatter ----

def test_settles_then_reseeds(s):
    """A board of still lifes keeps its population, so after the limit a new
    scatter replaces it, drawn in one step."""
    alive = block(4, 4) | block(10, 30) | block(20, 12) | block(28, 36)
    set_board(s, alive)
    for n in range(1, STILL_LIMIT + 2):
        s.step()
        assert board(s) == alive
        assert still(s) == n
    assert still(s) == STILL_LIMIT + 1
    cycles = s.step()
    scattered = board(s)
    assert scattered != alive
    assert 250 <= len(scattered) <= 390
    assert pop(s) == len(scattered)
    assert still(s) == 0 and prev(s) == 0xFFFF
    assert s.page_bytes() == expected_page(scattered)
    check_consistent(s, scattered)
    assert cycles < STEP_LIMIT
    # and life goes on from there
    s.step()
    assert board(s) == next_gen(scattered)


def test_reseeds_when_nearly_empty(s):
    alive = block(10, 10)
    set_board(s, alive)
    s.step()
    scattered = board(s)
    assert len(scattered) > 200
    assert s.page_bytes() == expected_page(scattered)
    check_consistent(s, scattered)


def test_reseed_fits(s):
    """The scatter step, from the densest still board there is (every other
    row full, 640 cells), erases and draws its changes inside 6 ticks."""
    alive = {(r, c) for r in range(0, ROWS, 2) for c in range(COLS)}
    assert len(alive) == 640 and next_gen(alive) == alive
    set_board(s, alive)
    s.poke(s.addr("lf_still"), STILL_LIMIT + 1)
    cycles = s.step()
    scattered = board(s)
    assert 250 <= len(scattered) <= 390
    assert s.page_bytes() == expected_page(scattered)
    check_consistent(s, scattered)
    print("reseed step", cycles)
    assert cycles < STEP_LIMIT


def test_full_board_dies_in_one_step(s):
    """Every cell alive: all die at once (8 neighbours each), the picture
    goes dark, and the next step scatters."""
    alive = {(r, c) for r in range(ROWS) for c in range(COLS)}
    set_board(s, alive)
    s.step()
    assert board(s) == set()
    assert s.page_bytes() == bytes(0x2000)
    assert pop(s) == 0
    s.step()
    assert len(board(s)) > 200
