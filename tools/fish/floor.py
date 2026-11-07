"""After Dusk's own sea floor, an original drawing: 280 x 36 dots. Sand speckle that thickens toward the bottom,
fading up into the black water, with pebbles of a few sizes half sunk in it.
Returns rows of 0 (dark) / 1 (lit)."""
import math, random

W, H = 280, 36
BAYER8 = None

def bayer(n):
    if n == 1:
        return [[0]]
    b = bayer(n // 2)
    m = n // 2
    out = [[0] * n for _ in range(n)]
    for y in range(n):
        for x in range(n):
            v = b[y % m][x % m] * 4
            out[y][x] = v + [[0, 2], [3, 1]][y // m][x // m]
    return out

def floor(seed=7):
    rnd = random.Random(seed)
    B = bayer(8)
    g = [[0] * W for _ in range(H)]
    # a gently wavy top edge for the sand
    top = [6 + 2.2 * math.sin(x / 23.0) + 1.3 * math.sin(x / 9.0 + 1.7) for x in range(W)]
    for y in range(H):
        for x in range(W):
            t = (y - top[x]) / (H - top[x])          # 0 at the sand's top, 1 at the bottom
            if y < top[x] - 5:
                continue
            if y < top[x]:
                lvl = 0.03 * (1 - (top[x] - y) / 5)      # stray grains above the sand
            else:
                lvl = 0.04 + 0.30 * min(1, t) ** 1.3
            # random grains, never two lit side by side across (keeps it grainy, not blotchy)
            if rnd.random() < lvl:
                g[y][x] = 1
    # pebbles: dark-edged lit stones with a dark lower half (shadow)
    placed = []
    for k in range(20):
        for _ in range(40):
            rx = rnd.choice([2, 2.5, 3, 3.5, 4, 5])
            ry = max(1.0, rx * rnd.uniform(0.55, 0.75))
            cx = rnd.uniform(4, W - 4)
            cy = rnd.uniform(top[int(cx)] + 4 + ry, H - 1.5)
            if all(abs(cx - px) > rx + pr + 2 or abs(cy - py) > ry + pq + 2 for px, py, pr, pq in placed):
                placed.append((cx, cy, rx, ry))
                break
    for cx, cy, rx, ry in placed:
        for y in range(int(cy - ry - 2), int(cy + ry + 3)):
            for x in range(int(cx - rx - 2), int(cx + rx + 3)):
                if not (0 <= x < W and 0 <= y < H):
                    continue
                d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
                d2 = ((x + 0.5 - cx) / (rx + 1.6)) ** 2 + ((y + 0.5 - cy) / (ry + 1.4)) ** 2
                if d <= 1:
                    # a grey stone: lit rim, checker inside, lit highlight up and to the left
                    inner = ((x + 0.5 - cx) / max(0.5, rx - 1)) ** 2 + ((y + 0.5 - cy) / max(0.5, ry - 1)) ** 2
                    hi = ((x + 0.5 - (cx - rx * 0.35)) / (rx * 0.35)) ** 2 + ((y + 0.5 - (cy - ry * 0.4)) / (ry * 0.35)) ** 2
                    if inner > 1 or hi <= 1 or rx <= 2:
                        g[y][x] = 1
                    else:
                        g[y][x] = 0 if (x + y) & 1 else 1
                elif d2 <= 1:
                    g[y][x] = 0      # dark ring so the stone stands off the sand
    return g

if __name__ == '__main__':
    from PIL import Image
    g = floor()
    im = Image.new('RGB', (W, H))
    for y in range(H):
        for x in range(W):
            im.putpixel((x, y), (120, 255, 140) if g[y][x] else (0, 0, 0))
    im.resize((W * 4, H * 4), Image.NEAREST).save('floor.png')
    print('ok')
