#!/bin/bash
# Put the built disk image on a FloppyEmu SD card.
#
# Thin wrapper: the real tool is femu-sd (in this directory, maintained at
# https://github.com/wr/floppyemu-sd), which handles the FloppyEmu "file not
# contiguous" problem properly. This wrapper defaults the image to this
# project's build output.
#
#   tools/install-sd.sh                     push build/AFTERDUSK.dsk
#   tools/install-sd.sh other.dsk           push something else
#   tools/install-sd.sh list|check|repair|eject
set -u
here=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
    list|check|repair|eject) exec "$here/femu-sd" "$@" ;;
    "") exec "$here/femu-sd" push "$here/../build/AFTERDUSK.dsk" ;;
    *)  exec "$here/femu-sd" push "$@" ;;
esac
