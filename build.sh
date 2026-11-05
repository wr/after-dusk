#!/bin/bash
# Build After Dusk: assemble, link, and write the disk image.
#   ./build.sh                       -> build/AFTERDUSK.dsk
#   FX_TICKS=120 OUT=build/AFTERDUSK-test.dsk ./build.sh   (short effects, for tests)
# Needs ca65/ld65 on PATH and tools/bootstrap.sh run once (dos33fsprogs, venv).
set -euo pipefail
cd "$(dirname "$0")"

FX_TICKS="${FX_TICKS:-10800}"
OUT="${OUT:-build/AFTERDUSK.dsk}"
DOS33FSPROGS="${DOS33FSPROGS:-.tools/dos33fsprogs}"
DOS33="$DOS33FSPROGS/utils/dos33fs-utils/dos33"
TOK="$DOS33FSPROGS/utils/asoft_basic-utils/tokenize_asoft"
PY=.tools/venv/bin/python
[ -x "$DOS33" ] || { echo "dos33fsprogs missing: run tools/bootstrap.sh" >&2; exit 1; }

# The disk is the vendored DOS 3.3 System Master with HELLO replaced. Never
# build an image from scratch: master-based images are proven on real drives
# and the FloppyEmu.
BASE=vendor/dos33-master-jan83.dsk
OBJ=build/obj
mkdir -p "$OBJ"

# Generated sources, once their generators exist.
for gen in tools/gen_tables.py tools/gen_art.py; do
  [ -f "$gen" ] && "$PY" "$gen"
done

# main.s links first so `start` sits at $6000.
objs=()
for src in src/main.s $(ls src/*.s | grep -v '^src/main.s$'); do
  o="$OBJ/$(basename "$src" .s).o"
  ca65 --cpu 65C02 -g -I src -D FX_TICKS="$FX_TICKS" -o "$o" "$src"
  objs+=("$o")
done
ld65 -C after-dusk.cfg -Ln build/afterdusk.lbl -m build/afterdusk.map -o build/afterdusk.bin "${objs[@]}"

# The linker writes the resident program and build/fx.bin (every effect, for
# $2000) and refuses anything that outgrows its area (after-dusk.cfg).
size=$(wc -c < build/afterdusk.bin | tr -d ' ')
fxsize=$(wc -c < build/fx.bin | tr -d ' ')

"$TOK" < basic/hello.bas > "$OBJ/HELLO.tok"
printf '\xb0\x8d' > "$OBJ/SEED.txt"           # "0" + Return, high-bit ASCII

cp "$BASE" "$OUT"
"$DOS33" "$OUT" UNLOCK HELLO >/dev/null
"$DOS33" -y "$OUT" DELETE HELLO >/dev/null
"$DOS33" -y "$OUT" SAVE A "$OBJ/HELLO.tok" HELLO >/dev/null
"$DOS33" -y -a 0x6000 "$OUT" BSAVE build/afterdusk.bin AFTERDUSK >/dev/null
"$DOS33" -y -a 0x2000 "$OUT" BSAVE build/fx.bin FX >/dev/null
"$DOS33" -y "$OUT" SAVE T "$OBJ/SEED.txt" SEED >/dev/null
test "$(wc -c < "$OUT" | tr -d ' ')" = 143360
echo "built $OUT ($size bytes of program, $fxsize of effects, FX_TICKS=$FX_TICKS)"
