"""What Fish!'s screen must hold, worked out in Python from the memory and data
contract, for the creatures in the simulator's state arrays.

    art = load_art()                    # build/fish_art.json
    assert s.page_bytes() == expected_page(s)
    assert fish_bg(s) == expected_bg(s)

A creature is drawn from its frame (lit rows, then mask rows, facing right).
Facing left (swimmers only: Seaweed and Bubbles never turn), each source row is
read right to left through the bit-reverse table and drawn at
X = x + cw - bx - wb*7; facing right at X = x + bx. Byte column c0 = X // 7,
shift k = X % 7, and output byte i = (src[i] << k) & $7F | src[i-1] >> (7-k).

Every row starts from FISH_BG (rows 156-191) or black, then every slot that
isn't Seaweed, in slot order: screen = (screen AND NOT mask) OR lit. FISH_BG is
the floor with every Seaweed composed onto it the same way, in slot order.

Motion (Global Constraints): Rng is the core's random numbers, so a test can
tell which hop turns; band() is where a spawn may land; hop() is one hop.
"""
import json
from functools import lru_cache

from conftest import BUILD
from sim import PAGE1, row_base

FLOOR_TOP = 156
FLOOR_ROWS = 192 - FLOOR_TOP
ROLE_STILL = 4                  # Seaweed
REV = [int(f"{b:07b}"[::-1], 2) for b in range(128)]


@lru_cache(maxsize=None)
def load_art():
    return json.loads((BUILD / "fish_art.json").read_text())


def signed(v):
    return v - 0x10000 if v & 0x8000 else v


def creatures(s):
    """The slots in use, in slot order, read from the state arrays."""
    def arr(name, i):
        return s.peek(s.addr(name) + i)

    out = []
    for i in range(s.peek(s.addr("fish_n"))):
        out.append({
            "kind": arr("fish_kind", i), "frame": arr("fish_frame", i), "dir": arr("fish_dir", i),
            "x": signed(arr("fish_xl", i) | arr("fish_xh", i) << 8),
            "y": signed(arr("fish_yl", i) | arr("fish_yh", i) << 8),
        })
    return out


def mirrored(c):
    return c["dir"] == 1 and load_art()["kinds"][c["kind"]]["role"] < ROLE_STILL


def placed(c):
    """(top row, first byte column, [(lit, mask) per row]); each row wb+1 bytes."""
    kind = load_art()["kinds"][c["kind"]]
    wb = kind["wb"]
    frame = kind["frames"][c["frame"]]
    if mirrored(c):
        x = c["x"] + kind["cw"] - kind["bx"] - wb * 7
    else:
        x = c["x"] + kind["bx"]
    c0, k = x // 7, x % 7

    def shift(row):
        src = [REV[b] for b in reversed(row)] if mirrored(c) else list(row)
        src = [0] + src + [0]                   # src[-1] and src[wb]
        return [(src[i + 1] << k) & 0x7F | src[i] >> (7 - k) for i in range(wb + 1)]

    rows = [(shift(lit), shift(mask)) for lit, mask in zip(frame["lit"], frame["mask"])]
    return c["y"] + kind["by"], c0, rows


def compose(lines, c, first=0):
    """Draw creature c over lines (a list of 40-byte bytearrays for rows
    first, first+1, ...): line = (line AND NOT mask) OR lit."""
    top, c0, rows = placed(c)
    for r, (lit, mask) in enumerate(rows):
        y = top + r - first
        if not 0 <= y < len(lines):
            continue
        line = lines[y]
        for i in range(len(lit)):
            if 0 <= c0 + i < 40:
                line[c0 + i] = line[c0 + i] & ~mask[i] & 0x7F | lit[i]


def expected_bg(s):
    """FISH_BG: the floor, then every Seaweed in slot order (1,440 bytes)."""
    lines = [bytearray(row) for row in load_art()["floor"]]
    for c in creatures(s):
        if load_art()["kinds"][c["kind"]]["role"] == ROLE_STILL:
            compose(lines, c, FLOOR_TOP)
    return b"".join(bytes(line) for line in lines)


def expected_lines(s):
    """The 192 visible rows of page 1, 40 bytes each."""
    bg = expected_bg(s)
    lines = [bytearray(40) for _ in range(FLOOR_TOP)]
    lines += [bytearray(bg[r * 40:r * 40 + 40]) for r in range(FLOOR_ROWS)]
    for c in creatures(s):
        if load_art()["kinds"][c["kind"]]["role"] != ROLE_STILL:
            compose(lines, c)
    return lines


def expected_page(s):
    """Page 1 (8K) as the composition rule has it. The screen holes (the 8
    bytes after each 120) aren't shown, so they keep what the page holds now."""
    page = bytearray(s.page_bytes(PAGE1))
    for y, line in enumerate(expected_lines(s)):
        a = row_base(y, PAGE1) - (PAGE1 << 8)
        page[a:a + 40] = line
    return bytes(page)


def fish_bg(s):
    a = s.addr("FISH_BG")
    return bytes(s.mem.ram[a:a + FLOOR_ROWS * 40])


# ---------------------------------------------------------------- motion
# How each creature moves, by the Global Constraints (the approved sample).

ROLE_SWIM, ROLE_TOP, ROLE_FLOOR, ROLE_LOW, ROLE_RISE = 0, 1, 2, 3, 5
HOP = 2                         # dots a swimmer moves, rows a Bubble rises (FISH_HOP: 2 or 4)


class Rng:
    """The core's random numbers (src/rng.s): a 16-bit xorshift (7, 9, 8),
    and rng_below's draws under the next power of two, rejecting n or more."""

    def __init__(self, state):
        self.lo, self.hi = state & 0xFF, state >> 8

    def next(self):
        lo, hi = self.lo, self.hi
        a = (hi & 1) << 7 | lo >> 1             # lsr hi; ror lo
        carry = lo & 1
        hi = a ^ hi
        a = carry << 7 | hi >> 1                # ror
        lo = a ^ lo
        hi = lo ^ hi
        self.lo, self.hi = lo, hi
        return lo

    def below(self, n):
        mask = (1 << (n - 1).bit_length()) - 1
        while True:
            v = self.next() & mask
            if v < n:
                return v


def band(kind, anywhere):
    """(ys, xs): where a creature fish_spawn places may have its cell's
    top-left. A newcomer swimmer's xs are its two entries (x = -w heading
    right, 280 heading left)."""
    k = load_art()["kinds"][kind]
    w, h, role = k["cw"], k["ch"], k["role"]
    ys = {ROLE_SWIM: range(2, 182 - h + 1),
          ROLE_TOP: range(0, 31),
          ROLE_FLOOR: range(192 - h - 4, 192 - h),
          ROLE_LOW: range(156 - h + 4, 156 - h + 13),
          ROLE_STILL: range(192 - h, 192 - h + 1),
          ROLE_RISE: range(0, 157) if anywhere else range(152, 153)}[role]
    if role == ROLE_RISE:
        xs = range(4, 280 - w - 4 + 1)
    elif role == ROLE_STILL or anywhere:
        xs = range(0, 280 - w + 1)
    else:
        xs = (-w, 280)
    return ys, xs


def beats(hop=HOP):
    """The swimmers' beats in ticks (Seaweed has none) and Bubbles': they
    scale with the hop, so the speed stays 30 dots a second."""
    return (4 * hop // 2, 5 * hop // 2, 6 * hop // 2), 3 * hop // 2


def hop(c, turn, dots=HOP):
    """(new, gone): creature c (not Seaweed) after one hop of `dots`, and
    whether that takes it off for good (it is then replaced by a newcomer). A
    Bubble rises `dots` rows; the rest turn round if `turn`, then move `dots`
    dots the way they face. Frames swap every hop. Gone: x < -w-dots or
    x > 280+dots, a Bubble y < -h."""
    k = load_art()["kinds"][c["kind"]]
    c = dict(c, frame=c["frame"] ^ 1)
    if k["role"] == ROLE_RISE:
        c["y"] -= dots
        return c, c["y"] < -k["ch"]
    if turn:
        c["dir"] ^= 1
    c["x"] += -dots if c["dir"] else dots
    return c, c["x"] < -k["cw"] - dots or c["x"] > 280 + dots
