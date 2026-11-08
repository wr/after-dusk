"""Generate src/fish_art.inc (Fish!'s creature frames, descriptor tables and sea floor),
build/fish_art.json (the same data, for the tests) and build/fish-preview.png (both frames of
every kind, facing both ways, at 4x, green on black).

The drawings are After Dusk's own, drawn from the real animals (tools/fish/). A creature
frame is a grid of 0 = see-through, 1 = lit, 2 = dark; its mask is every non-see-through dot
grown by one in all 8 directions (kit.mask_of), which gives it a dark outline.

Each kind has one box shared by both frames: the smallest rectangle inside its cell that
holds both frames' masks. A frame is ROWS rows of 5 bytes of lit dots (WB bytes of dots, then
zeros) followed by ROWS rows of 5 bytes of mask (1 = covered), in hi-res byte format (7 dots a
byte, bit 0 leftmost, bit 7 = 0), facing right: every frame 5 bytes wide, which the program
shifts into a 6-byte cache row. The mask is stored un-inverted so that shifting fills with 0;
the program inverts it as it shifts (through its inverted shift table). Facing left, a swimmer
is drawn from a mirrored copy of its frame (every row's 5 bytes bit-reversed and turned round,
whatever its WB) that fish_init builds in aux memory at the addresses in fk_m0*/fk_m1*; the
drawing then sits 35 - BW dots in, so the program places it at x + cw - bx - 35 (fk_xm). The
floor is the bottom 36 screen rows (156..191), 40 bytes each.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tools.fish.creatures import CREATURES  # noqa: E402
from tools.fish.floor import floor  # noqa: E402
from tools.fish.kit import mask_of  # noqa: E402

ROLE_SWIM, ROLE_TOP, ROLE_FLOOR, ROLE_LOW, ROLE_STILL, ROLE_RISE = range(6)
STRIDE = 5                      # bytes a frame row takes: wb <= 5 bytes of dots, then zeros
# Where fish_init puts the mirrored frames (aux memory; config.inc's FISH_MIRA/B): the
# swimmers' frames in kind order, each whole, first into A then into B.
MIRROR_AREAS = ((0xA000, 0xC000), (0x1680, 0x2000))
ROLES = {"JellyFish": ROLE_TOP, "Seahorse": ROLE_TOP, "Crab": ROLE_FLOOR,
         "Globefish": ROLE_LOW, "Seaweed": ROLE_STILL, "Bubbles": ROLE_RISE}


def pack(rows, x0, wb):
    """Rows of 0/1 dots from column x0 into wb bytes each (7 dots a byte, bit 0 leftmost)."""
    out = []
    for r in rows:
        line = []
        for b in range(wb):
            v = 0
            for k in range(7):
                x = x0 + b * 7 + k
                if x < len(r) and r[x]:
                    v |= 1 << k
            line.append(v)
        out.append(line)
    return out


def kinds():
    out = []
    for name, fn in CREATURES:
        canv = [fn(0), fn(1)]
        masks = [mask_of(c) for c in canv]
        cw, ch = canv[0].w, canv[0].h
        xs = [x for m in masks for r in m for x, v in enumerate(r) if v]
        ys = [y for m in masks for y, r in enumerate(m) if any(r)]
        bx, by = min(xs), min(ys)
        bw, bh = max(xs) - bx + 1, max(ys) - by + 1
        # so that fish_hop's old box joined with its new one fits the
        # renderer's 8 bytes
        assert bw <= 48, f"{name}: box {bw} dots wide, past 48"
        wb = -(-bw // 7)
        assert wb <= 5, f"{name}: {wb} bytes wide, past the frame's 5"
        frames = []
        for c, m in zip(canv, masks):
            lit = [[1 if c.p[y][x] == 1 else 0 for x in range(cw)] for y in range(by, by + bh)]
            msk = [m[y] for y in range(by, by + bh)]
            frames.append({"lit": pack(lit, bx, wb), "mask": pack(msk, bx, wb)})
        out.append({"name": name, "cw": cw, "ch": ch, "bx": bx, "by": by, "bw": bw,
                    "rows": bh, "wb": wb, "role": ROLES.get(name, ROLE_SWIM), "frames": frames})
    place_mirrors(out)
    return out


def frame_size(kind):
    return 2 * kind["rows"] * STRIDE


def place_mirrors(ks):
    """Each swimmer's two mirrored frames get aux addresses (kind["mirror"] = [frame 0,
    frame 1]); kinds that never face left point at their plain frames (None)."""
    areas = [list(a) for a in MIRROR_AREAS]
    for k in ks:
        k["mirror"] = [None, None]
        if k["role"] >= ROLE_STILL:
            continue
        for n in (0, 1):
            for area in areas:
                if area[0] + frame_size(k) <= area[1]:
                    k["mirror"][n] = area[0]
                    area[0] += frame_size(k)
                    break
            else:
                raise AssertionError(f"{k['name']}: no room for its mirrored frame {n}")


def floor_bytes():
    rows = floor()
    assert len(rows) == 36 and all(len(r) == 280 for r in rows)
    return pack(rows, 0, 40)


def table(name, values):
    lines = [f"{name}:"]
    for i in range(0, len(values), 16):
        lines.append("        .byte " + ", ".join(f"${v & 0xFF:02X}" for v in values[i:i + 16]))
    return "\n".join(lines)


def frame_bytes(f):
    """Lit rows then mask rows, each row padded to STRIDE bytes."""
    return [b for part in ("lit", "mask") for row in f[part] for b in row + [0] * (STRIDE - len(row))]


def write_inc(ks, fl):
    total = sum(2 * frame_size(k) for k in ks)
    parts = ["; Generated by tools/gen_fish.py. Do not edit.",
             f"FISH_NKIND = {len(ks)}",
             f"FISH_ART_BYTES = {total}",
             f"FISH_STRIDE = {STRIDE}",
             f'.assert FISH_MIRA = ${MIRROR_AREAS[0][0]:04X} && FISH_MIRA_END = ${MIRROR_AREAS[0][1]:04X}, '
             'error, "the mirrored frames were placed for another FISH_MIRA"',
             f'.assert FISH_MIRB = ${MIRROR_AREAS[1][0]:04X} && FISH_MIRB_END = ${MIRROR_AREAS[1][1]:04X}, '
             'error, "the mirrored frames were placed for another FISH_MIRB"',
             '        .segment "FX14"']
    for key in ("cw", "ch", "bx", "by", "bw", "rows", "wb", "role"):
        parts.append(table("fk_" + key, [k[key] for k in ks]))
    parts.append("; the frame's X from the cell's x facing left (cw - bx - 35), and the")
    parts.append("; padding before the drawing then (35 - bw); rows x 5 (a frame's mask from its lit)")
    parts.append(table("fk_xm", [k["cw"] - k["bx"] - 35 for k in ks]))
    parts.append(table("fk_pad", [35 - k["bw"] for k in ks]))
    parts.append(table("fk_r5", [k["rows"] * STRIDE for k in ks]))
    for n in (0, 1):
        parts.append(f"fk_f{n}lo:")
        parts.append("        .byte " + ", ".join(f"<fk_frame{i}_{n}" for i in range(len(ks))))
        parts.append(f"fk_f{n}hi:")
        parts.append("        .byte " + ", ".join(f">fk_frame{i}_{n}" for i in range(len(ks))))
    parts.append("; the mirrored frames, in aux memory (kinds that never face left: their plain frames)")
    for n in (0, 1):
        addrs = [f"${k['mirror'][n]:04X}" if k["mirror"][n] is not None else f"fk_frame{i}_{n}"
                 for i, k in enumerate(ks)]
        parts.append(f"fk_m{n}lo:")
        parts.append("        .byte " + ", ".join(f"<{a}" for a in addrs))
        parts.append(f"fk_m{n}hi:")
        parts.append("        .byte " + ", ".join(f">{a}" for a in addrs))
    parts.append('        .segment "FISHART"')
    for i, k in enumerate(ks):
        parts.append(f"; {k['name']}: cell {k['cw']}x{k['ch']}, box {k['bw']}x{k['rows']} at "
                     f"({k['bx']},{k['by']}), {k['wb']} bytes of dots a row; lit rows then mask rows")
        for n in (0, 1):
            parts.append(table(f"fk_frame{i}_{n}", frame_bytes(k["frames"][n])))
    parts.append('        .segment "FISHFLOOR"')
    parts.append("; sea floor, screen rows 156..191, 40 bytes each")
    parts.append(table("fish_floor", [b for row in fl for b in row]))
    (ROOT / "src/fish_art.inc").write_text("\n".join(parts) + "\n")


def write_json(ks, fl):
    (ROOT / "build").mkdir(exist_ok=True)
    data = {"kinds": ks, "floor": fl}
    (ROOT / "build/fish_art.json").write_text(json.dumps(data, separators=(",", ":")))


def write_preview(ks):
    try:
        from PIL import Image
    except ImportError:
        return
    scale, gap = 4, 6
    cols = 4
    cellw = max(k["cw"] for k in ks)
    cellh = max(k["ch"] for k in ks)
    slot_w, slot_h = (cellw * 2 + gap) , cellh + gap
    # per kind: frame 0 right, frame 1 right, frame 0 left, frame 1 left
    img = Image.new("RGB", (cols * (cellw * 2 + gap) * scale,
                            -(-len(ks) // cols) * 2 * slot_h * scale), (5, 16, 8))
    px = img.load()
    for i, (name, fn) in enumerate(CREATURES):
        for n in (0, 1):
            c = fn(n)
            for mirror in (0, 1):
                ox = ((i % cols) * slot_w + n * cellw // 1) * scale
                oy = ((i // cols) * 2 + mirror) * slot_h * scale
                for y in range(c.h):
                    for x in range(c.w):
                        if c.p[y][x] != 1:
                            continue
                        xx = c.w - 1 - x if mirror else x
                        for dy in range(scale):
                            for dx in range(scale):
                                px[ox + xx * scale + dx, oy + y * scale + dy] = (80, 255, 108)
    img.save(ROOT / "build/fish-preview.png")


def main():
    ks = kinds()
    fl = floor_bytes()
    write_inc(ks, fl)
    write_json(ks, fl)
    write_preview(ks)


if __name__ == "__main__":
    main()
