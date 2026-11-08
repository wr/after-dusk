# Third-Party Notices

This project's own code is MIT-licensed (see [LICENSE](LICENSE), Copyright (c) 2026 Wells Riley).
The MIT grant covers Wells's original work only. The build and the release disk also use
third-party material that Wells does not own and cannot relicense. This file lists each piece, who
holds the copyright, its license status, and how it's used.

## Apple DOS 3.3 System Master (January 1983)

- File: `vendor/dos33-master-jan83.dsk` (143,360 bytes)
- SHA-256: `70986935d95c4a918852700364ac107607eb861a7d93a69c2b5caf44a696b17a`
- Copyright: (c) Apple Computer, Inc.
- License / status: Apple's copyrighted operating system. Apple has never placed DOS 3.3 in the
  public domain or issued a redistribution license. It is distributed widely across the
  retrocomputing community by convention, not by permission: the same January 1983 System Master
  is bundled by the AppleWin emulator and hosted openly by the Internet Archive and the Asimov
  archive. It is included here in good faith for interoperability and preservation, with no claim
  of ownership and no affiliation with Apple, and will be removed on a rights holder's request.
- In repo: yes.
- In release: yes. `build.sh` copies this master, replaces its `HELLO` program, and adds
  `AFTERDUSK`, `FX`, `FX2` and `SEED` to produce `AFTERDUSK.dsk`. The DOS 3.3 boot code and file system
  in `AFTERDUSK.dsk` are Apple's.

## dos33fsprogs (build tool only)

- Source: https://github.com/deater/dos33fsprogs by Vince Weaver.
- License / status: GPL. Used only as a host build tool (`dos33`, `tokenize_asoft`), which
  `tools/bootstrap.sh` clones and builds into `.tools/`.
- In repo: no. In release: no. These programs write our files into the disk image; none of their
  own code is copied into `AFTERDUSK.dsk`.

## Tools referenced but not bundled

- cc65 (`ca65` / `ld65`), the 6502 assembler and linker. zlib license.
- MAME, the emulator used for tests. Its own licenses. Apple ROM images for it are never in this
  repository.
- py65, pytest, Pillow, installed into `.tools/venv` for tests. Their own licenses.

`tools/femu-sd` is Wells's own tool, copied from https://github.com/wr/floppyemu-sd.

## Effects modelled on After Dark

After Dark and its modules (Flying Toasters, Rose, Fish! and the rest) are Berkeley Systems'
work and trademarks. After Dusk is an unaffiliated tribute: every effect here is new code written
from watching the originals run, and no Berkeley Systems code, artwork or sound is included. The
toaster, the fish, the other sea creatures and the sea floor are original drawings. Rose follows the original module's method as described (not
copied) by the after-dark project, https://github.com/Vortitron/after-dark.
