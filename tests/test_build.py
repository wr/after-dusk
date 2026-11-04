import re
import subprocess

from conftest import ROOT, dos33, labels


def test_disk_size(built):
    assert (built / "AFTERDUSK.dsk").stat().st_size == 143360


def test_catalog(built):
    out = subprocess.run([dos33(), str(built / "AFTERDUSK.dsk"), "CATALOG"],
                         check=True, capture_output=True, text=True).stdout
    entries = {m.group(2): m.group(1) for m in re.finditer(r"^\s*\*?\s*([ABTI])\s+\d+\s+(\S+)", out, re.M)}
    assert entries.get("HELLO") == "A"
    assert entries.get("AFTERDUSK") == "B"
    assert entries.get("SEED") == "T"


def test_load_address_and_size(built):
    assert labels()["start"] == 0x6000
    assert "restart" in labels()
    assert (built / "afterdusk.bin").stat().st_size <= 13824


def test_no_speaker_refs():
    for path in (ROOT / "src").glob("*"):
        text = path.read_text(errors="replace")
        for word in ("C030", "c030", "SPKR", "SPEAKER"):
            assert word not in text, f"{path.name} mentions {word}"
