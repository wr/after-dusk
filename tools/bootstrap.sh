#!/bin/bash
# Set up the local tools this project needs, all inside .tools/ (gitignored):
#   .tools/venv          Python with py65, pytest and Pillow (host tests, art preview)
#   .tools/dos33fsprogs  dos33 + tokenize_asoft, pinned (writes files into the disk image)
# cc65 (ca65/ld65) and MAME are expected on PATH.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)

python3 -m venv .tools/venv
.tools/venv/bin/pip install -q -r requirements-test.txt

# Same pinned commit and build steps as the Apple II terminal project.
DOS33_COMMIT=78fc3bd4b24a6b792f49f311e85412e0cccc272c
DEST="$root/.tools/dos33fsprogs"
if [ ! -d "$DEST/.git" ]; then
  git clone -q https://github.com/deater/dos33fsprogs.git "$DEST"
fi
git -C "$DEST" fetch -q origin "$DOS33_COMMIT"
git -C "$DEST" checkout -q --detach "$DOS33_COMMIT"
make -s -C "$DEST/utils/dos33fs-utils" >/dev/null
make -s -C "$DEST/utils/asoft_basic-utils" >/dev/null
echo "dos33fsprogs at $(git -C "$DEST" rev-parse --short HEAD)"
.tools/venv/bin/pytest --version
