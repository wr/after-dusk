"""Generate src/art.inc (sprite source data and language-card layout) and
build/art-preview.png (the sprites at 8x, green on black).

The drawings are After Dusk's own winged toaster (three wing positions) and a
slice of toast, the same as in the approved mockup. Each sprite lives in a
cell (40x40 for the toaster, 16x15 for the toast) with pixel values
0 = see-through, 1 = lit, 2 = dark; its mask is every non-see-through pixel
grown by one dot in all 8 directions, which gives every sprite a dark outline.

art.inc also holds, per sprite and shift, each row's span: the first and
one-past-last byte that holds any mask dot, as offsets into the block (H
starts, then H ends), so drawing skips the empty corners.

art.inc holds, per sprite, the unshifted pixels and mask trimmed to the
mask's bounding box, in hi-res byte format (7 dots per byte, bit 0 leftmost,
bit 7 = 0), with BPR bytes per row: enough for any of the 7 shifts. The
program builds the 7 shifted copies into the language card at startup
(see sprite.s); the addresses are fixed here.
"""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

WING_ANGLES = (-108, -62, -14)      # sprite ids 0, 1, 2: wing up, middle, down
LC_START = 0xD000
LC_LIMIT = 0xF000                   # Warp's tables start here (src/config.inc)


def build_sprite(w, h, inside, shade, extra=None):
    pix = [[0] * w for _ in range(h)]

    def ins(x, y):
        return 0 <= x < w and 0 <= y < h and inside(x, y)

    for y in range(h):
        for x in range(w):
            if ins(x, y):
                edge = not ins(x - 1, y) or not ins(x + 1, y) or not ins(x, y - 1) or not ins(x, y + 1)
                pix[y][x] = 1 if edge else shade(x, y)

    def put(x, y, v):
        if 0 <= x < w and 0 <= y < h:
            pix[y][x] = v

    if extra:
        extra(put)
    mask = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            mask[y][x] = int(any(
                0 <= x + dx < w and 0 <= y + dy < h and pix[y + dy][x + dx]
                for dy in (-1, 0, 1) for dx in (-1, 0, 1)))
    return pix, mask


BX0, BX1, BY0, BY1 = 6, 28, 20, 34


def in_body(x, y):
    if x < BX0 or x > BX1 or y < BY0 or y > BY1:
        return False
    r = 3
    cx = min(max(x, BX0 + r), BX1 - r)
    cy = min(max(y, BY0 + r), BY1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 1


def body_shade(x, y):
    if y == BY0 + 1 and (BX0 + 4 <= x <= BX0 + 9 or BX0 + 12 <= x <= BX0 + 17):
        return 2                                     # bread slots
    if x == BX0 + 5 and BY0 + 3 <= y <= BY1 - 6:
        return 2                                     # chrome glint
    if BX1 - 6 <= x <= BX1 - 3 and BY0 + 5 <= y <= BY0 + 6:
        return 2                                     # lever slot
    if y == BY1 - 5:
        return 2                                     # trim line
    if y > BY1 - 5:
        return 1 if (x + y) & 1 else 2               # shaded base
    return 1


def toaster(base):
    def extra(put):
        for fx in (BX0 + 3, BX0 + 4, BX1 - 4, BX1 - 3):
            put(fx, BY1 + 1, 1)                      # feet
        rx, ry, span = 17, BY0 + 1, 62

        def wing_at(x, y):
            dx, dy = x - rx, y - ry
            d = math.hypot(dx, dy)
            if d < 1:
                return 1
            a = (math.degrees(math.atan2(dy, dx)) - base) % 360
            if a > span:
                return 0
            reach = 20 - a * 0.17
            if d > reach:
                return 0
            for k in range(1, 5):
                off = math.radians(a - k * 12.5)
                if d > reach * 0.5 and abs(d * math.sin(off)) < 0.6:
                    return 2
            return 1

        wing = [[wing_at(x, y) for x in range(40)] for y in range(40)]

        def in_wing(x, y):
            return 0 <= x < 40 and 0 <= y < 40 and wing[y][x] > 0

        for y in range(40):
            for x in range(40):
                if in_wing(x, y):
                    put(x, y, wing[y][x])
                elif in_body(x, y) and (in_wing(x - 1, y) or in_wing(x + 1, y)
                                        or in_wing(x, y - 1) or in_wing(x, y + 1)):
                    put(x, y, 2)                     # dark edge where the wing crosses the body

    return build_sprite(40, 40, in_body, body_shade, extra)


def in_bread(x, y):
    return ((1 <= x <= 14 and 6 <= y <= 13)
            or (x - 5) ** 2 + (y - 5.5) ** 2 <= 18
            or (x - 10) ** 2 + (y - 5.5) ** 2 <= 18)


def toast():
    def shade(x, y):
        crust = not in_bread(x - 2, y) or not in_bread(x + 2, y) or not in_bread(x, y - 2) or not in_bread(x, y + 2)
        return 2 if crust else (1 if (x + y) & 1 else 2)
    return build_sprite(16, 15, in_bread, shade)


class Sprite:
    """A trimmed sprite: cell-relative lit/mask dot sets and its packed rows."""

    def __init__(self, pix, mask):
        cells = [(x, y) for y, row in enumerate(mask) for x, v in enumerate(row) if v]
        self.x0 = min(x for x, _ in cells)
        self.y0 = min(y for _, y in cells)
        self.w = max(x for x, _ in cells) - self.x0 + 1
        self.h = max(y for _, y in cells) - self.y0 + 1
        self.bpr = (self.w + 6 + 6) // 7          # room for any shift 0-6
        self.lit = {(x, y) for y, row in enumerate(pix) for x, v in enumerate(row) if v == 1}
        self.mask = set(cells)

    def spans(self, shift):
        """Per row, the first and one-past-last byte holding any mask dot, as
        offsets from the start of the block (row * bpr + byte)."""
        assert self.bpr * self.h <= 256, "a block must be indexable by Y"
        starts, ends = [], []
        m = self.rows(self.mask, shift)
        for r in range(self.h):
            row = m[r * self.bpr:(r + 1) * self.bpr]
            nz = [j for j, b in enumerate(row) if b]
            assert nz, "every row of a trimmed sprite holds some mask"
            starts.append(r * self.bpr + nz[0])
            ends.append(r * self.bpr + nz[-1] + 1)
        return starts, ends

    def rows(self, dots, shift=0):
        """Packed hi-res bytes, BPR per row, for a set of cell dots at a shift."""
        out = []
        for r in range(self.h):
            row = [0] * self.bpr
            for c in range(self.w):
                if (self.x0 + c, self.y0 + r) in dots:
                    p = c + shift
                    row[p // 7] |= 1 << (p % 7)
            out.extend(row)
        return out


def sprites():
    return [Sprite(*toaster(a)) for a in WING_ANGLES] + [Sprite(*toast())]


def layout(sps):
    """Language-card address of each (sprite, shift) pixel block and mask block."""
    addr = LC_START
    pix, msk = [], []
    for sp in sps:
        size = sp.bpr * sp.h
        for _ in range(7):
            pix.append(addr)
            msk.append(addr + size)
            addr += 2 * size
    return pix, msk, addr


def table(name, values):
    lines = [f"{name}:"]
    for i in range(0, len(values), 16):
        lines.append("        .byte " + ", ".join(f"${v & 0xFF:02X}" for v in values[i:i + 16]))
    return "\n".join(lines)


def write_inc(sps):
    pix, msk, end = layout(sps)
    assert end <= LC_LIMIT, f"sprites need ${end:04X}, past ${LC_LIMIT:04X}"
    parts = [
        "; Generated by tools/gen_art.py. Do not edit.",
        f"SPR_COUNT = {len(sps)}",
        f"SPR_LC_END = ${end:04X}",
        table("spr_x0", [s.x0 for s in sps]),
        table("spr_y0", [s.y0 for s in sps]),
        table("spr_h", [s.h for s in sps]),
        table("spr_bpr", [s.bpr for s in sps]),
        table("spr_pix_lo", [a & 0xFF for a in pix]),
        table("spr_pix_hi", [a >> 8 for a in pix]),
        table("spr_msk_lo", [a & 0xFF for a in msk]),
        table("spr_msk_hi", [a >> 8 for a in msk]),
        "spr_src_lo:",
        "        .byte " + ", ".join(f"<spr_src{i}" for i in range(len(sps))),
        "spr_src_hi:",
        "        .byte " + ", ".join(f">spr_src{i}" for i in range(len(sps))),
    ]
    spans = [(i, k) for i in range(len(sps)) for k in range(7)]
    parts.append("spr_spn_lo:")
    parts.append("        .byte " + ", ".join(f"<spr_spn{i}_{k}" for i, k in spans))
    parts.append("spr_spn_hi:")
    parts.append("        .byte " + ", ".join(f">spr_spn{i}_{k}" for i, k in spans))
    for i, k in spans:
        st, en = sps[i].spans(k)
        parts.append(table(f"spr_spn{i}_{k}", st + en))
    for i, s in enumerate(sps):
        parts.append(f"; sprite {i}: {s.w}x{s.h} dots at ({s.x0},{s.y0}) in its cell, {s.bpr} bytes per row")
        parts.append(table(f"spr_src{i}", s.rows(s.lit) + s.rows(s.mask)))
    (ROOT / "src/art.inc").write_text("\n".join(parts) + "\n")


def write_preview(sps):
    try:
        from PIL import Image
    except ImportError:
        return
    scale, cell, gap = 8, 40, 4
    img = Image.new("RGB", ((cell + gap) * len(sps) * scale, cell * scale), (5, 16, 8))
    px = img.load()
    for i, s in enumerate(sps):
        ox = i * (cell + gap) * scale
        for (x, y) in s.lit:
            for dy in range(scale):
                for dx in range(scale):
                    px[ox + x * scale + dx, y * scale + dy] = (80, 255, 108)
    (ROOT / "build").mkdir(exist_ok=True)
    img.save(ROOT / "build/art-preview.png")


def main():
    sps = sprites()
    write_inc(sps)
    write_preview(sps)


if __name__ == "__main__":
    main()
