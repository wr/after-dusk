"""After Dusk's Flying Toasters in isometric: a winged chrome pop-up toaster (four wing
frames) and a slice of toast, seen from above with 2:1 edges. Original drawings from a real
1950s toaster, bird wings and a slice of bread.

The toaster's long axis lies along its flight line (1 down for every 2 left), front end
toward the lower left. Three faces show: the top (slots running lengthwise), the front end
(lower left) and the long side (lower right). Isometric coordinates (a, b, v): a forward
along the body from its back corner, b across it toward the near side, v up.
"""
import math
from tools.fish.kit import *


# ---------------------------------------------------------------- the box
# Hand-placed pixel isometric: every edge is a regular 2:1 staircase (2 across, 1 down).
# The top face is a diamond whose top corner is the two dots at (XB, YT), (XB + 1, YT); it
# steps down-left L rows to the front-left corner and down-right W rows to the back-right
# corner. The two vertical faces hang H rows below the diamond's lower edges.
XB, YT = 21, 10
L, W, H = 9, 5, 10


def top_edge_y(x):
    """y of the diamond's upper edge at column x (x in XB-2L .. XB+1+2W)."""
    return YT + (XB - x + 1) // 2 if x <= XB else YT + (x - XB - 1) // 2


def bottom_edge_y(x):
    """y of the diamond's lower edge at column x: the top of the vertical faces."""
    xl = XB - 2 * L                          # front-left corner column
    xc = XB - 2 * L + 2 * (W + L - L)        # not used
    if x <= XB - 2 * L + 2 * W:              # front face: from the left corner down to the bottom corner
        return YT + L + (x - xl) // 2
    return YT + W + (XB + 1 + 2 * W - x) // 2


X0, X1 = XB - 2 * L, XB + 1 + 2 * W          # the box's leftmost and rightmost columns
XC = XB - 2 * L + 2 * W + 1                  # the first column of the long side (the corner's right dot)


def in_box(x, y):
    x, y = int(x), int(y)
    return X0 <= x <= X1 and top_edge_y(x) <= y <= bottom_edge_y(x) + H


def in_top(x, y):
    x, y = int(x), int(y)
    return X0 <= x <= X1 and top_edge_y(x) <= y < bottom_edge_y(x)


def in_front(x, y):
    x, y = int(x), int(y)
    return X0 <= x < XC - 1 and bottom_edge_y(x) <= y <= bottom_edge_y(x) + H


def in_side(x, y):
    x, y = int(x), int(y)
    return XC - 1 <= x <= X1 and bottom_edge_y(x) <= y <= bottom_edge_y(x) + H


FEET = [(X0 + 1, bottom_edge_y(X0 + 1) + H + 1), (XC - 1, bottom_edge_y(XC - 1) + H + 1),
        (X1 - 2, bottom_edge_y(X1 - 2) + H + 1)]
LEVER_Y = bottom_edge_y(X0) + 7


def in_extras(x, y):
    x, y = int(x), int(y)
    for (fx, fy) in FEET:
        if fx <= x <= fx + 1 and fy <= y <= fy + 1:
            return True
    return X0 - 2 <= x < X0 and LEVER_Y <= y <= LEVER_Y + 1          # the lever's knob


BODY = lambda x, y: in_box(x, y) or in_extras(x, y)
TOP, SIDE, FRONT = in_top, in_side, in_front


def stair(c, x0, y0, n, v, thick=1):
    """A 2:1 staircase down-left from (x0, y0): n rows of two dots each."""
    for i in range(n):
        for t in range(thick):
            c.put(x0 - 2 * i, y0 + i + t, v)
            c.put(x0 - 2 * i - 1, y0 + i + t, v)


def body_shade(x, y):
    if in_top(x, y):
        return 1                                            # brightest
    if in_side(x, y):
        d = y - bottom_edge_y(int(x))                       # rows below the top edge
        return 1 if d == 3 else 2                           # dark, with one chrome highlight line
    if in_front(x, y):
        return checker(x, y)                                # darkest
    return 1


def body_detail(c):
    # slots: two dark parallelograms running lengthwise along the top
    for b in (1, 3):
        stair(c, XB + 2 * b - 2, YT + b + 2, 6, 2, thick=2)
    # one clean dark line where the top meets each vertical face
    for x in range(X0, X1 + 1):
        c.put(x, bottom_edge_y(x), 2)
    # the front corner: a straight lit column between the two shaded faces
    for y in range(bottom_edge_y(XC - 1) + 1, bottom_edge_y(XC - 1) + H + 1):
        c.put(XC - 1, y, 1)
    # the lever's track up the front end, ending at the knob
    for y in range(LEVER_Y - 4, LEVER_Y + 1):
        c.put(X0 + 1, y, 1)


# ---------------------------------------------------------------- wings
# The near wing is drawn once in its own coordinates (u along the span from the root, v
# across it, trailing edge at +v) like a gull's wing seen from above: a broad rounded
# shoulder, a long smooth leading edge out to a rounded wrist two-thirds of the way, long
# primaries forming a tapered rounded tip, and a trailing edge that sweeps back to the root
# as a row of rounded feather ends. Each frame turns the same outline about its root on
# screen (like a rigid cutout) and scales v to foreshorten it: thin as it passes level
# (frame 1), and once down (2, 3) a long blade seen more edge-on, about half to two thirds
# as thick as when raised. It is rooted on the near side face at (22, 25) and points right.
# Frames play back and forth, 0 1 2 3 2 1.
#
# Inside the outline the wing is lit, with dark feather marks drawn everywhere on it (in
# front of the body too; a two-dot dark seam already parts it from the body):
# - the wing's rounded inner end at the root: a one-dot dark curve hugging the shoulder
#   outline one lit dot inside it, like a "(" from the leading edge round to the trailing
#   edge, open toward the tip, with only that one-dot lit rim between it and the seam (a dot
#   that would touch the outside steps one dot in, or goes). In frame 0 it runs down the
#   inner side and hooks round at the bottom, where the shoulder ends and the feathers
#   begin; in frames 1 to 3 it is a short rounded hook;
# - in the raised frames three rows along the span through the outer two thirds (frame 0),
#   three dots apart and drawn as dashes of four dots with one-dot gaps, so they read as
#   divisions between long feathers without turning the wing grey; frame 1 is seen nearly
#   edge-on and gets two rows, one near each edge;
# - in the lowered frames (2, 3) the feathers are seen more from below: one row of short
#   slanted dashes across the thin band, three dots apart along it, each running out to the
#   trailing edge;
# - a ragged edge: where a division meets the tip or the trailing edge, and in the dips
#   between the rounded feather ends, the edge dot is dark (a one-dot notch that the final
#   finish leaves alone), so the tip reads as separate feather ends. The silhouette does not
#   change.
#
# The far wing is the other wing's rounded top showing above the far edge of the top face,
# like the top of a mitten, drawn per frame as a dome whose base runs along that edge (the
# rest is behind the body): frame 0 a broad dome, highest a little toward the back, its
# back side steeper; frame 1 the same wing lower, a low dome; frames 2 and 3 nothing shows.
# It is shaded lit with sparse dark dots (further off than the near wing), with the seam
# where it meets the body and a lit outline round the rest.
A_VEC = (-2.0, 1.0)                             # one unit forward along the body (the toast uses these)
B_VEC = (2.0, 1.0)                              # one unit across, toward the near side
ROOT_NEAR = (22.0, 25.0)
# per frame: (degrees, tip up positive; width scale v; overall scale)
NEAR_POSES = [(34, 1.0, 1.0), (13, 0.55, 1.0), (-8, 0.56, 1.0), (-47, 0.67, 1.0)]
V_SHIFT = 2.0        # the root pivot sits 2 rows above the chord's middle, so the raised
                     # wing's shoulder stays below the back slot while the lowered wing's
                     # feathers reach the bottom margin


def wing_outline():
    """The wing pointing right in (u, v): outline and feather ellipses (cu, cv, ru, rv)."""
    P = []
    P += bez((0, -6.0), (4, -6.6), (8, -5.6), (10.5, -4.6), 10)          # leading edge to the wrist
    P += bez((10.5, -4.6), (13, -3.6), (15.3, -2.0), (16.0, -0.8), 8)    # the hand
    P += bez((16.0, -0.8), (16.7, 0.2), (16.3, 1.2), (15.5, 1.6), 6)     # rounded tip
    P += bez((15.5, 1.6), (12.5, 3.2), (8, 5.0), (4, 5.9), 10)           # trailing edge: primaries, secondaries
    P += bez((4, 5.9), (1.2, 6.3), (-0.9, 4.0), (-0.9, 0.2), 6)          # the shoulder
    P += bez((-0.9, 0.2), (-0.9, -3.2), (-0.6, -5.6), (0, -6.0), 4)
    feathers = [(14.0, 2.3, 1.3, 0.9), (11.7, 3.5, 1.3, 0.9), (9.3, 4.5, 1.3, 0.9),      # primaries
                (6.7, 5.3, 1.3, 0.8), (4.0, 5.9, 1.3, 0.8)]                             # secondaries
    return P, feathers


def trailing_v(P, u):
    """v of the trailing edge (the outline's greatest v) at span position u."""
    best = None
    n = len(P)
    for i in range(n):
        (u0, v0), (u1, v1) = P[i], P[(i + 1) % n]
        if (u0 <= u) != (u1 <= u) and u0 != u1:
            v = v0 + (u - u0) * (v1 - v0) / (u1 - u0)
            best = v if best is None else max(best, v)
    return best


def shoulder_curve(w, inset=(1.5, 2.0)):
    """The wing's rounded inner end: the shoulder outline (trailing edge round to the leading
    edge) moved inward on screen by inset dots (along the span, across it), with the frame's
    v scale w taken into account, then smoothed so the tight corners do not loop."""
    pts = (bez((4.5, 5.85), (1.2, 6.3), (-0.9, 4.0), (-0.9, 0.2), 8) +
           bez((-0.9, 0.2), (-0.9, -3.2), (-0.6, -5.6), (0, -6.0), 6)[1:] + [(2.0, -6.3)])
    sp = [(u, v * w) for (u, v) in pts]                      # as on screen (before rotation)
    out = []
    for i, (x, y) in enumerate(sp):
        (x0, y0), (x1, y1) = sp[max(i - 1, 0)], sp[min(i + 1, len(sp) - 1)]
        tx, ty = x1 - x0, y1 - y0
        n = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / n, tx / n
        if nx * (7.0 - x) + ny * (0.0 - y) < 0:            # point the normal into the wing
            nx, ny = -nx, -ny
        out.append((x + inset[0] * nx, y + inset[1] * ny))
    for _ in range(2):
        out = [out[0]] + [((a[0] + b[0] + c[0]) / 3, (a[1] + b[1] + c[1]) / 3)
                          for a, b, c in zip(out, out[1:], out[2:])] + [out[-1]]
    return [(x, y / w) for (x, y) in out]


def wing_marks(frame):
    """The dark marks inside the wing in (u, v): a list of (points, kind) with kind 'solid'
    (a dark line), 'curl' (a dark line that keeps a lit dot between itself and anything
    outside the wing), 'broken' (dashes, ending in a notch where it leaves the wing), 'dash'
    (a short line ending in a notch) or 'notch' (only the edge dot where the line leaves)."""
    P, _ = wing_outline()
    w = NEAR_POSES[frame][1]
    marks = [(shoulder_curve(w), 'curl')]       # the rounded inner end, a "(" open toward the tip
    if frame in (0, 1):
        for v in ([-3.3, -0.3, 2.7] if frame == 0 else [-3.0, 2.2]):
            marks.append(([(5.5, v), (19.0, v)], 'broken'))          # rows along the span
        for u in (12.9, 10.5, 8.0):                                  # dips between feather ends
            vt = trailing_v(P, u)
            marks.append(([(u, vt - 1.0), (u, vt + 3.5)], 'notch'))
    else:
        for u in (6.8, 9.6, 12.4, 14.8):
            vt = trailing_v(P, u)
            marks.append(([(u + 0.4, vt - 3.0 / w), (u - 0.2, vt + 1.5 / w)], 'dash'))   # out to the trailing edge
    return marks


def wing_geometry(frame):
    """The near wing on screen: its region, and its dark marks as (screen points, kind)."""
    deg, w, k = NEAR_POSES[frame]
    rx, ry = ROOT_NEAR
    ca, sa = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    def to_screen(u, v):
        u, v = u * k, (v + V_SHIFT) * w * k
        x, y = u * ca + v * sa, -u * sa + v * ca    # rotate, tip up for positive degrees
        return (rx + x, ry + y)
    poly, feathers = wing_outline()
    parts = [poly_inside([to_screen(u, v) for (u, v) in poly])]
    for (cu, cv, ru, rv) in feathers:
        parts.append(poly_inside([to_screen(cu + ru * math.cos(a), cv + rv * math.sin(a))
                                  for a in [i * math.pi / 10 for i in range(20)]]))
    return union(*parts), [([to_screen(u, v) for (u, v) in pts], kind) for (pts, kind) in wing_marks(frame)]


def far_dome(frame):
    """The far wing's rounded top as a screen region: its base is below the top face's far
    edge, so the body hides all but the dome."""
    if frame == 0:
        top = (bez((7.5, 18.0), (7.5, 12.0), (10.0, 7.0), (14.5, 7.0), 10) +
               bez((14.5, 7.0), (18.0, 7.0), (18.8, 9.5), (18.9, 12.5), 6))
    elif frame == 1:
        top = (bez((8.5, 17.0), (8.7, 12.5), (10.5, 10.0), (13.5, 10.0), 8) +
               bez((13.5, 10.0), (16.2, 10.0), (16.8, 11.5), (16.9, 13.5), 5))
    else:
        return lambda x, y: False
    return poly_inside(top + [(top[-1][0], 22.0), (top[0][0], 22.0)])


def slot_dots():
    """The dark dots of the two slots, so a seam never runs into them."""
    d = Canvas(41, 40)
    d.fill(BODY, 1)
    body_detail(d)
    return {(x, y) for y in range(d.h) for x in range(d.w) if d.p[y][x] == 2 and in_top(x, y)}


SLOTS = slot_dots()
NEAR_SLOTS = {(x + dx, y + dy) for (x, y) in SLOTS for dx in (-1, 0, 1) for dy in (-1, 0, 1)}


def seam2(c, front, back):
    """A solid two-dot-wide dark seam: dots of a back layer within two of a front layer. It
    stops one dot short of the slots, so nothing looks as if it grows out of a slot."""
    for y in range(c.h):
        for x in range(c.w):
            if (x, y) in NEAR_SLOTS and (x, y) not in SLOTS:
                continue
            if c.p[y][x] and back(x + 0.5, y + 0.5) and not front(x + 0.5, y + 0.5):
                if any(front(x + dx + 0.5, y + dy + 0.5) for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)
                       if abs(dx) + abs(dy) <= 2):
                    c.p[y][x] = 2


def seam(c, front, back):
    """Dots of a back layer that touch a front layer go dark, so the layers read apart."""
    for y in range(c.h):
        for x in range(c.w):
            if c.p[y][x] and back(x + 0.5, y + 0.5) and not front(x + 0.5, y + 0.5):
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if front(x + dx + 0.5, y + dy + 0.5):
                        c.p[y][x] = 2
                        break


def trace(pts):
    """The dots of a polyline, in order from its first point."""
    out = []
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        x0, y0, x1, y1 = map(lambda a: int(round(a)), (ax, ay, bx, by))
        dx, sx = abs(x1 - x0), (1 if x0 < x1 else -1)
        dy, sy = -abs(y1 - y0), (1 if y0 < y1 else -1)
        e = dx + dy
        while True:
            if not out or out[-1] != (x0, y0):
                out.append((x0, y0))
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * e
            if e2 >= dy:
                e += dy; x0 += sx
            if e2 <= dx:
                e += dx; y0 += sy
    return out


def draw_mark(c, pts, kind, region, keep):
    """A dark mark inside a region, off the lit outer edge. 'broken' keeps every other dot;
    'broken', 'dash' and 'notch' also darken the edge dot where the line leaves the
    silhouette (a one-dot notch) and record it in keep so the final finish leaves it dark."""
    dots = [(x, y) for (x, y) in trace(pts)
            if 0 <= x < c.w and 0 <= y < c.h and c.p[y][x] and region(x + 0.5, y + 0.5)]
    edge = lambda x, y: any(not c.get(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    inner = [p for p in dots if not edge(*p)]
    if kind == 'curl':
        wing = lambda x, y: c.get(x, y) and region(x + 0.5, y + 0.5)
        rim = lambda x, y: all(wing(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
        inner = []
        for (x, y) in dots:                       # a dot too near the outside moves one in, or goes
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                if rim(x + dx, y + dy):
                    if (x + dx, y + dy) not in inner:
                        inner.append((x + dx, y + dy))
                    break
    if kind in ('broken', 'dash', 'notch') and dots and edge(*dots[-1]):
        c.p[dots[-1][1]][dots[-1][0]] = 2
        keep.add(dots[-1])
    if kind == 'notch':
        return
    if kind == 'broken':
        inner = [p for i, p in enumerate(inner) if (len(inner) - i) % 5 != 1]   # dashes of four; the dot by the notch stays lit
    for (x, y) in inner:
        c.p[y][x] = 2


def body_detail_masked(c, near):
    d = c.copy()
    body_detail(d)
    for y in range(c.h):
        for x in range(c.w):
            if d.p[y][x] != c.p[y][x] and not near(x + 0.5, y + 0.5) and c.p[y][x]:
                c.p[y][x] = d.p[y][x]


def toaster(frame):
    c = Canvas(41, 40)
    near, marks = wing_geometry(frame)
    far = far_dome(frame)
    # silhouettes: far wing behind the body, near wing in front of both
    c.fill(union(far, BODY, near), 1)
    c.recolor(BODY, body_shade)
    c.recolor(lambda x, y: far(x, y) and not BODY(x, y), dots(4, 2, 1))   # the far wing, sparse dots
    c.recolor(near, 1)
    finish(c)
    seam(c, BODY, far)
    seam2(c, near, union(BODY, far))
    body_detail_masked(c, near)
    keep = set()
    for pts, kind in marks:
        draw_mark(c, pts, kind, near, keep)
    return finish(c, keep_dark_edges=lambda x, y: (x, y) in keep)


# ---------------------------------------------------------------- toast
SLICE = [  # a slice of bread, clockwise from the bottom left: straight sides, a flat bottom
    # with rounded corners, two rounded lobes on top with a dip between (u across, v up)
    (-11, 9.5), (-12, 8.5), (-12, 0), (-11.5, -4), (-10, -7.5), (-8, -9.2), (-5, -9.5),
    (-2.5, -8.3), (0, -6.4), (2.5, -8.3), (5, -9.5), (8, -9.2), (10, -7.5), (11.5, -4),
    (12, 0), (12, 8.5), (11, 9.5)]


SLICE_FLAT = [  # the slice for the flat view: straight sides, a flat bottom and one smooth
    # rounded top (the dip between two lobes turned into a divot once flattened)
    (-11, 9.5), (-12, 8.5), (-12, 0), (-11.5, -4), (-10, -7), (-7.5, -9), (-4, -10),
    (0, -10.3), (4, -10), (7.5, -9), (10, -7), (11.5, -4), (12, 0), (12, 8.5), (11, 9.5)]


def toast_flat(bottom_edge='left'):
    """A slice of toast lying flat, face up, in the same ground plane as the toaster's top:
    the bread outline mapped onto the a, b axes (2:1 edges), its flat bottom toward the
    viewer along one of the two lower edges and the lobes away, with a two-row thickness
    hanging straight down under the two near edges. bottom_edge 'left' puts the bottom along
    the lower-left edge (width along b), 'right' along the lower-right edge (width along a)."""
    c = Canvas(31, 23)
    su, sv = 7.0 / 24, 7.0 / 19             # bread units -> iso units: a 7 x 7 face
    if bottom_edge == 'left':
        wvec, hvec = B_VEC, (-A_VEC[0], -A_VEC[1])     # width along b, lobes toward -a
        cx, cy = 15.0, 8.5
    else:
        wvec, hvec = (-A_VEC[0], -A_VEC[1]), (-B_VEC[0], -B_VEC[1])  # width along -a, lobes toward -b
        cx, cy = 15.0, 8.5
    def pt(u, v, k=1.0):
        w, h = u * su * k, -v * sv * k
        return (cx + w * wvec[0] + h * hvec[0], cy + w * wvec[1] + h * hvec[1])
    face = poly_inside([pt(u, v) for (u, v) in SLICE_FLAT])
    thick = lambda x, y: face(x, y - 1) or face(x, y - 2)
    c.fill(union(face, thick), checker)                  # the thickness faces, two rows
    c.recolor(face, dots(4, 3, 1))                       # the toasted face: pale, a few dots
    # a lit outline round the face, then the crust: a dark ring one dot inside it
    def is_face(x, y):
        return face(x + 0.5, y + 0.5)
    outline = {(x, y) for y in range(c.h) for x in range(c.w) if is_face(x, y) and any(
        not is_face(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    for (x, y) in outline:
        c.p[y][x] = 1
    for y in range(c.h):
        for x in range(c.w):
            if is_face(x, y) and (x, y) not in outline and any(
                    (x + dx, y + dy) in outline for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                c.p[y][x] = 2
    return finish(c)


def toast(frame):
    return toast_flat(TOAST_BOTTOM)


TOAST_BOTTOM = 'right'          # the flat bottom along the lower-right edge: width along the flight line, like the slots
