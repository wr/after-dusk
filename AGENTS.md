# AGENTS.md

Guidance for coding agents (Claude Code via `CLAUDE.md`, Codex) working in this repository.

## Source of truth
- GitHub: github.com/wr/after-dusk (created at the first release)
- Branch prefix: wells/
- PR mode: none (commit to main)

## What this is

After Dusk is a boot disk for the Apple IIc that goes straight into an After Dark-style screen saver
randomizer. It cycles black-and-white hi-res effects (see Effect ids below) in random order, about
3 minutes each, until the machine is switched off. Any key skips to the next effect. It is silent.
It also runs on an enhanced IIe with 128K (tested in MAME), where `timing_init` finds no
vertical-blank latch, so every effect is paced by the cycle-counted fallback.

The resident 65C02 program, `AFTERDUSK`, loads at `$6000` from a DOS 3.3 disk. Every effect is
linked into one of two more files, `FX` (effects 0-13) and `FX2` (Fish!, with its art and sea
floor), which HELLO loads at `$2000` in turn just before `BRUN AFTERDUSK`. After Dusk copies
them to aux memory at start-up (`FX` at `$2000`, `FX2` at `$6000`), and copies each effect from
there into the overlay slot at `$8800` when its turn comes, so the disk is never touched after
boot. Fish! also copies its drawing code into FXRAM and the language card when it starts, and
reads its art from `FX2` in aux as it draws.

## Commands

```bash
tools/bootstrap.sh                 # once: .tools/venv (py65, pytest, Pillow) + .tools/dos33fsprogs
./build.sh                         # -> build/AFTERDUSK.dsk (Fish! with 4-dot hops)
FISH_HOP=2 BUILD_DIR=build/hop2 ./build.sh             # Fish! with the original's 2-dot hops
ONLY_FX=14 OUT=build/FISH.dsk ./build.sh               # a disk that shows one effect from power-on
FX_TICKS=120 OUT=build/AFTERDUSK-test.dsk ./build.sh   # 2-second effects, for emulator tests
.tools/venv/bin/pytest tests -q    # host tests (py65 simulator) + emulator tests if ROMs exist
tests/mame/run.sh apple2c tests/mame/boot.lua 30       # one emulator test
tools/make-gifs.sh                 # the README's animations: docs/screenshots/*.gif, from MAME
tools/install-sd.sh                # put build/AFTERDUSK.dsk on a FloppyEmu SD card
```

Needs `ca65`/`ld65` (cc65) and `mame` on PATH. Emulator ROM images are not in the repo; see
`tests/README.md`.

## Layout

- `src/` 65C02 sources (ca65). `main.s` links first so `start` is at `$6000`.
  `config.inc` holds every shared address below. `after-dusk.cfg` is the linker layout.
- `src/fx_*.s` one effect each, in its own segment `FXn` (n = its id), starting with
  `jmp init` and `jmp step`. Fish! (`fx_fish.s`) includes `fish_draw.inc` (its cache engine:
  pre-shifted creatures composed row by row, every piece paid for before it runs) and
  `fish_init.inc` (its init-only code). To add one: a segment and an `OVLn` area in
  `after-dusk.cfg`, loaded from `FXFILE2` (`FX2`) rather than `FXFILE`; in `main.s` the
  `.import __FXn_LOAD__, __FXn_SIZE__` line and entries in `fx_table` and `fx_slow`; `NFX` in
  `config.inc` and `tests/fxcommon.py`. Both files are nearly full (FX 15,970 and FX2 16,021 of
  16,384 bytes): another effect needs room made or a third file.
- `basic/hello.bas` the HELLO program: bumps a seed in the text file `SEED`, POKEs it to `$0300`,
  then `BLOAD FX` and `BRUN AFTERDUSK`.
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
| `$80`–`$8F` | drawing scratch (`hires.s`); the loader's pointers between effects |
| `$90`–`$9F` | sprite-engine scratch |
| `$0300`–`$0301` | seed from HELLO |
| `$0310`–`$031F` | status block for tests |
| `$0800`–`$1FFF` | `FXRAM`, private to the running effect (Fish!: its live background `$0800`, drawing code `$0E00`, state `$1C00`) |
| `$2000` / `$4000` | hi-res page 1 / page 2 (the FX files sit here until start-up copies them; Fish! fills page 2 with its caches and kernels, and shows page 1 only) |
| `$6000`–`$87FF` | the resident program (10,240 bytes max) |
| `$8800`–`$95FF` | overlay slot: the running effect's code (3,584 bytes max per effect) |
| `$D000`–`$F5FF` | language card bank 1: pre-shifted sprites and Warp's tables, built at startup |
| `$F600`–`$F6FF` | language card: `aux_fetch` and `aux_copy`, the copy loops that read aux memory |
| `$F700`–`$FFF9` | language card: Fish!'s code that reads aux memory (copied from FX2 when it starts); `$FFFA`–`$FFFF` are the vectors, never written |
| aux `$0800`–`$1FFF`, `$A000`–`$BFFF` | Fish!'s shift tables and a mirrored copy of its art, built when it starts |
| aux `$2000`–`$5FFF` | the FX file: effects 0-13, one after another (16K max) |
| aux `$6000`–`$9FFF` | the FX2 file: Fish!'s code, art and sea floor, read in place (16K max) |

Status block: `$0310` current effect (`$FF` before the first), `$0311` effects started,
`$0312`/`$0313` steps since boot, `$0314` 1 = vertical-blank pacing, `$0315` 1 = IIc Plus.

Effect ids: 0 Flying Toasters, 1 Warp, 2 Starry Night, 3 Zot!, 4 Can of Worms, 5 Lissajous,
6 Nightlines, 7 String Theory, 8 Rose, 9 Doodles, 10 Shapes, 11 Spheres, 12 Bouncing Ball,
13 Rainstorm, 14 Fish!.

Each effect's step must finish inside its ticks on a 1 MHz IIc (`tests/fxcommon.py`
checks the worst step against `ticks × 17,030 − 300` cycles and the median against 85% of
that). When an effect can't keep up, it gets fewer objects, never a slower rate (Flying Toasters
is the one exception, below). A step that can
take longer than one frame must call `vbl_poll` during its work (the sprite engine does it for
every sprite): the IIc's vertical-blank flag remembers only one blank, and `wait_ticks` counts
frames to a deadline. `tests/mame/pacing.lua` checks every effect's real rate. Final counts:

- Flying Toasters: 4 toasters and 3 slices of toast (8 objects were planned; the original flies
  11), at about 14.3 updates a second instead of 15. With everything on screen the worst update
  fits its 4 ticks (65,771 cycles); with objects clipped at the screen edges an update can reach
  about 93,000 and slip a frame. Keeping 7 objects was chosen over a steady 15 a second, so its
  `test_budget` allows the worst step 6 ticks and the median all 4, and `pacing.lua` allows 8%
  under its rate. No other effect may do this.
- Warp: 64 stars (70 were planned).
- Starry Night: up to 85 stars (about 90 were planned; star records must fit one 8-bit index).
- Nightlines: 8 generations kept (the original keeps 20, drawing 30-35 lines a second against
  12 steps here, so the ends go 7-10.5 dots a step to match its speed); ends bounce off the edges
  of the whole screen; a step that rubs out and draws 8 lines corner to corner (about 79,000
  cycles) still fits 5 ticks.
- String Theory: 2 ribbons of 20 strings at 6 ticks (the original draws 30-35 strings a second
  against 10 steps here, so the ribbons move 2.8-4.2 dots a step to match its speed); its own
  unrolled line routine (`str_line`), about twice as fast as `fline` on long lines.
- Shapes: sizes capped (height x (width + 161) <= 13,851) so the biggest fills in 3 ticks.
- Spheres: radius 12-44 (58 was planned) so the biggest circle fills in 4 ticks.
- Rainstorm: 45 drops (55 were planned) at 3 ticks.
- Fish!: 3 creatures (10 in the original; a Seaweed counts as one), all 14 kinds, 4-dot hops on
  beats twice the original's (the same speed in coarser steps; `FISH_HOP=2` builds the original's
  2-dot hops, which hold fewer). It steps every tick: a lone hop at sea is about 12,000 cycles of
  the tick's 17,030, over the floor 19,000, a crossing more, so a tick holds one hop and the
  count is set by hops falling due together. Each hop keeps within one tick of its beat (most
  start a tick early) except, rarely (about once in five minutes), when three creatures cross
  over the floor; every step still fits its tick, and without a vertical blank the step pads
  itself to a tick (`tests/mame/fish_rate.lua`).

Speeds follow the originals, timed from video of the real After Dark modules (Afterglow);
where the IIc draws fewer updates a second, each update moves further.

## Never

- Never read or write `$C030`–`$C03F`. After Dusk is silent.
- Never commit Apple ROM images or Berkeley Systems artwork. The toaster is an original drawing.
- Never build the disk from scratch; always start from the vendored master.
- Never set bit 7 of a screen byte.
- Never use interrupt-driven code; interrupts stay masked (`SEI`).
