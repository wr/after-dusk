"""Fish!'s art: the generator's output is exactly the approved drawings."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tools.fish import floor as floor_mod  # noqa: E402
from tools.fish.creatures import CREATURES  # noqa: E402
from tools.fish.kit import mask_of  # noqa: E402

APPROVED = "dabcab45ae1cd88d1f55dd37453b484ddc20ce3b73771c22e4a69d1e5acfcb05"
ORDER = ['French Angelfish', 'Blue Puller', 'Pennant Coralfish', 'Globefish', 'Forceps Fish',
         'Crab', 'Red Fish', 'Imperial Angelfish', 'School', 'Tropical Fish', 'Seaweed',
         'Bubbles', 'JellyFish', 'Seahorse']


def sample_blob():
    """The blob export.py built for the approved sample."""
    out = []
    for name, fn in CREATURES:
        fr = [fn(0), fn(1)]
        frames = []
        for c in fr:
            m = mask_of(c)
            frames.append([''.join('#' if c.p[y][x] == 1 else '-' if c.p[y][x] == 2
                                   else ('o' if m[y][x] else '.') for x in range(c.w))
                           for y in range(c.h)])
        out.append({'name': name, 'w': fr[0].w, 'h': fr[0].h, 'frames': frames})
    fl = [''.join('#' if v else '.' for v in row) for row in floor_mod.floor()]
    return json.dumps({'creatures': out, 'floor': fl}, separators=(',', ':'))


@pytest.fixture(scope="session")
def art():
    subprocess.run([sys.executable, str(ROOT / "tools/gen_fish.py")], check=True)
    return json.loads((ROOT / "build/fish_art.json").read_text())


def unpack(rows, x0, y0, w, h):
    """Bytes back to a set of (x, y) dots in the cell."""
    dots = set()
    for j, row in enumerate(rows):
        for b, v in enumerate(row):
            for k in range(7):
                if v >> k & 1:
                    dots.add((x0 + b * 7 + k, y0 + j))
    return dots


def test_art_is_the_approved_drawings():
    assert hashlib.sha256(sample_blob().encode()).hexdigest() == APPROVED


def test_fourteen_kinds_in_order(art):
    assert [k["name"] for k in art["kinds"]] == ORDER


def test_roles(art):
    roles = {k["name"]: k["role"] for k in art["kinds"]}
    for name, role in roles.items():
        want = {"JellyFish": 1, "Seahorse": 1, "Crab": 2, "Globefish": 3,
                "Seaweed": 4, "Bubbles": 5}.get(name, 0)
        assert role == want, name


def test_bytes_are_hires(art):
    for k in art["kinds"]:
        for f in k["frames"]:
            for lit, mask in zip(f["lit"], f["mask"]):
                for a, b in zip(lit, mask):
                    assert a < 0x80 and b < 0x80
                    assert a & ~b == 0, k["name"]


def test_frames_share_a_box(art):
    for k in art["kinds"]:
        assert k["wb"] == -(-k["bw"] // 7)
        assert k["bx"] >= 0 and k["by"] >= 0
        assert k["bx"] + k["bw"] <= k["cw"] and k["by"] + k["rows"] <= k["ch"]
        for f in k["frames"]:
            for part in ("lit", "mask"):
                assert len(f[part]) == k["rows"]
                assert all(len(r) == k["wb"] for r in f[part])


def test_decodes_to_the_drawings(art):
    for k, (name, fn) in zip(art["kinds"], CREATURES):
        for n in (0, 1):
            c = fn(n)
            m = mask_of(c)
            lit = {(x, y) for y in range(c.h) for x in range(c.w) if c.p[y][x] == 1}
            msk = {(x, y) for y in range(c.h) for x in range(c.w) if m[y][x]}
            f = k["frames"][n]
            assert unpack(f["lit"], k["bx"], k["by"], k["cw"], k["ch"]) == lit, name
            assert unpack(f["mask"], k["bx"], k["by"], k["cw"], k["ch"]) == msk, name


def test_floor(art):
    fl = art["floor"]
    assert len(fl) == 36 and all(len(r) == 40 for r in fl)
    want = floor_mod.floor()
    got = unpack(fl, 0, 0, 280, 36)
    assert got == {(x, y) for y in range(36) for x in range(280) if want[y][x]}


def test_art_fits(art):
    total = sum(2 * k["rows"] * k["wb"] * 2 for k in art["kinds"])
    assert total <= 0x1E00


def test_inc_has_the_labels(art):
    text = (ROOT / "src/fish_art.inc").read_text()
    assert "FISH_NKIND = 14" in text
    for label in ("fk_cw", "fk_ch", "fk_bx", "fk_by", "fk_bw", "fk_rows", "fk_wb", "fk_role",
                  "fk_f0lo", "fk_f0hi", "fk_f1lo", "fk_f1hi", "fish_floor"):
        assert f"\n{label}:" in text
    for seg in ("FX14", "FISHART", "FISHFLOOR"):
        assert f'.segment "{seg}"' in text
