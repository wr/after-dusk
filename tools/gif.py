"""Turn one effect's emulator frames (tests/mame/movie.lua) into an animated GIF.

    python tools/gif.py <fx id> <frames dir> <out dir>

Keeps one frame per step of the effect (its ticks from the table below), at
the point in the step where the most dots are lit, so lines that are rubbed
out and redrawn don't flicker. MAME's frames are 560 x 192 (each hi-res dot
two pixels wide) from its green monochrome monitor, black and one green;
the GIFs double the lines to 560 x 384, like the screenshots.
"""
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

# id: (file name, ticks per step as in src/main.s fx_table, start s, length s)
EFFECTS = {
    0: ("flying-toasters", 4, 0, 6),
    1: ("warp", 2, 0, 5),
    2: ("starry-night", 4, 0, 6),
    3: ("zot", 3, 1.25, 7.1),           # from one bolt to just before the third
    4: ("can-of-worms", 3, 0, 6),
    5: ("lissajous", 2, 2, 6),
    6: ("nightlines", 5, 2, 6),
    7: ("string-theory", 6, 2, 6),
    8: ("rose", 2, 0, 6),
    9: ("doodles", 2, 0, 6),
    10: ("shapes", 3, 0, 6),
    11: ("spheres", 4, 0, 6),
    12: ("bouncing-ball", 3, 0, 5),
    13: ("rainstorm", 3, 0, 5),
}
GREEN = (25, 215, 0)


def load(frames_dir, first, count):
    out = []
    for n in range(first, first + count):
        im = Image.open(frames_dir / f"f{n:04d}.png").convert("L")
        im = im.point(lambda v: 255 if v > 40 else 0).convert("1")
        out.append(im.resize((im.width, im.height * 2), Image.NEAREST))
    return out


def main():
    fx, frames_dir, out_dir = int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    name, ticks, start, length = EFFECTS[fx]
    first, count = int(start * 60), int(length * 60)
    frames = load(frames_dir, first, count + ticks)

    # The phase within a step where the picture is fullest.
    def lit(p):
        return sum(frames[i].histogram()[255] for i in range(p, count, ticks))
    phase = max(range(ticks), key=lit)
    picked = frames[phase:phase + count:ticks]

    # Each kept frame lasts one step; GIF delays are in 1/100 s, so round the
    # running time, not each delay, to keep the speed exact. Identical frames
    # in a row become one longer frame.
    stills, delays = [], []
    for i, im in enumerate(picked):
        cs = round((i + 1) * ticks * 100 / 60) - round(i * ticks * 100 / 60)
        if stills and im.tobytes() == stills[-1].tobytes():
            delays[-1] += cs
        else:
            stills.append(im)
            delays.append(cs)

    pal = [0, 0, 0, *GREEN] + [0] * (256 * 3 - 6)
    paletted = []
    for im in stills:
        p = im.convert("L").point(lambda v: 1 if v else 0).convert("P")
        p.putpalette(pal)
        paletted.append(p)
    out = out_dir / f"{name}.gif"
    paletted[0].save(out, save_all=True, append_images=paletted[1:],
                     duration=[d * 10 for d in delays], loop=0, optimize=False)
    if shutil.which("gifsicle"):                # lossless, often 5 times smaller
        subprocess.run(["gifsicle", "-b", "-O3", str(out)], check=True)
    print(f"{out}: {len(stills)} frames, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
