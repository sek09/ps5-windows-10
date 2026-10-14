#!/usr/bin/env python3
"""Make an "XP" copy of the PS5 Linux loader that reads its kernel command line from cmdl-xp.txt
(instead of cmdline.txt) on the Linux boot partition. That file carries "ps5vm=xp", so a tile that
sends this loader boots Linux straight into Windows XP, while the normal loader still boots the desktop.

usage: python3 patch_loader.py ps5-linux-loader.elf loader-xp.elf

Only the 11-byte file name changes ("cmdline.txt" -> "cmdl-xp.txt", same length). Tested with
loader v2.5 (sha256 9fc48733...bc49); other versions are patched if the string is found the same way."""
import hashlib, sys

TESTED = "9fc48733077145d1d204a4c9cdb879baaab1e711a604dd73af0dd4a807d6bc49"
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, "rb").read())
h = hashlib.sha256(d).hexdigest()
print("input sha256", h, "(tested v2.5)" if h == TESTED else "(untested version, continuing)")
# The path string sits in the import-name area, right after a ".sprx" module name and before "lseek".
needle = b".sprx\x00cmdline.txt\x00"
i = d.find(needle)
if i < 0 or d.find(needle, i + 1) >= 0:
    sys.exit("could not find exactly one cmdline.txt path string - not patching")
j = i + len(b".sprx\x00")
d[j:j + 11] = b"cmdl-xp.txt"
open(dst, "wb").write(d)
print("patched offset", hex(j), "->", dst)
