# Tests

Two layers.

## Host tests (no emulator)

`tests/sim.py` loads the linked program into py65, a Python 65C02 simulator that also counts
cycles, and calls individual routines. These tests check drawing, the sprite engine, the random
numbers, the randomizer's choices, and each effect's behaviour and per-step cycle budget.

```sh
tools/bootstrap.sh                   # once
.tools/venv/bin/pytest tests -q
```

The session builds the disk once (`tests/conftest.py`).

## Emulator tests (MAME)

`tests/mame/run.sh <driver> <script.lua> <seconds> [disk]` boots a disk in MAME and runs a Lua
script against it, unthrottled and without a window. Scripts use `tests/mame/lib.lua`: they wait
in emulated frames, read the status block (`$0310`–`$0315`, see `AGENTS.md`), press keys and take
snapshots into `build/mame/snap/`. Every script also fails if After Dusk's own code touches the
speaker. `tests/test_mame.py` runs the scripts from pytest and skips them when the ROMs are missing.

### ROM images

MAME needs the Apple IIc's ROMs, which are Apple's and never go in this repository. Put them in
`.tools/roms/` (gitignored), arranged by MAME's set names:

```
.tools/roms/apple2c/    a2c.128  341-0265-a.chr  342-0132-c.e12  341-0027-a.p5  341-0028-a.rom  sc01a.bin
.tools/roms/a2diskiing/ 341-0027-a.p5  341-0028-a.rom
.tools/roms/d2fdc/      341-0027-a.p5  341-0028-a.rom
.tools/roms/votrsc01a/  sc01a.bin
```

`a2c.128` is the IIc's ROM version 255 (the first 16K of `apple2co.rom` in
`apple_2c_original_rom.zip` from the Asimov archive's `emulators/rom_images` folder; its I/O page
differs from MAME's dump, so the checksum won't match). The Disk II PROMs come from the same
folder. The character ROM, keyboard ROM and speech-chip ROM are zero-filled placeholders: After
Dusk shows no text and only checks that some key was pressed, so the tests don't need them. MAME
reports wrong checksums and "might not run correctly", and runs anyway.

### The long ones

- `pacing.lua` checks every effect's real rate (steps per 300 frames) on the release disk.
- `soak.lua` runs 8 emulated hours on the release disk: still running every minute, all six
  effects seen, no effect twice in a row, 3 minutes each on average. It takes about 13 minutes
  of real time, so pytest skips it unless `AD_SOAK=1` is set. First full run (2026-11-04):
  160 effects, 180.5 s average, passed.

### Lessons

- `SDL_VIDEODRIVER=dummy` is what keeps MAME from opening a window on macOS.
- `-nothrottle` makes emulated time run as fast as the Mac allows (about 20× real time here), so
  wait in emulated frames, never in wall-clock time.
- The IIc ROM beeps at power-on. The speaker guard only counts accesses made while the program
  counter is inside After Dusk (`$6000`–`$95FF`).
- MAME writes cfg, nvram and snapshots under `build/mame/`, never into the source tree.
