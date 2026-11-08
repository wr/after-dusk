import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"


@pytest.fixture(scope="session")
def built():
    """Build the release disk once per test session and return the build dir."""
    subprocess.run(["./build.sh"], cwd=ROOT, check=True, capture_output=True, text=True)
    return BUILD


def dos33():
    return str(ROOT / ".tools/dos33fsprogs/utils/dos33fs-utils/dos33")


def labels(path=None):
    """Parse an ld65 -Ln label file into {name: address}."""
    path = path or BUILD / "afterdusk.lbl"
    out = {}
    for line in Path(path).read_text().splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "al":
            out[parts[2].lstrip(".")] = int(parts[1], 16)
    return out


def hop_build(hop):
    """The build directory for Fish! with `hop`-dot hops: build/ for the
    default 2, build/hop4/ (built on first use, files apart) for 4."""
    if hop == 2:
        return BUILD
    path = BUILD / f"hop{hop}"
    subprocess.run(["./build.sh"], cwd=ROOT, check=True, capture_output=True, text=True,
                   env=dict(os.environ, FISH_HOP=str(hop), BUILD_DIR=f"build/hop{hop}"))
    return path
