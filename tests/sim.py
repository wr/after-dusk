"""Run After Dusk's routines on py65, a 65C02 simulator that counts cycles.

    s = Sim()
    s.set_point(10, 20)                 # PX, PY
    cycles = s.call("plot", zp={PCOL: 1, PAGE: 0x20})
    assert (10, 20) in s.page_pixels(0x20)
"""
from pathlib import Path

from py65.devices.mpu65c02 import MPU

from conftest import BUILD, labels

# Zero page and status addresses (mirror src/config.inc)
PX, PY, PX2, PY2, PCOL, PAGE, RAD = 0x10, 0x12, 0x14, 0x16, 0x18, 0x19, 0x1A
RNG, TICKS, DISP = 0x20, 0x22, 0x24
ST_FX, ST_STARTS, ST_BEAT, ST_TIMING, ST_FAST = 0x0310, 0x0311, 0x0312, 0x0314, 0x0315
SEED = 0x0300
KBD, KBDSTRB = 0xC000, 0xC010
PAGE1, PAGE2 = 0x20, 0x40
FXRAM = (0x0800, 0x2000)

SENTINEL = 0x0200          # return address target; never executed


class SpeakerError(AssertionError):
    pass


RDMAINRAM, RDCARDRAM, WRMAINRAM, WRCARDRAM = 0xC002, 0xC003, 0xC004, 0xC005


class Mem:
    """64K of RAM that refuses the speaker and can record writes, plus the IIc's
    auxiliary 64K: writing $C003/$C005 sends reads/writes of $0200-$BFFF there
    (instruction fetches included), $C002/$C004 sends them back to main."""

    def __init__(self):
        self.ram = bytearray(0x10000)
        self.aux = bytearray(0x10000)
        self.rd_aux = False
        self.wr_aux = False
        self.track = False
        self.written = set()
        self.reads = set()
        self.watch_reads = ()
        self.read_hooks = {}       # address -> function() returning the byte read
        self.write_hooks = {}      # address -> function(value)

    def __getitem__(self, a):
        if 0xC030 <= a <= 0xC03F:
            raise SpeakerError(f"speaker read at ${a:04X}")
        if self.watch_reads and a in self.watch_reads:
            self.reads.add(a)
        if self.read_hooks and a in self.read_hooks:
            return self.read_hooks[a]()
        if self.rd_aux and 0x0200 <= a < 0xC000:
            return self.aux[a]
        return self.ram[a]

    def __setitem__(self, a, v):
        if 0xC030 <= a <= 0xC03F:
            raise SpeakerError(f"speaker write at ${a:04X}")
        if self.write_hooks and a in self.write_hooks:
            self.write_hooks[a](v)
        if RDMAINRAM <= a <= WRCARDRAM:
            if a < WRMAINRAM:
                self.rd_aux = a == RDCARDRAM
            else:
                self.wr_aux = a == WRCARDRAM
            return
        if self.wr_aux and 0x0200 <= a < 0xC000:
            self.aux[a] = v & 0xFF
        else:
            self.ram[a] = v & 0xFF
        if self.track:
            self.written.add(a)

    def __len__(self):
        return 0x10000


def row_base(y, page=PAGE1):
    """Address of the first byte of hi-res row y."""
    return (page << 8) + (y & 7) * 0x400 + ((y >> 3) & 7) * 0x80 + (y >> 6) * 0x28


class Sim:
    def __init__(self, path=None):
        path = Path(path or BUILD / "afterdusk.bin")
        self.mem = Mem()
        self.mpu = MPU(memory=self.mem)
        data = path.read_bytes()
        self.mem.ram[0x6000:0x6000 + len(data)] = data
        self.labels = labels()

    # ---- memory ----
    def peek(self, a):
        return self.mem.ram[a]

    def poke(self, a, v):
        self.mem.ram[a] = v & 0xFF

    def peek16(self, a):
        return self.mem.ram[a] | (self.mem.ram[a + 1] << 8)

    def poke16(self, a, v):
        v &= 0xFFFF
        self.mem.ram[a] = v & 0xFF
        self.mem.ram[a + 1] = v >> 8

    def load_effects(self):
        """As HELLO and start do: the FX file at $2000, copied to aux memory,
        both pages cleared, and the aux copy loop in the language card."""
        data = (BUILD / "fx.bin").read_bytes()
        self.mem.ram[0x2000:0x2000 + len(data)] = data
        self.call("fx_stash", max_cycles=2_000_000)
        self.mem.ram[0x2000:0x6000] = bytes(0x4000)
        self.call("lc_install")
        return self

    def set_point(self, x, y, xa=PX, ya=PY):
        self.poke16(xa, x)
        self.poke16(ya, y)

    def addr(self, name):
        return name if isinstance(name, int) else self.labels[name]

    # ---- running code ----
    def call(self, target, a=0, x=0, y=0, zp=None, max_cycles=5_000_000):
        """Call a routine (label or address) until it returns; returns cycles used."""
        for k, v in (zp or {}).items():
            self.poke(k, v)
        ret = SENTINEL - 1
        self.mem.ram[0x1FF] = ret >> 8
        self.mem.ram[0x1FE] = ret & 0xFF
        mpu = self.mpu
        mpu.sp = 0xFD
        mpu.pc = self.addr(target)
        mpu.a, mpu.x, mpu.y = a, x, y
        mpu.p = 0x34                     # interrupts masked, decimal off
        start = mpu.processorCycles
        while mpu.pc != SENTINEL:
            mpu.step()
            if mpu.processorCycles - start > max_cycles:
                raise TimeoutError(f"{target} ran past {max_cycles} cycles (PC ${mpu.pc:04X})")
        return mpu.processorCycles - start

    def carry(self):
        return bool(self.mpu.p & 1)

    # ---- write tracking ----
    def start_tracking(self):
        self.mem.written = set()
        self.mem.track = True

    def writes_outside(self, *ranges):
        """Addresses written since start_tracking that fall outside every (lo, hi) range."""
        out = [a for a in self.mem.written if not any(lo <= a < hi for lo, hi in ranges)]
        return sorted(out)

    # ---- screen ----
    def page_bytes(self, page=PAGE1):
        """The 8K of a page, as raw memory."""
        base = page << 8
        return bytes(self.mem.ram[base:base + 0x2000])

    def fill_page(self, page, value):
        base = page << 8
        self.mem.ram[base:base + 0x2000] = bytes([value]) * 0x2000

    def page_pixels(self, page=PAGE1):
        """Set of lit (x, y) on a page."""
        lit = set()
        ram = self.mem.ram
        for y in range(192):
            base = row_base(y, page)
            for b in range(40):
                v = ram[base + b]
                if v & 0x7F:
                    for bit in range(7):
                        if v & (1 << bit):
                            lit.add((b * 7 + bit, y))
        return lit

    def set_pixels(self, pixels, page=PAGE1):
        for x, y in pixels:
            a = row_base(y, page) + x // 7
            self.mem.ram[a] |= 1 << (x % 7)


class VblLatch:
    """The IIc's vertical-blank latch, timed by the simulator's cycle count:
    $C019 bit 7 sets at every frame boundary (17,030 cycles) and stays set
    until $C070 is read. stuck_after: once that many frames have passed, the
    latch stops clearing (a broken machine, for the probe's sake)."""

    def __init__(self, sim, stuck_after=None):
        self.sim = sim
        self.cleared = self.frame()
        self.stuck_after = stuck_after
        sim.mem.read_hooks[0xC019] = self.read
        sim.mem.read_hooks[0xC070] = self.clear

    def frame(self):
        return self.sim.mpu.processorCycles // 17030

    def read(self):
        return 0x80 if self.frame() > self.cleared else 0x00

    def clear(self):
        if self.stuck_after is None or self.frame() < self.stuck_after:
            self.cleared = self.frame()
        return 0
