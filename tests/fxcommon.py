"""Shared checks for the effects."""
from conftest import BUILD
from sim import PAGE1, PAGE2, ST_FX, ST_TIMING, Sim

NFX = 15                        # effects (fx_count)
OVL = 0x8800                    # the overlay slot: jmp init, jmp step

# Writes an effect may make: drawing scratch, RNG and core scratch, DISP,
# sprite engine, its own zero page, the extra drawing scratch, the stack,
# the status block, FXRAM, both screen pages, and display soft switches.
ALLOWED = [
    (0x10, 0x20), (0x20, 0x30), (0x30, 0x40), (0x40, 0x80), (0x80, 0x90), (0x90, 0xA0),
    (0x100, 0x200), (0x0310, 0x0320), (0x0800, 0x2000), (0x2000, 0x6000),
    (0xC050, 0xC058),
]
# Fish! alone may also write the language card's spare area after the copy
# loops (its drawing code lives there), and these aux areas (its tables and
# mirrored art): never FX and FX2 ($2000-$9FFF), which every effect's next
# run loads from. No other effect writes aux memory at all.
FISH_ALLOWED = [(0xF700, 0xFFFA)]
FISH_ALLOWED_AUX = [(0x0800, 0x2000), (0xA000, 0xC000)]



def fx_entry(s, fx):
    base = s.addr("fx_table") + fx * 6
    return OVL, OVL + 3, s.peek(base + 4), s.peek(base + 5)


def start(fx, seed=0x4D2A, prepare=None, build=None):
    """A Sim set up as After Dusk is after start-up (effects in aux memory,
    sprites and tables built), with effect `fx` loaded and initialised as the
    randomizer would. `build` is the build directory (default: build/)."""
    s = Sim(build=build or BUILD).load_effects()
    s.poke(ST_TIMING, 0)
    s.mem.ram[0xFFFA:0x10000] = bytes(6)
    s.call("sprite_setup", max_cycles=3_000_000)
    s.call("make_tables", max_cycles=200_000)
    s.call("load_fx", a=fx)
    s.poke16(0x20, seed)
    s.poke(ST_FX, fx)
    init, step, wipe, _ = fx_entry(s, fx)
    if prepare:
        prepare(s)
    if wipe:
        s.call("wipe_to_black", max_cycles=2_000_000)
    s.call("show_page1")
    s.call(init, max_cycles=3_000_000)
    s.step = lambda: s.call(step, max_cycles=1_000_000)
    return s


def run(s, n):
    """Run n steps; returns the worst step's cycles."""
    return max(s.step() for _ in range(n))


TICK = 17030
OVERHEAD = 300          # the randomizer's own work per step, plus the tick wait


def check_budget(fx, steps=300, seeds=(0x4D2A, 0x1357, 0xBEEF), build=None):
    """Every step must finish inside its ticks (so the IIc never slips a frame),
    and the typical step must stay under the 85% budget, leaving headroom."""
    s = start(fx, build=build)
    ticks = fx_entry(s, fx)[3]
    hard = ticks * TICK - OVERHEAD
    cycles = []
    for seed in seeds:
        s = start(fx, seed=seed, build=build)
        cycles += [s.step() for _ in range(steps)]
    worst = max(cycles)
    median = sorted(cycles)[len(cycles) // 2]
    assert worst < hard, f"worst step {worst} cycles; {ticks} ticks allow {hard}"
    budget = ticks * TICK * 0.85
    assert median < budget, f"median step {median} cycles; budget {budget:.0f}"
    return worst, median


def check_in_bounds(fx, steps=300, build=None, extra=(), extra_aux=()):
    """The effect writes only ALLOWED (and `extra`, an effect's own areas), and
    nothing to aux memory outside `extra_aux`."""
    s = start(fx, build=build)
    s.start_tracking()
    run(s, steps)
    assert s.writes_outside(*ALLOWED, *extra) == []
    assert s.aux_writes_outside(*extra_aux) == []
    return s


def check_bit7(s):
    for page in (PAGE1, PAGE2):
        assert all(b & 0x80 == 0 for b in s.page_bytes(page)), f"bit 7 set on page ${page:02X}"
