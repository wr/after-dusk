#!/bin/bash
# Run one emulator test.
#   tests/mame/run.sh <driver> <script.lua> <seconds> [disk]
# Prints the script's output. Exits 0 when the script printed PASS lines and
# no FAIL line, 1 on any FAIL (or no PASS), 77 when the ROMs are missing.
set -u
cd "$(dirname "$0")/../.."
drv=$1 script=$2 secs=$3 disk=${4:-build/AFTERDUSK.dsk}

if [ ! -d .tools/roms/"$drv" ] && [ ! -d .tools/roms/apple2c ]; then
  echo "SKIP: no emulator ROMs in .tools/roms (see tests/README.md)"
  exit 77
fi

out=build/mame
mkdir -p "$out"/cfg "$out"/nvram "$out"/snap "$out"/diff "$out"/logs
log="$out/logs/$(basename "$script" .lua).log"

SDL_VIDEODRIVER=dummy mame "$drv" -rompath .tools/roms -flop1 "$disk" \
  -autoboot_script "$script" -nothrottle -seconds_to_run "$secs" \
  -sound none -video none -skip_gameinfo \
  -cfg_directory "$out/cfg" -nvram_directory "$out/nvram" \
  -snapshot_directory "$out/snap" -diff_directory "$out/diff" > "$log" 2>&1
grep -E '^(PASS|FAIL|INFO)' "$log"
if grep -q '^FAIL' "$log" || ! grep -q '^PASS' "$log"; then
  echo "(full log: $log)"
  exit 1
fi
exit 0
