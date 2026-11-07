"""Drawing kit for After Dusk's own Fish! creatures, original drawings made from the real animals.

A creature frame is a grid of 0 = see-through, 1 = lit (white), 2 = dark (black, but opaque).
The mask is every non-see-through dot grown by one in all 8 directions (a dark outline), the
same rule as tools/gen_art.py. Creatures are drawn facing right; the program mirrors them.
"""
import math
from PIL import Image, ImageDraw

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.p = [[0] * w for _ in range(h)]

    def get(self, x, y):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.p[y][x]
        return 0

    def put(self, x, y, v):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.p[y][x] = v

    # --- shapes, tested at dot centres ---
    def fill(self, inside, v=1):
        for y in range(self.h):
            for x in range(self.w):
                if inside(x + 0.5, y + 0.5):
                    self.p[y][x] = v if not callable(v) else v(x, y)

    def recolor(self, inside, v):
        """Change dots already drawn (non-zero) inside a region."""
        for y in range(self.h):
            for x in range(self.w):
                if self.p[y][x] and inside(x + 0.5, y + 0.5):
                    self.p[y][x] = v if not callable(v) else v(x, y)

    def line(self, x0, y0, x1, y1, v=2):
        x0, y0, x1, y1 = map(lambda a: int(round(a)), (x0, y0, x1, y1))
        dx, sx = abs(x1 - x0), (1 if x0 < x1 else -1)
        dy, sy = -abs(y1 - y0), (1 if y0 < y1 else -1)
        e = dx + dy
        while True:
            self.put(x0, y0, v)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * e
            if e2 >= dy:
                e += dy; x0 += sx
            if e2 <= dx:
                e += dx; y0 += sy

    def polyline(self, pts, v=2):
        for a, b in zip(pts, pts[1:]):
            self.line(*a, *b, v)

    def curve(self, f, t0, t1, n, v=2):
        pts = [f(t0 + (t1 - t0) * i / n) for i in range(n + 1)]
        self.polyline(pts, v)

    def outline_edges(self, v=1, only=None):
        """Dots on the edge of the drawn shape (next to see-through) set to v."""
        q = [row[:] for row in self.p]
        for y in range(self.h):
            for x in range(self.w):
                if self.p[y][x] and (only is None or only(x, y)):
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if not (0 <= xx < self.w and 0 <= yy < self.h) or not self.p[yy][xx]:
                            q[y][x] = v
                            break
        self.p = q

    def copy(self):
        c = Canvas(self.w, self.h)
        c.p = [row[:] for row in self.p]
        return c


def poly_inside(pts):
    def inside(x, y):
        c = False
        n = len(pts)
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            if (y0 > y) != (y1 > y):
                xi = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
                if x < xi:
                    c = not c
        return c
    return inside


def ellipse_inside(cx, cy, rx, ry, rot=0.0):
    ca, sa = math.cos(rot), math.sin(rot)
    def inside(x, y):
        dx, dy = x - cx, y - cy
        u, v = dx * ca + dy * sa, -dx * sa + dy * ca
        return (u / rx) ** 2 + (v / ry) ** 2 <= 1
    return inside


def union(*fs):
    return lambda x, y: any(f(x, y) for f in fs)


def minus(a, b):
    return lambda x, y: a(x, y) and not b(x, y)


def dither(level):
    """level 0..16 of dark dots, ordered 4x4 (absolute grid). Returns v(x, y): 2 dark, 1 lit."""
    return lambda x, y: 2 if BAYER[y & 3][x & 3] < level else 1


def bez(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def mask_of(c):
    m = [[0] * c.w for _ in range(c.h)]
    for y in range(c.h):
        for x in range(c.w):
            m[y][x] = int(any(0 <= x + dx < c.w and 0 <= y + dy < c.h and c.p[y + dy][x + dx]
                              for dy in (-1, 0, 1) for dx in (-1, 0, 1)))
    return m


def render(c, scale, bg=(0, 0, 0), lit=(120, 255, 140), dark=(0, 0, 0), maskcol=None, mirror=False):
    im = Image.new('RGB', (c.w * scale, c.h * scale), bg)
    d = ImageDraw.Draw(im)
    m = mask_of(c)
    for y in range(c.h):
        for x in range(c.w):
            xx = c.w - 1 - x if mirror else x
            v = c.p[y][x]
            col = lit if v == 1 else (dark if v == 2 else (maskcol if (maskcol and m[y][x]) else None))
            if col:
                d.rectangle([xx * scale, y * scale, xx * scale + scale - 1, y * scale + scale - 1], fill=col)
    return im


def dots(step_x, step_y, off=0):
    """Sparse dot shading: a dark dot every step_x across, rows every step_y, staggered."""
    def v(x, y):
        if y % step_y:
            return 1
        sh = (y // step_y) * (step_x // 2) + off
        return 2 if (x + sh) % step_x == 0 else 1
    return v


def checker(x, y):
    return 2 if (x + y) & 1 else 1


def finish(c, keep_dark_edges=None):
    """Make every edge dot of the silhouette lit, so the shape reads against the black sea."""
    c.outline_edges(1, only=(lambda x, y: not keep_dark_edges(x, y)) if keep_dark_edges else None)
    return c
