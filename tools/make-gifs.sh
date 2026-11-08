#!/bin/bash
# Record every effect in MAME and turn each into an animated GIF for the README.
#   tools/make-gifs.sh            # all effects
#   tools/make-gifs.sh 0 12       # just these ids
# Needs the emulator ROMs (tests/README.md) and a built disk. Frames go to
# build/mame/movie/fx<id>/, GIFs to docs/screenshots/<name>.gif.
set -eu
cd "$(dirname "$0")/.."
[ -d .tools/roms/apple2c ] || { echo "no emulator ROMs in .tools/roms (see tests/README.md)"; exit 1; }
ids=("$@")
[ ${#ids[@]} -gt 0 ] || ids=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14)

record() {
  local id=$1 d=build/mame/movie/fx$1
  rm -rf "$d"
  mkdir -p "$d"/snap "$d"/cfg "$d"/nvram
  AD_FX=$id AD_WAIT=${AD_WAIT:-2} AD_SECS=${AD_SECS:-10} SDL_VIDEODRIVER=dummy \
    mame apple2c -rompath .tools/roms -flop1 build/AFTERDUSK.dsk \
    -autoboot_script tests/mame/movie.lua -nothrottle -seconds_to_run 400 \
    -sound none -video none -skip_gameinfo \
    -cfg_directory "$d/cfg" -nvram_directory "$d/nvram" \
    -snapshot_directory "$d/snap" -diff_directory "$d" > "$d/log" 2>&1
  grep -q '^PASS' "$d/log" || { echo "fx$id: recording failed (see $d/log)"; return 1; }
}

# Four emulators at a time.
pids=()
for id in "${ids[@]}"; do
  record "$id" & pids+=($!)
  if [ ${#pids[@]} -ge 4 ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
done
wait

for id in "${ids[@]}"; do
  .tools/venv/bin/python tools/gif.py "$id" build/mame/movie/fx$id/snap docs/screenshots
done
