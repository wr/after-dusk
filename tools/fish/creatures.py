"""After Dusk's own Fish! creatures: fourteen kinds, two frames each, drawn from the real
animals. Every drawing is original art made for After Dusk. Each function takes the frame
(0 or 1) and returns a Canvas (see kit.py). CREATURES lists them in the kind order.
"""
import math
from .kit import *

def forceps(ph):
    """Forceps fish (longnose butterflyfish): round yellow body, long thin snout, dark cap over
    the head and nape, white chin and chest, dark eyespot at the back of the anal fin."""
    c = Canvas(35, 33)
    wag = (0, 1)[ph]
    tail = poly_inside([(9, 16.5), (2, 10 + wag), (1, 16.5 + wag), (2, 23 + wag)])
    dors = poly_inside([(8, 12), (11, 4.5), (16, 1.5), (22, 2.5), (26, 8), (20, 8)])
    anal = poly_inside([(9, 20), (12, 28.5), (17, 30), (22, 26.5), (19, 22)])
    body = ellipse_inside(17.5, 16.5, 10, 10.5)
    snout = poly_inside([(25, 13.5), (34.6, 16), (34.6, 17.4), (25, 19.5)])
    c.fill(union(tail, dors, anal, body, snout), 1)
    # yellow body: sparse dots
    c.recolor(body, dots(3, 2))
    # fins: soft fine dots along the outer fin, a dark line where fin meets body
    c.recolor(minus(dors, body), dots(2, 2, 1))
    c.recolor(minus(anal, body), dots(2, 2, 1))
    c.recolor(tail, dots(3, 2))
    # dark cap over head and nape
    cap = poly_inside([(18.5, 5.2), (24, 6.2), (28.5, 12.6), (25.5, 14.6), (19.5, 13.5)])
    c.recolor(cap, 2)
    # chin and chest lit
    c.recolor(poly_inside([(19.5, 13.6), (25.5, 14.7), (34.6, 16.2), (34.6, 17.4), (26, 20), (22, 25), (18.5, 19)]), 1)
    finish(c)
    # eye in the cap: lit ring, dark pupil
    for (x, y) in ((23, 10), (24, 10), (25, 10), (23, 11), (25, 11), (23, 12), (24, 12), (25, 12)):
        c.put(x, y, 1)
    c.put(24, 11, 2)
    # short seams where the fins meet the body
    c.line(9, 14, 9, 19, 2)
    c.curve(lambda t: (17.5 + 10 * math.cos(t), 16.5 + 10.5 * math.sin(t)), 3.75, 4.35, 4, 2)
    # gill arc
    c.curve(lambda t: (21.5 + 2 * math.cos(t), 19 + 5 * math.sin(t)), -1.3, 1.2, 8, 2)
    # eyespot
    c.fill(ellipse_inside(12.5, 25.5, 1.7, 1.6), 2)
    # pectoral fin
    c.polyline([(20, 20), (15 + wag, 22), (19, 23)], 2)
    return c


def blue_puller(ph):
    """Blue chromis: slim oval body, deeply forked tail, big eye, soft dorsal."""
    c = Canvas(35, 19)
    wag = (0, 1)[ph]
    tail = poly_inside([(10, 9.5), (1, 1.5 + wag), (5, 9.5), (1, 17.5 + wag)])
    dors = poly_inside([(10, 6), (14, 1.5), (22, 1), (26, 4), (20, 5)])
    anal = poly_inside([(13, 14), (16, 17.5), (22, 15.5), (21, 13)])
    body = union(ellipse_inside(20, 9.5, 12.5, 5.6), ellipse_inside(13, 9.5, 5, 3.8))
    c.fill(union(tail, dors, anal, body), 1)
    # darker back, lighter belly
    c.recolor(lambda x, y: body(x, y) and y < 8, checker)
    c.recolor(lambda x, y: body(x, y) and 8 <= y < 10.5, dots(2, 2))
    c.recolor(minus(dors, body), dots(2, 2, 1))
    c.recolor(tail, dots(2, 2, 1))
    finish(c)
    # eye
    c.fill(ellipse_inside(27.5, 8, 2.2, 2.2), 1)
    c.curve(lambda t: (27.5 + 2.6 * math.cos(t), 8 + 2.6 * math.sin(t)), 0, 6.3, 18, 2)
    c.put(28, 8, 2); c.put(28, 7, 2)
    c.line(32, 11, 33, 11, 2)            # mouth
    c.curve(lambda t: (23.5 + 1.5 * math.cos(t), 10 + 4 * math.sin(t)), -1.3, 1.3, 6, 2)  # gill
    c.line(22, 12, 18 + wag, 13, 2)        # pectoral
    c.line(10, 6, 10, 13, 2)               # tail root
    return c


def pennant(ph):
    """Pennant coralfish: tall disc, two broad dark bands, long white streamer off the dorsal."""
    c = Canvas(35, 36)
    wag = (0, 1)[ph]
    tail = poly_inside([(9, 22), (3, 17 + wag), (2, 22.5 + wag), (3, 28 + wag)])
    dors = poly_inside([(9, 15), (13, 8), (18, 5), (25, 9), (17, 12)])
    anal = poly_inside([(10, 27), (13, 35), (19, 34), (22, 29)])
    body = ellipse_inside(18, 21, 10, 11.5)
    snout = poly_inside([(25.5, 18), (32, 21.5), (32, 23), (25.5, 26)])
    c.fill(union(tail, dors, anal, body, snout), 1)
    band1 = poly_inside([(19, 5), (24.5, 8.5), (21.5, 34), (15.5, 34)])
    band2 = poly_inside([(10, 12), (14, 8.5), (13, 36), (8, 34)])
    c.recolor(band1, 2)
    c.recolor(band2, 2)
    c.recolor(lambda x, y: x < 9.5, dots(2, 2))             # yellow tail
    c.recolor(lambda x, y: 12 < x < 17.5 and y < 12.5 and dors(x, y), dots(2, 2))  # yellow dorsal
    finish(c)
    # streamer: two dots thick, curving back from the dorsal spine
    for (x, y) in bez((17, 6), (12, 1), (6, 0.5 + wag), (1, 3 + wag), 24):
        c.put(x, y, 1); c.put(x, y + 1, 1)
    # eye
    c.fill(ellipse_inside(26, 18.5, 1.5, 1.5), 2)
    c.put(26, 18, 1)
    # mouth, pectoral
    c.put(31, 22, 2)
    c.line(22, 25, 19 + wag, 27, 1)
    return c


def scales(x, y):
    """Dark scale pattern: short dark arcs in staggered rows, about half dark."""
    r = y % 3
    sh = 2 if (y // 3) & 1 else 0
    xx = (x + sh) % 4
    if r == 0:
        return 2 if xx in (1, 2) else 1
    if r == 1:
        return 2 if xx in (0, 3) else 1
    return 1


def french_angelfish(ph):
    """French angelfish: deep disc body, dark grey with every scale edged pale; long dorsal
    and anal fins sweeping back past the tail root into trailing filaments; rounded tail;
    pale ring round the eye; small mouth with a pale chin."""
    c = Canvas(35, 31)
    wag = (0, 1)[ph]
    body = ellipse_inside(20.5, 15.5, 9, 11)
    snout = poly_inside([(27, 12), (33.6, 14.5), (33.6, 18), (27, 20)])
    tail = ellipse_inside(8.5, 15.5 + wag, 4.5, 4.5)
    dors = poly_inside([(26, 5), (20, 2), (13, 2), (7, 4.5), (4.5, 6.5), (8, 10), (12, 12.5)])
    anal = poly_inside([(26, 26), (20, 29), (13, 29), (7, 26.5), (4.5, 24.5), (8, 21), (12, 18.5)])
    c.fill(union(tail, dors, anal, body, snout), 1)
    # dark grey body, scales edged pale
    c.recolor(union(body, snout), scales)
    # fins and tail: dark, finer than the body
    c.recolor(minus(union(dors, anal, tail), body), checker)
    finish(c)
    # filaments trailing off the fin tips
    c.polyline([(5, 6), (3, 6 - wag), (1, 7 - wag)], 1)
    c.polyline([(5, 25), (3, 25 + wag), (1, 24 + wag)], 1)
    # seams where the fins and tail meet the body
    c.curve(lambda t: (20.5 + 9 * math.cos(t), 15.5 + 11 * math.sin(t)), 3.45, 4.75, 12, 2)
    c.curve(lambda t: (20.5 + 9 * math.cos(t), 15.5 + 11 * math.sin(t)), 1.55, 2.85, 12, 2)
    c.line(12, 12, 12, 19, 2)
    # eye: pale ring, dark centre
    c.fill(ellipse_inside(28, 12.5, 2.6, 2.6), 1)
    c.fill(ellipse_inside(28, 12.5, 1.3, 1.3), 2)
    # mouth and pale chin
    c.fill(poly_inside([(29.5, 16.5), (33.6, 16), (33.6, 18.5), (29.5, 19.5)]), 1)
    c.put(33, 15, 2)
    # pectoral fin
    c.polyline([(25, 17), (21 + wag, 20), (24, 21)], 2)
    return c


def imperial_angelfish(ph):
    """Emperor angelfish: oval body crossed by many close horizontal blue-and-yellow stripes
    that curve slightly; a dark mask through the eye edged pale; a dark bar behind the head
    over the pectoral; rounded pale tail; dorsal fin rounded at the back."""
    c = Canvas(35, 24)
    wag = (0, 1)[ph]
    body = ellipse_inside(19.5, 12, 11, 8.5)
    snout = poly_inside([(28, 9), (33.6, 11), (33.6, 13.5), (28, 15.5)])
    tail = ellipse_inside(6.5, 12 + wag, 4.5, 5)
    dors = poly_inside([(11, 7), (13, 2.5), (20, 0.5), (28, 2.5), (29, 4.5), (24, 6)])
    anal = poly_inside([(11, 17), (13, 21.5), (20, 23.5), (28, 21.5), (29, 19.5), (24, 18)])
    c.fill(union(tail, dors, anal, body, snout), 1)

    # stripes: dark rows every third row, bending up a little toward the back
    def stripes(x, y):
        yy = y + (24 - x) * 0.12
        return 2 if int(math.floor(yy)) % 3 == 0 else 1
    striped = lambda x, y: (body(x, y) or dors(x, y) or anal(x, y)) and 8.5 <= x < 25
    c.recolor(striped, stripes)
    c.recolor(minus(tail, body), dots(4, 3))
    # dark bar behind the head
    c.recolor(lambda x, y: body(x, y) and 22 <= x < 24.5 and 5 < y < 19.5, 2)
    # dark mask through the eye
    mask = poly_inside([(27.5, 5.5), (31, 6.5), (31.5, 16), (27, 17)])
    c.recolor(mask, 2)
    finish(c)
    # pale edge round the mask
    c.polyline([(27, 6), (26, 10), (26, 15), (27, 17)], 1)
    c.polyline([(31, 7), (32, 11), (32, 16)], 1)
    # eye in the mask
    c.put(29, 10, 1); c.put(30, 10, 1); c.put(29, 11, 1)
    # mouth, gill arc, pectoral
    c.put(33, 12, 2)
    c.polyline([(25, 13), (20 + wag, 15), (24, 16)], 2)
    c.line(10, 8, 10, 16, 2)
    return c


def tropical_fish(ph):
    """Butterflyfish with a false eye: compressed round body, a big dark eyespot ringed in white
    on the rear upper body, a dark bar through the real eye, fine diagonal lines across the
    body, a short pointed snout and a small fan tail."""
    c = Canvas(35, 28)
    wag = (0, 1)[ph]
    body = ellipse_inside(18.5, 14, 10, 10)
    snout = poly_inside([(27, 12), (34.6, 15), (34.6, 16.5), (27, 18)])
    tail = poly_inside([(9, 14), (2, 9 + wag), (1, 14 + wag), (2, 19 + wag)])
    dors = poly_inside([(9.5, 10), (12, 4), (19, 1.5), (26, 4), (27, 8)])
    anal = poly_inside([(10.5, 19), (13, 25), (19, 26.5), (25, 24), (26, 20)])
    c.fill(union(tail, dors, anal, body, snout), 1)
    # fine diagonal lines across the body
    lines = lambda x, y: 2 if (x + y) % 5 == 0 else 1
    c.recolor(lambda x, y: body(x, y) and x < 25, lines)
    # fin shading
    c.recolor(minus(union(dors, anal), body), dots(2, 2, 1))
    c.recolor(tail, dots(2, 2, 1))
    # dark bar through the real eye
    c.recolor(lambda x, y: (body(x, y) or dors(x, y)) and 25 <= x < 28, 2)
    # false eye: white ring, dark centre
    c.fill(ellipse_inside(13.5, 9.5, 4, 4), 1)
    c.fill(ellipse_inside(13.5, 9.5, 2.4, 2.4), 2)
    finish(c)
    # real eye
    c.put(26, 10, 1); c.put(27, 10, 1)
    # mouth, fin seams, pectoral
    c.put(34, 15, 2)
    c.line(10, 11, 10, 17, 2)
    c.polyline([(22, 16), (18 + wag, 19), (21, 20)], 2)
    return c



def red_fish(ph):
    """Squirrelfish: chunky red reef fish with a very large eye, a tall spiny dorsal fin,
    a deeply forked tail and faint pale stripes along the flank."""
    c = Canvas(35, 29)
    wag = (0, 1)[ph]
    cx, cy, rx, ry = 21.5, 16.5, 12.5, 7
    body = ellipse_inside(cx, cy, rx, ry)
    tail = poly_inside([(10, 16.5), (1, 6 + wag), (5.5, 16.5), (1, 27 + wag)])
    dors = poly_inside([(12, 12), (14, 2.5), (25, 4), (26.5, 11)])
    anal = poly_inside([(15, 22), (17, 27.5), (24, 26), (25, 22)])
    pelv = poly_inside([(23, 22), (21 + wag, 25.5), (26, 23)])
    c.fill(union(tail, dors, anal, pelv, body), 1)
    # red: even mid-grey dots
    c.recolor(body, dots(2, 2))
    c.recolor(minus(union(dors, anal, pelv), body), dots(2, 2, 1))
    c.recolor(tail, dots(2, 2, 1))
    finish(c)
    # faint pale stripes following the curve of the flank
    for k in (-0.6, -0.2, 0.25):
        c.curve(lambda u: (cx + u * rx, cy + k * ry * math.sqrt(1 - u * u)), -0.8, 0.5, 16, 1)
    # dorsal spines
    for xx in range(15, 26, 2):
        top = 3.5 + (xx - 14) * (1.5 / 11)
        c.line(xx, top + 1, xx, 11, 2)
    # very large eye
    c.fill(ellipse_inside(29, 13.5, 3, 3), 1)
    c.curve(lambda t: (29 + 3.3 * math.cos(t), 13.5 + 3.3 * math.sin(t)), 0, 6.3, 20, 2)
    c.fill(ellipse_inside(29.5, 13.5, 1.2, 1.2), 2)
    # mouth, gill arc, pectoral, tail root
    c.line(32, 18, 33, 18, 2)
    c.curve(lambda t: (24.5 + 2 * math.cos(t), 17 + 5 * math.sin(t)), -1.2, 1.2, 8, 2)
    c.polyline([(24, 19), (19 + wag, 21), (23, 22)], 2)
    c.line(10, 12, 10, 21, 2)
    return c


def globefish(ph):
    """Inflated pufferfish, side on: a ball of short spines, fan tail, fluttering pectoral,
    an eye near the front and a tiny beak."""
    c = Canvas(35, 29)
    wag = (0, 1)[ph]
    cx, cy, rx, ry = 19.5, 15, 9.8, 9.3
    body = ellipse_inside(cx, cy, rx, ry)
    tail = poly_inside([(11, 15), (4, 9.5 + wag), (2, 15.5 + wag), (4, 21 + wag)])
    beak = poly_inside([(28.5, 13.2), (32.5, 14.3), (32.5, 16.2), (28.5, 17.4)])
    c.fill(union(body, tail, beak), 1)
    # short spines poking out all round, except where the tail joins and at the beak
    for i in range(16):
        a = i * math.pi / 8 + 0.2
        if 2.5 < a < 3.9 or a < 0.25 or a > 6.1:
            continue
        x0, y0 = cx + (rx - 0.3) * math.cos(a), cy + (ry - 0.3) * math.sin(a)
        x1, y1 = cx + (rx + 1.9) * math.cos(a), cy + (ry + 1.9) * math.sin(a)
        c.line(x0, y0, x1, y1, 1)
    # dot spines inside, white belly
    c.recolor(lambda x, y: body(x, y) and y < 19.5 and x < 23, dots(3, 3))
    c.recolor(tail, dots(2, 2, 1))
    finish(c)
    # tail root
    c.line(11, 11, 11, 19, 2)
    # dark spots
    for (x, y) in ((15, 9), (13, 16)):
        c.put(x, y, 2); c.put(x + 1, y, 2); c.put(x, y + 1, 2); c.put(x + 1, y + 1, 2)
    # eye: clear halo, dark ring, pupil
    c.recolor(ellipse_inside(24.5, 11.5, 3.8, 3.6), 1)
    c.curve(lambda t: (24.5 + 2.6 * math.cos(t), 11.5 + 2.6 * math.sin(t)), 0, 6.3, 18, 2)
    c.put(24, 11, 2); c.put(25, 11, 2); c.put(24, 12, 2); c.put(25, 12, 2)
    # mouth: a short dark slit at the tip of the beak
    c.line(30, 15, 32, 15, 2)
    # pectoral fin, fluttering
    c.polyline([(21, 16), (16 - wag, 17), (17, 20 + wag), (21, 19)], 2)
    return c


def crab(ph):
    """Crab on the sea floor, seen from the front: wide scalloped carapace, two raised claws,
    four walking legs a side, eyes on stalks."""
    c = Canvas(35, 31)
    step = (0, 1)[ph]
    M = 34  # mirror axis: x -> M - x
    shell = ellipse_inside(17, 18, 10.5, 5.2)
    bumps = union(*[ellipse_inside(x, 12.9, 1.8, 1.9) for x in (9.5, 13.25, 17, 20.75, 24.5)])
    parts = [shell, bumps]
    op = 0.5 + step  # how far the movable finger opens
    for sx in (1, -1):
        def m(x):
            return x if sx > 0 else M - x
        arm = poly_inside([(m(7), 15.5), (m(9.5), 14.5), (m(6.5), 9), (m(4), 10)])
        palm = ellipse_inside(m(5), 7, 3, 2.5)
        fixed = poly_inside([(m(5.5), 5.5), (m(7.5), 5.5), (m(8.5), 1.5), (m(7.5), 1)])
        mov = poly_inside([(m(2.5), 5.5), (m(4.5), 5.5), (m(3.5 - op), 1.5), (m(2.5 - op), 2)])
        parts += [arm, palm, fixed, mov]
    c.fill(union(*parts), 1)
    c.recolor(lambda x, y: shell(x, y) and y > 14.5, dots(3, 3))
    finish(c)
    # seams where the arms meet the shell, and the palm joint
    for sx in (1, -1):
        def m(x):
            return x if sx > 0 else M - x
        c.line(m(8), 14, m(9), 16, 2)
        c.line(m(4), 9, m(6), 9, 2)
    # eyes on short stalks
    for ex, dx in ((13, -1), (21, 1)):
        c.line(ex, 12, ex + dx, 10, 1)
        for (x, y) in ((ex + dx - 1, 9), (ex + dx, 9), (ex + dx - 1, 8), (ex + dx, 8)):
            c.put(x, y, 1)
        c.put(ex + dx - (0 if dx > 0 else 1), 8, 2)
    # walking legs: body -> knee -> foot on the ground; alternate legs step
    legs = [((7, 16.5), (2, 16), (1, 30)),
            ((7, 19), (4, 20.5), (4, 30)),
            ((8, 21.5), (6, 24), (8, 30)),
            ((10, 23), (9, 26), (12, 30))]
    for i, (a, k, f) in enumerate(legs):
        lift = 1 if (i + step) % 2 else 0
        for sx in (1, -1):
            def m(p):
                return (p[0] if sx > 0 else M - p[0], p[1])
            kx, ky = k
            fx, fy = f
            c.polyline([m(a), m((kx, ky - lift)), m((fx + lift, fy - lift))], 1)
    return c


def seaweed(ph):
    """Kelp: four wavy blades standing up from the sea floor, a midrib down each."""
    c = Canvas(35, 36)
    sway = (0, 1)[ph]
    H = 35.5
    blades = [(5, 4, 1.6, 22, 0.0), (13, 9, 1.4, 18, 1.5), (21, 1, 1.8, 24, 3.2), (30, 11, 1.3, 16, 0.8)]

    def blade(x0, top, amp, lam, phs):
        span = H - top
        def cxf(y):
            t = (H - y) / span
            return x0 + amp * math.sin(2 * math.pi * (H - y) / lam + phs) + 1.6 * sway * t * t
        def hwf(y):
            t = (H - y) / span
            return 0.8 + 2.0 * math.sin(math.pi * min(1.0, t * 1.1))
        def inside(x, y):
            if y > H or y < top:
                return False
            return abs(x - cxf(y)) <= hwf(y)
        return inside, cxf, hwf

    parts = [blade(*b) for b in blades]
    c.fill(union(*[p[0] for p in parts]), 1)
    for inside, cxf, hwf in parts:
        c.recolor(inside, dots(4, 3))
    finish(c)
    for (x0, top, amp, lam, phs), (inside, cxf, hwf) in zip(blades, parts):
        for y in range(int(top), 36):
            if hwf(y + 0.5) >= 1.8:
                c.put(cxf(y + 0.5) - 0.5, y, 2)
    return c


def ring6(c, x0, y0):
    """A round 6-across bubble: four flat dots a side, diagonal corners, dark inside."""
    for x in range(x0 + 1, x0 + 5):
        c.put(x, y0, 1); c.put(x, y0 + 5, 1)
    for y in range(y0 + 1, y0 + 5):
        c.put(x0, y, 1); c.put(x0 + 5, y, 1)
        for x in range(x0 + 1, x0 + 5):
            c.put(x, y, 2)
    c.put(x0 + 2, y0 + 2, 1)   # highlight


def ring4(c, x0, y0):
    """A 4-across bubble: a plus-shaped ring with a 2x2 dark middle."""
    for x in (x0 + 1, x0 + 2):
        c.put(x, y0, 1); c.put(x, y0 + 3, 1)
    for y in (y0 + 1, y0 + 2):
        c.put(x0, y, 1); c.put(x0 + 3, y, 1)
        c.put(x0 + 1, y, 2); c.put(x0 + 2, y, 2)


def bubbles(ph):
    """A loose group of air bubbles rising: round lit rings with a highlight."""
    c = Canvas(13, 15)
    w = (0, 1)[ph]
    ring6(c, 6 - w, 1)
    ring4(c, 1 + w, 7)
    # small: 3 across, a diamond ring
    sx, sy = 9 - w, 10
    for (x, y) in ((sx - 1, sy), (sx + 1, sy), (sx, sy - 1), (sx, sy + 1)):
        c.put(x, y, 1)
    c.put(sx, sy, 2)
    # tiny ones: single dots
    c.put(4 + w, 13, 1)
    c.put(11 - w, 14, 1)
    c.put(2 + w, 3, 1)
    return c


def tube(pts, radii):
    """Inside test for a sausage: a disc at every point of a centreline, radius interpolated."""
    def inside(x, y):
        for (px, py), r in zip(pts, radii):
            if (x - px) ** 2 + (y - py) ** 2 <= r * r:
                return True
        return False
    return inside


def stamp(c, x, y, rows, key):
    """Paint a little hand-drawn pattern at (x, y); key maps each character to a value."""
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch in key:
                c.put(x + i, y + j, key[ch])


RING = [".##.",
        "#..#",
        ".##."]


def jellyfish(ph):
    """Moon jelly: a flattened translucent dome with a scalloped rim, four gonad rings showing
    through near the top, and fine tentacles trailing below.  Frame 0 the bell is tall and
    narrow, frame 1 it has squeezed squat and wide and the tentacles bunch and spread."""
    c = Canvas(35, 30)
    cx = 17.5
    if ph == 0:
        rx, ry, cy, bot = 12.5, 11.5, 12.5, 13.5
    else:
        rx, ry, cy, bot = 16.0, 8.5, 10.5, 12.5
    dome = lambda x, y: ellipse_inside(cx, cy, rx, ry)(x, y) and y <= bot
    # scalloped rim: notches bitten out of the bottom edge
    notches = union(*[ellipse_inside(cx + k * 4, bot + 0.2, 1.6, 1.3) for k in (-3, -2, -1, 0, 1, 2, 3)])
    bell = minus(dome, notches)
    c.fill(bell, 1)
    finish(c)
    # four gonad rings in a shallow arc, each on a clear patch
    gy = int(round(cy - ry * 0.55))
    rings = ((-7.5, 1), (-2.5, 0), (2.5, 0), (7.5, 1)) if ph == 0 else ((-9, 0), (-3, 0), (3, 0), (9, 0))
    for k, dy in rings:
        gx = int(cx + k) - 1
        c.fill(lambda x, y, gx=gx, gy=gy, dy=dy: gx - 0.5 <= x <= gx + 4.5 and gy + dy - 0.5 <= y <= gy + dy + 3.5, 1)
        stamp(c, gx, gy + dy, RING, {'#': 2})
    # the ring canal and frill just above the rim: one dotted row
    c.recolor(lambda x, y: bell(x, y) and int(bot) - 2 < y < int(bot) - 1 and abs(x - cx) < rx - 3, dots(2, 1))
    # tentacles: thin lit threads from the rim
    n = 9
    for i in range(n):
        u = (i - (n - 1) / 2) / ((n - 1) / 2)          # -1 .. 1
        x0 = cx + u * (rx - 2)
        if ph == 0:
            length = 15 - 3 * (u * u) + (1 if i % 2 else 0)
            spread = 0.5 * u
        else:
            length = 12 - 3 * (u * u) + (1 if i % 2 else 0)
            spread = 3.0 * u
        wig = 0.8 if i % 2 else -0.8
        c.curve(lambda t, x0=x0, spread=spread, wig=wig, length=length:
                (x0 + spread * t + wig * math.sin(t * length / 3.0), bot + 1 + t * length),
                0, 1, int(length * 2), 1)
    return c


def seahorse(ph):
    """Seahorse in profile, snout right: coronet, tube snout, curved neck and belly, ringed
    body, tail curled forward in a spiral.  Only the little dorsal fin on its back moves."""
    c = Canvas(18, 36)
    # spine: head down the back, belly forward, tail curling forward and in
    spine = (bez((11, 6), (8, 9), (6.5, 13), (7.5, 18), 12)
             + bez((7.5, 18), (8.5, 23), (6.5, 27), (7.5, 30), 10)
             + bez((7.5, 30), (8.5, 34), (13.5, 34.5), (14, 31), 10)
             + bez((14, 31), (14.3, 28.5), (11.5, 28), (11.5, 30), 8))
    radii = ([2.7, 2.6, 2.6, 2.7, 2.9, 3.1, 3.3] + [3.5, 3.7, 3.9, 4.0, 4.0, 3.9]
             + [3.7, 3.3, 2.9, 2.6, 2.3, 2.1, 1.9, 1.7, 1.5, 1.4, 1.3]
             + [1.3, 1.2, 1.1, 1.0, 0.9, 0.9, 0.9, 0.8, 0.8, 0.8, 0.8]
             + [0.8] * 9)
    body = tube(spine, radii)
    head = ellipse_inside(11, 6, 3.4, 2.9)
    snout = poly_inside([(12, 5.5), (17.6, 7.2), (17.6, 9.3), (12, 9.5)])
    crown = poly_inside([(8.5, 3.5), (9, 1.2), (10, 2.5), (11, 0.4), (12, 2.5), (13, 1.2), (13.8, 3.5)])
    fin_dy = (0, 1)[ph]
    fin = poly_inside([(4.5, 13.5), (1.5, 12.5 + fin_dy), (0.4, 16.5 + fin_dy), (1.2, 21 - fin_dy), (4, 21.5)])
    c.fill(union(body, head, snout, crown, fin), 1)
    # ridged rings across the body every 4 dots along the spine; down the thin tail they
    # shrink to single ridge dots
    s, nxt = 0.0, 5.0
    for i in range(1, len(spine) - 1):
        (xa, ya), (xb, yb) = spine[i - 1], spine[i]
        s += math.hypot(xb - xa, yb - ya)
        if s >= nxt:
            nxt += 4.0 if radii[i] >= 2.0 else 3.0
            px, py = spine[i]
            if radii[i] < 2.0:
                if radii[i] > 1.1:
                    c.put(px, py, 2)
                continue
            (x0, y0), (x1, y1) = spine[i - 1], spine[i + 1]
            nx, ny = -(y1 - y0), (x1 - x0)
            d = math.hypot(nx, ny) or 1
            nx, ny = nx / d, ny / d
            r = radii[i] - 0.3
            c.line(px - nx * r, py - ny * r, px + nx * r, py + ny * r, 2)
    finish(c)
    # eye, snout line, fin rays
    c.put(12, 5, 2)
    c.line(13, 8, 16, 8, 2)
    c.line(3, 15, 2, 14 + fin_dy, 2)
    c.line(3, 17, 2, 17 + fin_dy, 2)
    c.line(3, 19, 2, 20 - fin_dy, 2)
    return c


MINI = ["#..###.",
        ".######",
        "#..###."]
MINI_UP = ["#..###.",
           ".######",
           ".#.###."]
MINI_DOWN = [".#.###.",
             ".######",
             "#..###."]


def mini_fish(c, x, y, flick):
    stamp(c, x, y, (MINI, MINI_UP, MINI_DOWN)[flick], {'#': 1})
    c.put(x + 5, y + 1, 2)      # eye


def school(ph):
    """A loose school of ten small fish, all heading right, shimmering as tails flick and a
    few of them nudge along a dot."""
    c = Canvas(32, 35)
    # (x, y, tail shape at frame 0, nudge at frame 1)
    fish = [(12, 0, 0, 1), (23, 3, 1, 0),
            (3, 6, 2, 0), (15, 9, 0, 1),
            (25, 14, 2, 1), (7, 15, 1, 0),
            (1, 22, 0, 1), (18, 21, 2, 0),
            (10, 28, 1, 1), (22, 30, 0, 0)]
    for x, y, fl, dx in fish:
        if ph == 1:
            fl = (fl + 1) % 3
            x += dx
        mini_fish(c, x, y, fl)
    return c


CREATURES = [
    ('French Angelfish', french_angelfish),
    ('Blue Puller', blue_puller),
    ('Pennant Coralfish', pennant),
    ('Globefish', globefish),
    ('Forceps Fish', forceps),
    ('Crab', crab),
    ('Red Fish', red_fish),
    ('Imperial Angelfish', imperial_angelfish),
    ('School', school),
    ('Tropical Fish', tropical_fish),
    ('Seaweed', seaweed),
    ('Bubbles', bubbles),
    ('JellyFish', jellyfish),
    ('Seahorse', seahorse),
]
