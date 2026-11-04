"""Emulator tests: each runs one Lua script under MAME and checks its verdict.
Skipped, not failed, when the ROM images aren't installed (see tests/README.md)."""
import subprocess

import pytest

from conftest import ROOT


def run_mame(script, seconds, driver="apple2c", disk=None):
    cmd = [str(ROOT / "tests/mame/run.sh"), driver, f"tests/mame/{script}", str(seconds)]
    if disk:
        cmd.append(str(disk))
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode == 77:
        pytest.skip("emulator ROMs not installed")
    assert r.returncode == 0, r.stdout + r.stderr
    return r.stdout


def test_boot(built):
    run_mame("boot.lua", 30)
