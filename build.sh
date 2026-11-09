#!/bin/bash
# Build After Dusk: assemble, link, and write the disk image.
#   ./build.sh                       -> build/AFTERDUSK.dsk
#   FX_TICKS=120 OUT=build/AFTERDUSK-test.dsk ./build.sh   (short effects, for tests)
#   FISH_HOP=2 BUILD_DIR=build/hop2 ./build.sh   Fish! with 2-dot hops (4 is the
#                                    default); BUILD_DIR keeps the files apart
#   ONLY_FX=14 OUT=build/FISH.dsk ./build.sh   a disk that shows one effect from
#                                    power-on (default -1: all of them)
# Needs ca65/ld65 on PATH and tools/bootstrap.sh run once (dos33fsprogs, venv).
set -euo pipefail
cd "$(dirname "$0")"

FX_TICKS="${FX_TICKS:-10800}"
FISH_HOP="${FISH_HOP:-4}"
ONLY_FX="${ONLY_FX:--1}"
BUILD_DIR="${BUILD_DIR:-build}"
OUT="${OUT:-$BUILD_DIR/AFTERDUSK.dsk}"
DOS33FSPROGS="${DOS33FSPROGS:-.tools/dos33fsprogs}"
DOS33="$DOS33FSPROGS/utils/dos33fs-utils/dos33"
TOK="$DOS33FSPROGS/utils/asoft_basic-utils/tokenize_asoft"
PY=.tools/venv/bin/python
[ -x "$DOS33" ] || { echo "dos33fsprogs missing: run tools/bootstrap.sh" >&2; exit 1; }

# The disk is the vendored DOS 3.3 System Master with HELLO replaced. Never
# build an image from scratch: master-based images are proven on real drives
# and the FloppyEmu.
BASE=vendor/dos33-master-jan83.dsk
OBJ="$BUILD_DIR/obj"
mkdir -p "$OBJ"
# The linker layout names its output files; point them at BUILD_DIR.
sed "s#build/#$BUILD_DIR/#" after-dusk.cfg > "$OBJ/after-dusk.cfg"

# Generated sources: each tools/gen_*.py writes its own src/*.inc.
for gen in tools/gen_*.py; do
  "$PY" "$gen"
done

# main.s links first so `start` sits at $6000.
objs=()
for src in src/main.s $(ls src/*.s | grep -v '^src/main.s$'); do
  o="$OBJ/$(basename "$src" .s).o"
  ca65 --cpu 65C02 -g -I src -D FX_TICKS="$FX_TICKS" -D FISH_HOP="$FISH_HOP" -D ONLY_FX="$ONLY_FX" -o "$o" "$src"
  objs+=("$o")
done
ld65 -C "$OBJ/after-dusk.cfg" -Ln "$BUILD_DIR/afterdusk.lbl" -m "$BUILD_DIR/afterdusk.map" -o "$BUILD_DIR/afterdusk.bin" "${objs[@]}"

# The linker writes the resident program and the three effects files,
# $BUILD_DIR/fx.bin, fx2.bin and fx3.bin (all loaded at $4000), and refuses anything
# that outgrows its area (after-dusk.cfg).
size=$(wc -c < "$BUILD_DIR/afterdusk.bin" | tr -d ' ')
fxsize=$(wc -c < "$BUILD_DIR/fx.bin" | tr -d ' ')
fx2size=$(wc -c < "$BUILD_DIR/fx2.bin" | tr -d ' ')
fx3size=$(wc -c < "$BUILD_DIR/fx3.bin" | tr -d ' ')

"$TOK" < basic/hello.bas > "$OBJ/HELLO.tok"
"$PY" tools/join_hello.py "$OBJ/HELLO.tok" "$BUILD_DIR/splash.bin"
printf '\xb0\x8d' > "$OBJ/SEED.txt"           # "0" + Return, high-bit ASCII

cp "$BASE" "$OUT"
"$DOS33" "$OUT" UNLOCK HELLO >/dev/null
"$DOS33" -y "$OUT" DELETE HELLO >/dev/null
"$DOS33" -y "$OUT" SAVE A "$OBJ/HELLO.tok" HELLO >/dev/null
"$DOS33" -y -a 0x6000 "$OUT" BSAVE "$BUILD_DIR/afterdusk.bin" AFTERDUSK >/dev/null
"$DOS33" -y -a 0x4000 "$OUT" BSAVE "$BUILD_DIR/fx.bin" FX >/dev/null
"$DOS33" -y -a 0x4000 "$OUT" BSAVE "$BUILD_DIR/fx2.bin" FX2 >/dev/null
"$DOS33" -y -a 0x4000 "$OUT" BSAVE "$BUILD_DIR/fx3.bin" FX3 >/dev/null
"$DOS33" -y -a 0x8000 "$OUT" BSAVE "$BUILD_DIR/paint.bin" PAINT >/dev/null
"$DOS33" -y "$OUT" SAVE T "$OBJ/SEED.txt" SEED >/dev/null
test "$(wc -c < "$OUT" | tr -d ' ')" = 143360
echo "built $OUT ($size bytes of program, $fxsize + $fx2size + $fx3size of effects, FX_TICKS=$FX_TICKS)"
