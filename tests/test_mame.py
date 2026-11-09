"""Emulator tests: each runs one Lua script under MAME and checks its verdict.
Skipped, not failed, when the ROM images aren't installed (see tests/README.md)."""
import os
import re
import shutil
import subprocess

import pytest

from conftest import ROOT, dos33


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
    run_mame("boot.lua", 95)


def test_boots_on_enhanced_iie(built):
    run_mame("iie.lua", 95, driver="apple2ee")


def test_timing(built):
    run_mame("timing.lua", 95)


def test_pacing(built):
    run_mame("pacing.lua", 600)


@pytest.fixture(scope="session")
def test_disk(built):
    """The disk with 2-second effects, for tests that need many effects."""
    out = built / "AFTERDUSK-test.dsk"
    env = dict(os.environ, FX_TICKS="120", OUT=str(out))
    subprocess.run(["./build.sh"], cwd=ROOT, env=env, check=True, capture_output=True)
    subprocess.run(["./build.sh"], cwd=ROOT, check=True, capture_output=True)  # labels back to release
    return out


@pytest.fixture(scope="session")
def fish_disk(built):
    """A trial disk that shows Fish! from power-on (ONLY_FX=14), the default
    hop size."""
    out = built / "FISH-TRIAL.dsk"
    env = dict(os.environ, ONLY_FX="14", OUT=str(out))
    subprocess.run(["./build.sh"], cwd=ROOT, env=env, check=True, capture_output=True)
    subprocess.run(["./build.sh"], cwd=ROOT, check=True, capture_output=True)  # labels back to release
    return out


def disk_copy(src, name, tmp_path):
    dst = tmp_path / name
    shutil.copy(src, dst)
    os.chmod(dst, 0o644)
    return dst


def test_randomizer(test_disk, tmp_path):
    run_mame("randomizer.lua", 225, disk=disk_copy(test_disk, "r.dsk", tmp_path))


def test_fish_rate(fish_disk, tmp_path):
    """Fish! takes 300 steps in 300 frames on the IIc."""
    run_mame("fish_rate.lua", 85, disk=disk_copy(fish_disk, "fish.dsk", tmp_path))


def test_fish_rate_on_enhanced_iie(fish_disk, tmp_path):
    """Review Focus 5: without the IIc's vertical-blank latch Fish! still runs
    within -17%..+22% of its rate (it pads its own step to about a tick)."""
    run_mame("fish_rate.lua", 85, driver="apple2ee", disk=disk_copy(fish_disk, "fish-iie.dsk", tmp_path))


def test_reset(built, tmp_path):
    run_mame("reset.lua", 95, disk=disk_copy(built / "AFTERDUSK.dsk", "reset.dsk", tmp_path))


def test_seed_changes_each_boot(built, tmp_path):
    d = disk_copy(built / "AFTERDUSK.dsk", "seed.dsk", tmp_path)
    seeds = []
    for _ in range(2):
        out = run_mame("seed.lua", 95, disk=d)
        seeds.append(int(re.search(r"seed=(\d+)", out).group(1)))
    assert seeds[0] != seeds[1], seeds


def test_boots_without_seed_file(built, tmp_path):
    d = disk_copy(built / "AFTERDUSK.dsk", "noseed.dsk", tmp_path)
    subprocess.run([dos33(), "-y", str(d), "DELETE", "SEED"], check=True, capture_output=True)
    run_mame("boot.lua", 95, disk=d)


def test_boots_write_protected(built, tmp_path):
    d = disk_copy(built / "AFTERDUSK.dsk", "ro.dsk", tmp_path)
    os.chmod(d, 0o444)
    run_mame("boot.lua", 95, disk=d)


@pytest.mark.skipif(not os.environ.get("AD_SOAK"), reason="long: set AD_SOAK=1 (8 emulated hours)")
def test_soak(built, tmp_path):
    run_mame("soak.lua", 8 * 3600 + 150, disk=disk_copy(built / "AFTERDUSK.dsk", "soak.dsk", tmp_path))
