"""Generate src/splash_art.inc: the boot splash's picture as a paint stream, and
its icon row.

The picture comes as 280 x 160 lit dots, each with the step (0-247) at which it
gets painted. The stream plays it back a step at a time, one or more steps for
every sector DOS reads, so the picture draws itself while the disk loads. Dots
are 7 to a byte on the Apple, so steps are bundled STEP_BUNDLE at a time and a
byte may be painted in several pieces (each piece is ORed onto the screen).

Stream records, one after another:
  $80                  end of this step
  $FE                  continue at SPLASH_TAIL ($8000), the rest of the stream
  $FF                  end of the stream
  otherwise a segment: first byte is the column (0-39); bit 6 set means "the next
  row down", otherwise the next byte is the row. Then a byte with the mode in its
  top two bits and the length in the rest, then the data: mode 0 literal (length
  bytes), mode $40 one value repeated, mode $80 two values alternating.

The first part of the stream (paint_head) rides in HELLO, so drawing starts as
soon as HELLO runs. The rest (paint_tail) is the PAINT file, read at $8000 while
the first part plays.

The art is tools/splash_art.json: the picture, each dot's step, and the icons.
"""
import base64
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "tools" / "splash_art.json"
OUT = ROOT / "src" / "splash_art.inc"

W, H = 280, 160
STEP_BUNDLE = 2            # disk-read steps per painted step
SAME_BYTE_GAP = 8          # dots of one byte within this many steps go together
HEAD_BYTES = 1750          # about this much of the stream rides in HELLO
HEAD_COVERS = 0.25         # ... and at least this share of the steps
TAIL_MAX = 0x15E0          # $8000-$95DF
AFTERDUSK_LANDS = 0x800    # AFTERDUSK ends up over the tail's first $800 bytes ...
LANDS_AT = 0.80            # ... and starts reaching them this far through the steps


def decode(art):
    pb = base64.b64decode(art["pic_b64"])
    pic = [(pb[y * 35 + (x >> 3)] >> (7 - (x & 7))) & 1 for y in range(H) for x in range(W)]
    rle = base64.b64decode(art["step_rle_b64"])
    steps = []
    for i in range(0, len(rle), 2):
        steps += [rle[i + 1]] * rle[i]
    assert len(pic) == len(steps) == W * H
    return pic, steps


def fragments(pic, steps):
    """(step, row, column, 7-dot mask), a byte's dots grouped by when they paint."""
    out = []
    for y in range(H):
        for c in range(40):
            dots = sorted((steps[y * W + c * 7 + b] // STEP_BUNDLE, b) for b in range(7) if pic[y * W + c * 7 + b])
            if not dots:
                continue
            group = [dots[0]]
            for d in dots[1:]:
                if d[0] - group[0][0] <= SAME_BYTE_GAP // STEP_BUNDLE:
                    group.append(d)
                else:
                    out.append((group[0][0], y, c, sum(1 << b for _, b in group)))
                    group = [d]
            out.append((group[0][0], y, c, sum(1 << b for _, b in group)))
    return sorted(out)


def encode(frags):
    """The stream as a list of per-step byte strings."""
    last = max(f[0] for f in frags)
    by_step = {s: [] for s in range(last + 1)}
    for f in frags:
        by_step[f[0]].append(f[1:])
    out, cury = [], None
    for s in range(last + 1):
        rec = bytearray()
        items = by_step[s]
        i = 0
        while i < len(items):
            y, c, v = items[i]
            data = [v]
            j = i + 1
            end = c
            while j < len(items) and items[j][0] == y and items[j][1] - end - 1 <= 1:
                data += [0] * (items[j][1] - end - 1) + [items[j][2]]
                end = items[j][1]
                j += 1
            head = bytearray()
            if cury is not None and y == cury + 1:
                head.append(c | 0x40)
            else:
                head += bytes([c, y])
            n = len(data)
            if n >= 4 and all(b == data[0] for b in data):
                body = bytes([0x40 | n, data[0]])
            elif n >= 6 and all(b == data[k % 2] for k, b in enumerate(data)):
                body = bytes([0x80 | n, data[0], data[1]])
            else:
                body = bytes([n]) + bytes(data)
            rec += head + body
            cury = y
            i = j
        rec.append(0x80)
        out.append(bytes(rec))
    return out


def rows(data, per=16):
    return "".join("        .byte " + ",".join(f"${b:02X}" for b in data[i:i + per]) + "\n" for i in range(0, len(data), per))


def icon_bytes(icon):
    assert len(icon) == 14 and all(len(r) == 14 for r in icon)
    out = bytearray()
    for r in icon:
        for start in (0, 7):
            out.append(sum(1 << b for b in range(7) if r[start + b] == "#"))
    return out


def main():
    art = json.loads(ART.read_text())
    pic, steps = decode(art)
    stream = encode(fragments(pic, steps))
    total = sum(map(len, stream))
    head, n, used = bytearray(), 0, 0
    while n < len(stream) and (used < HEAD_BYTES or n < len(stream) * HEAD_COVERS):
        head += stream[n]
        used += len(stream[n])
        n += 1
    tail = b"".join(stream[n:]) + b"\xFF"
    if len(tail) > TAIL_MAX:
        raise SystemExit(f"gen_splash: tail is {len(tail)} bytes, over {TAIL_MAX}")
    played, at = 0, n
    while played < AFTERDUSK_LANDS and at < len(stream):
        played += len(stream[at])
        at += 1
    if at > len(stream) * LANDS_AT:
        raise SystemExit(f"gen_splash: step {at} still needs the part of PAINT that AFTERDUSK overwrites")
    icons = bytearray()
    for icon in art["icons"]:
        icons += icon_bytes(icon)
    OUT.write_text(
        "; generated by tools/gen_splash.py\n"
        f"SPLASH_STEPS = {len(stream)}\n"
        f"SPLASH_ICON_Y = {art['icon_y']}\n"
        '.segment "SPLASH"\n'
        "paint_head:\n" + rows(head) + "        .byte $FE\n"
        "icons:\n" + rows(icons, 14) +
        '.segment "PAINT"\n'
        "paint_tail:\n" + rows(tail)
    )
    print(f"gen_splash: {len(stream)} steps, {total} bytes ({len(head)} in HELLO, {len(tail)} in PAINT), biggest step {max(map(len, stream))}")


if __name__ == "__main__":
    main()
