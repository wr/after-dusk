"""Generate src/art.inc (Flying Toasters' sprite source data and language-card
layout) and build/art-preview.png (the sprites at 8x, green on black).

The drawings come from tools/toasters.py: the toaster's four wing positions
(sprite ids 0-3, wings highest to lowest, each in a 41x40 cell) and the slice
of toast (id 4, 31x23). Dots are 0 see-through, 1 lit, 2 dark; the mask is
every drawn dot grown by one in all 8 directions (tools.fish.kit.mask_of).

Per sprite, art.inc holds the box (the smallest rectangle holding the mask) as
spr_x0/spr_y0/spr_h/spr_wb, the unshifted lit and mask rows in hi-res byte
format (7 dots a byte, bit 0 leftmost, bit 7 = 0), and a row descriptor per
box row: a, e, fa, fe (dots from the box's left edge, half-open) where
[a, e) spans the row's covered dots and [fa, fe) is its longest covered run.

At start-up sprite.s builds, for every (sprite, shift) pair, a packed block in
the language card at spr_blk[i*7+k]: rows top to bottom with no gaps; a row
holds, for each byte column c0..c1 (c0 = (a+k) div 7, c1 = (e-1+k) div 7), one
byte (lit) when the column is solid (s0 <= c < s1, s0 = (fa+k+6) div 7,
s1 = (fe+k) div 7: every dot covered) and otherwise two (lit, then the
AND-mask ~mask & $7F). When the effect starts, sprite_tables works each
row's byte columns out from the row descriptors into row tables in FXRAM at
ROWTAB (per block: c0, s0, s1 and c1+1 for every row, s0 = s1 = c1+1 when
the row has no solid byte), so drawing only looks them up.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tools.fish.kit import mask_of  # noqa: E402
from tools.toasters import toast, toaster  # noqa: E402

LC_START = 0xD000
LC_LIMIT = 0xF000                   # Warp's tables start here (src/config.inc)
ROWTAB = 0x1100                     # row tables in FXRAM, built when the effect starts
FXRAM_END = 0x2000


def div7(n):
    return n // 7


class Sprite:
    """A sprite trimmed to its mask's box: cell-relative lit/mask dot sets,
    its row descriptors and its packed blocks."""

    def __init__(self, pix, mask):
        cells = [(x, y) for y, row in enumerate(mask) for x, v in enumerate(row) if v]
        self.x0 = min(x for x, _ in cells)
        self.y0 = min(y for _, y in cells)
        self.w = max(x for x, _ in cells) - self.x0 + 1
        self.h = max(y for _, y in cells) - self.y0 + 1
        self.wb = (self.w + 6) // 7          # source bytes per row
        self.lit = {(x, y) for y, row in enumerate(pix) for x, v in enumerate(row) if v == 1}
        self.mask = set(cells)

    @classmethod
    def from_canvas(cls, c):
        return cls(c.p, mask_of(c))

    def row_dots(self, dots, r):
        """Box-relative x of every dot of `dots` in box row r."""
        return sorted(x - self.x0 for (x, y) in dots if y == self.y0 + r)

    def rows_desc(self):
        out = []
        for r in range(self.h):
            xs = self.row_dots(self.mask, r)
            assert xs, "every row of a trimmed sprite holds some mask"
            a, e = xs[0], xs[-1] + 1
            best = (0, 0)
            start = xs[0]
            for i in range(1, len(xs) + 1):
                if i == len(xs) or xs[i] != xs[i - 1] + 1:
                    if xs[i - 1] + 1 - start > best[1] - best[0]:
                        best = (start, xs[i - 1] + 1)
                    if i < len(xs):
                        start = xs[i]
            out.append((a, e, best[0], best[1]))
        return out

    def columns(self, k):
        """Per row at shift k: (c0, s0, s1, ce) byte columns, s0 = s1 = ce
        when the row has no solid byte."""
        out = []
        for a, e, fa, fe in self.rows_desc():
            c0, c1 = div7(a + k), div7(e - 1 + k)
            s0, s1 = div7(fa + k + 6), div7(fe + k)
            ce = c1 + 1
            if s0 >= s1:
                s0 = s1 = ce
            out.append((c0, s0, s1, ce))
        return out

    def row_bytes(self, dots, r, k):
        """Hi-res bytes of box row r of `dots` shifted right k dots, wb+1 bytes."""
        row = [0] * (self.wb + 1)
        for x in self.row_dots(dots, r):
            p = x + k
            row[p // 7] |= 1 << (p % 7)
        return row

    def packed(self, k):
        out = []
        for r, (c0, s0, s1, ce) in enumerate(self.columns(k)):
            lit = self.row_bytes(self.lit, r, k)
            msk = self.row_bytes(self.mask, r, k)
            for c in range(c0, ce):
                out.append(lit[c])
                if not s0 <= c < s1:
                    out.append(~msk[c] & 0x7F)
        return out

    def source(self):
        """The unshifted rows: h x wb lit bytes, then h x wb mask bytes."""
        lit = [b for r in range(self.h) for b in self.row_bytes(self.lit, r, 0)[:self.wb]]
        msk = [b for r in range(self.h) for b in self.row_bytes(self.mask, r, 0)[:self.wb]]
        return lit + msk


def sprites():
    return [Sprite.from_canvas(toaster(k)) for k in range(4)] + [Sprite.from_canvas(toast(0))]


def layout(sps):
    """Language-card address of each (sprite, shift) packed block, and the end
    of the last one."""
    addr = LC_START
    blk = []
    for sp in sps:
        for k in range(7):
            blk.append(addr)
            addr += len(sp.packed(k))
    return blk, addr


def row_tables(sps):
    """FXRAM address of each (sprite, shift) row table: four arrays of h
    bytes (c0, s0, s1, c1+1 per row), one after another."""
    addr = ROWTAB
    out = []
    for sp in sps:
        for _ in range(7):
            out.append(addr)
            addr += 4 * sp.h
    assert addr <= FXRAM_END, f"row tables need ${addr:04X}, past ${FXRAM_END:04X}"
    return out


def table(name, values):
    lines = [f"{name}:"]
    for i in range(0, len(values), 16):
        lines.append("        .byte " + ", ".join(f"${v & 0xFF:02X}" for v in values[i:i + 16]))
    return "\n".join(lines)


def write_inc(sps):
    blk, end = layout(sps)
    rows = row_tables(sps)
    assert end <= LC_LIMIT, f"sprites need ${end:04X}, past ${LC_LIMIT:04X}"
    for sp in sps:
        assert sp.wb + 1 <= 7 and sp.h <= 64
    n = len(sps)
    parts = [
        "; Generated by tools/gen_art.py. Do not edit.",
        f"SPR_COUNT = {n}",
        f"SPR_LC_END = ${end:04X}",
        table("spr_x0", [s.x0 for s in sps]),
        table("spr_y0", [s.y0 for s in sps]),
        table("spr_h", [s.h for s in sps]),
        table("spr_wb", [s.wb for s in sps]),
        table("spr_blk_lo", [a & 0xFF for a in blk]),
        table("spr_blk_hi", [a >> 8 for a in blk]),
        f"SPR_ROWTAB = ${ROWTAB:04X}",
        table("spr_row_lo", [a & 0xFF for a in rows]),
        table("spr_row_hi", [a >> 8 for a in rows]),
        "spr_src_lo:",
        "        .byte " + ", ".join(f"<spr_src{i}" for i in range(n)),
        "spr_src_hi:",
        "        .byte " + ", ".join(f">spr_src{i}" for i in range(n)),
    ]
    # Row descriptors, one array per sprite and field, indexed by box row:
    # a, e - 1, fa + 6 and fe, so that each div 7 (plus k) gives c0, c1, s0, s1.
    for field in ("a", "e1", "fa6", "fe"):
        parts.append(f"spr_{field}_lo:")
        parts.append("        .byte " + ", ".join(f"<spr_{field}{i}" for i in range(n)))
        parts.append(f"spr_{field}_hi:")
        parts.append("        .byte " + ", ".join(f">spr_{field}{i}" for i in range(n)))
    for i, s in enumerate(sps):
        desc = s.rows_desc()
        parts.append(table(f"spr_a{i}", [a for a, e, fa, fe in desc]))
        parts.append(table(f"spr_e1{i}", [e - 1 for a, e, fa, fe in desc]))
        parts.append(table(f"spr_fa6{i}", [fa + 6 for a, e, fa, fe in desc]))
        parts.append(table(f"spr_fe{i}", [fe for a, e, fa, fe in desc]))
    for i, s in enumerate(sps):
        parts.append(f"; sprite {i}: {s.w}x{s.h} dots at ({s.x0},{s.y0}) in its cell, {s.wb} bytes per row")
        parts.append(table(f"spr_src{i}", s.source()))
    (ROOT / "src/art.inc").write_text("\n".join(parts) + "\n")


def write_preview(sps):
    try:
        from PIL import Image
    except ImportError:
        return
    scale, cell, gap = 8, 41, 4
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
