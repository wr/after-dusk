"""Flying Toasters' art: the generator's output is exactly the approved drawings."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tools import toasters  # noqa: E402
from tools.fish.kit import mask_of  # noqa: E402

APPROVED = "5e7dd754d8824c39a708b5a13e10f84a2d320c60d74e1a321f25083ccaac6d79"


def rows_of(c):
    """A canvas as text rows: # lit, - dark, o mask only, . empty."""
    m = mask_of(c)
    return [''.join('#' if c.p[y][x] == 1 else '-' if c.p[y][x] == 2
                    else ('o' if m[y][x] else '.') for x in range(c.w))
            for y in range(c.h)]


def test_approved_drawings():
    blob = json.dumps({'toaster': [rows_of(toasters.toaster(k)) for k in range(4)],
                       'toast': rows_of(toasters.toast(0))}, separators=(',', ':'))
    assert hashlib.sha256(blob.encode()).hexdigest() == APPROVED
