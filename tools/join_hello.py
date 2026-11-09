"""Append the boot splash's machine code to the tokenized HELLO program.

HELLO.tok is a two-byte length, then the program as it sits in memory from
$0801. The machine code is linked for SPLASH_ADDR, so pad up to it and append;
DOS loads the whole file and Applesoft keeps its variables after the end of it.
"""
import sys

SPLASH_ADDR = 0x0B00
BASIC_START = 0x0801

tok_path, bin_path = sys.argv[1:3]
tok = bytearray(open(tok_path, "rb").read())
code = open(bin_path, "rb").read()
prog = tok[2:]
room = SPLASH_ADDR - BASIC_START
if len(prog) > room:
    raise SystemExit(f"join_hello: HELLO is {len(prog)} bytes, room for {room}")
image = bytes(prog) + bytes(room - len(prog)) + code
open(tok_path, "wb").write(len(image).to_bytes(2, "little") + image)
print(f"join_hello: HELLO file is {len(image)} bytes, ends at ${BASIC_START + len(image):04X}")
