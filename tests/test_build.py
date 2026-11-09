import re
import subprocess

from conftest import ROOT, dos33, labels


def test_disk_size(built):
    assert (built / "AFTERDUSK.dsk").stat().st_size == 143360


def catalog(built):
    """{name: type} for every file on the disk."""
    out = subprocess.run([dos33(), str(built / "AFTERDUSK.dsk"), "CATALOG"],
                         check=True, capture_output=True, text=True).stdout
    return {m.group(2): m.group(1) for m in re.finditer(r"^\s*\*?\s*([ABTI])\s+\d+\s+(\S+)", out, re.M)}


def test_catalog(built):
    entries = catalog(built)
    assert entries.get("HELLO") == "A"
    assert entries.get("AFTERDUSK") == "B"
    assert entries.get("SEED") == "T"
    assert entries.get("FX") == "B"


def test_load_address_and_size(built):
    assert labels()["start"] == 0x6000
    assert "restart" in labels()
    assert (built / "afterdusk.bin").stat().st_size <= 0x2800    # $6000-$87FF
    assert (built / "fx.bin").stat().st_size <= 0x4000           # $2000-$5FFF


def test_disk_has_fx2(built):
    assert catalog(built).get("FX2") == "B"
    assert (built / "fx2.bin").stat().st_size <= 0x4000          # aux $6000-$9FFF


def test_disk_has_fx3(built):
    assert catalog(built).get("FX3") == "B"
    assert (built / "fx3.bin").stat().st_size <= 0x2000          # main $A000-$BFFF


def test_disk_has_the_splash(built):
    assert catalog(built).get("PAINT") == "B"
    assert (built / "paint.bin").stat().st_size <= 0x15E0        # $8000-$95DF
    assert (built / "obj" / "HELLO.tok").exists()


def test_no_speaker_refs():
    for path in (ROOT / "src").glob("*"):
        text = path.read_text(errors="replace")
        for word in ("C030", "c030", "SPKR", "SPEAKER"):
            assert word not in text, f"{path.name} mentions {word}"
