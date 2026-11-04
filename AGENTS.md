# AGENTS.md

Guidance for coding agents (Claude Code via `CLAUDE.md`, Codex) working in this repository.

## Source of truth
- GitHub: github.com/wr/after-dusk (created at the first release)
- Branch prefix: wells/
- PR mode: none (commit to main)

## What this is

After Dusk is a boot disk for the Apple IIc that goes straight into an After Dark-style screen saver
randomizer. It cycles six black-and-white hi-res effects (Flying Toasters, Warp, Starry Night, Zot!,
Can of Worms, Lissajous) in random order, about 3 minutes each, until the machine is switched off.
Any key skips to the next effect. It is silent.

One 65C02 binary, `AFTERDUSK`, loads at `$6000` from a DOS 3.3 disk whose HELLO runs it at boot.

## Commands

```bash
tools/bootstrap.sh                 # once: .tools/venv (py65, pytest, Pillow) + .tools/dos33fsprogs
./build.sh                         # -> build/AFTERDUSK.dsk
FX_TICKS=120 OUT=build/AFTERDUSK-test.dsk ./build.sh   # 2-second effects, for emulator tests
.tools/venv/bin/pytest tests -q    # host tests (py65 simulator) + emulator tests if ROMs exist
tests/mame/run.sh apple2c tests/mame/boot.lua 30       # one emulator test
tools/install-sd.sh                # put build/AFTERDUSK.dsk on a FloppyEmu SD card
```

Needs `ca65`/`ld65` (cc65) and `mame` on PATH. Emulator ROM images are not in the repo; see
`tests/README.md`.

## Layout

- `src/` 65C02 sources (ca65). `main.s` links first so `start` is at `$6000`.
  `config.inc` holds every shared address below.
- `basic/hello.bas` the HELLO program: bumps a seed in the text file `SEED`, POKEs it to `$0300`,
  then `BRUN AFTERDUSK`.
- `tools/` generators (`gen_tables.py`, `gen_art.py`), `bootstrap.sh`, FloppyEmu tools.
- `vendor/dos33-master-jan83.dsk` the base disk image (see `THIRD-PARTY-NOTICES.md`).
- `tests/` host tests on the py65 simulator (`sim.py`), emulator tests in `tests/mame/`.

## Shared maps

Memory:

| Range | Use |
|---|---|
| `$10`–`$1F` | drawing parameters and scratch (`hires.s`) |
| `$20`–`$2F` | core state: `RNG` `$20`, `TICKS` `$22`, `DISP` `$24` |
| `$30`–`$3F` | sprite engine |
| `$40`–`$7F` | private to the running effect |
| `$0300`–`$0301` | seed from HELLO |
| `$0310`–`$031F` | status block for tests |
| `$0800`–`$1FFF` | `FXRAM`, private to the running effect |
| `$2000` / `$4000` | hi-res page 1 / page 2 |
| `$6000`–`$95FF` | the program (13,824 bytes max) |
| `$D000`–`$FFEF` | language card bank 1: pre-shifted sprites, built at startup |

Status block: `$0310` current effect (0–5, `$FF` before the first), `$0311` effects started,
`$0312`/`$0313` steps since boot, `$0314` 1 = vertical-blank pacing, `$0315` 1 = IIc Plus.

Effect ids: 0 Flying Toasters, 1 Warp, 2 Starry Night, 3 Zot!, 4 Can of Worms, 5 Lissajous.

Each effect's step must finish inside its ticks on a 1 MHz IIc (`tests/fxcommon.py`
checks the worst step against `ticks × 17,030 − 300` cycles and the median against 85% of
that). When an effect can't keep up, it gets fewer objects, never a slower rate. Final counts:

- Flying Toasters: 4 toasters and 3 slices of toast (7 toasters were planned).
- Warp: 64 stars (70 were planned).
- Starry Night: up to 85 stars (about 90 were planned; star records must fit one 8-bit index).

## Never

- Never read or write `$C030`–`$C03F`. After Dusk is silent.
- Never commit Apple ROM images or Berkeley Systems artwork. The toaster is an original drawing.
- Never build the disk from scratch; always start from the vendored master.
- Never set bit 7 of a screen byte.
- Never use interrupt-driven code; interrupts stay masked (`SEI`).
