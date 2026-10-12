#!/usr/bin/env python3
"""Keep your board's identity when flashing with a programmer.

A dump of your own SPI chip holds board-specific data in the first 0x250000 bytes
(flash descriptor, ME, and NVRAM with the DMI serial/UUID and the onboard LAN MAC).
The ASRock ROM ships blank NVRAM.  This takes 0x000000-0x24FFFF from your dump and
0x250000-0x7FFFFF (the BIOS code, where the TPM mod lives) from the modded image.

Usage: merge_nvram.py --dump my_chip_dump.bin --mod Z97MOCF_TPM2_8MB.bin --out flash_me.bin

Read the chip at least twice and compare the dumps before trusting them (a bad socket
contact gives silently truncated reads that are all 0xFF from some offset onward).
Setup settings stored in the old NVRAM come along too; clear CMOS after flashing if
the board does not POST."""
import argparse

SPLIT = 0x250000

ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
ap.add_argument('--dump', required=True); ap.add_argument('--mod', required=True); ap.add_argument('--out', required=True)
a = ap.parse_args()
dump = open(a.dump, 'rb').read(); mod = open(a.mod, 'rb').read()
assert len(dump) == len(mod) == 0x800000, "both files must be 8 MiB"
ff_tail = len(dump) - len(dump.rstrip(b'\xFF'))
if ff_tail > 0x100000:
    raise SystemExit(f"dump ends in {ff_tail:#x} bytes of 0xFF - probably a bad read, re-read the chip")
assert dump[0x10:0x14] == b'\x5a\xa5\xf0\x0f', "dump has no Intel flash descriptor signature"
open(a.out, 'wb').write(dump[:SPLIT] + mod[SPLIT:])
print(f"wrote {a.out}: dump[0:{SPLIT:#x}] + mod[{SPLIT:#x}:]")
