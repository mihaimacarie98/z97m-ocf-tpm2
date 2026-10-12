#!/usr/bin/env python3
"""Sanity-check an 8 MiB Z97M OC Formula image: FV header checksums, every FFS header/body
checksum (outer FV, PEI FV, decompressed nested DXE FV), and the TPM pieces of the mod.
Usage: verify_image.py IMAGE [--stock Z97MOCF2.50]"""
import argparse, struct, sys
from uefi_firmware import efi_compressor

NESTED = bytes.fromhex('2f7c71ae421a2b4f886178b79ca07e07')
TPM_GUIDS = {'TrEEPei': '20341ce2-d448-4b5e-9411-fe9826402dcf', 'AmiTpm20PlatformPei': '0d8039ff-49e9-4cc9-a806-bb7c31b0bcb0',
             'TrEEDxe': '12345756-fca3-49bd-8dae-c7bae8389aff', 'Tpm20PlatformDxe': '0718ad81-f26a-4850-a6ec-f268e309d707',
             'Tpm20Acpi': '4c8bdf60-2085-4577-8a46-96cb180967bc', 'TpmBootDxe (V11)': '78c18031-b5ae-4112-a635-70285b920a2f'}

def le(s):
    p = s.split('-'); return struct.pack('<IHH', int(p[0], 16), int(p[1], 16), int(p[2], 16)) + bytes.fromhex(p[3] + p[4])

def walk(img, base, lim):
    hl = struct.unpack('<H', img[base + 0x30:base + 0x32])[0]; o = base + hl; out = []
    while o < base + lim - 24:
        if img[o:o + 16] == b'\xFF' * 16: break
        sz = int.from_bytes(img[o + 20:o + 23], 'little'); out.append((o, bytes(img[o:o + 16]), img[o + 18], sz)); o = (o + sz + 7) & ~7
    return out

def check_fv(img, base, lim, label):
    hl = struct.unpack('<H', img[base + 0x30:base + 0x32])[0]
    ok = sum(struct.unpack(f'<{hl // 2}H', img[base:base + hl])) & 0xFFFF == 0
    files = walk(img, base, lim)
    for o, g, ft, sz in files:
        t = bytearray(img[o:o + 24]); t[17] = 0; t[23] = 0; t[16] = 0
        if (sum(t) + img[o + 16]) % 256: ok = False; print(f"  header checksum bad @0x{o:X}")
        if img[o + 19] & 0x40 and ft != 0xF0 and (img[o + 17] + sum(img[o + 24:o + sz])) % 256: ok = False; print(f"  body checksum bad @0x{o:X}")
    print(f"[{label}] {len(files)} files, {'OK' if ok else 'ERRORS'}")
    return ok, files

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('image'); ap.add_argument('--stock')
    a = ap.parse_args()
    img = open(a.image, 'rb').read(); assert len(img) == 0x800000, "expect 8 MiB image (strip the 4 KiB ASRock header)"
    ok1, _ = check_fv(img, 0x250000, 0x490000, 'main FV')
    ok2, pei = check_fv(img, 0x700000, 0xFE000, 'PEI FV')
    i = img.find(NESTED); ss = int.from_bytes(img[i + 24:i + 27], 'little')
    dec = bytes(efi_compressor.LzmaDecompress(img[i + 33:i + 24 + ss], ss - 9))
    fvlen = struct.unpack('<Q', dec[4 + 0x20:4 + 0x28])[0]
    ok3, dxe = check_fv(dec[4:4 + fvlen], 0, fvlen, f'nested DXE FV 0x{fvlen:X}')
    have = {g for _, g, _, _ in pei + dxe}
    for n, gs in TPM_GUIDS.items(): print(f"  {n:22s} {'present' if le(gs) in have else 'MISSING'}")
    abi = dec.find(le('9f3a0016-ae55-4288-829d-d22fd344c347')); d = dec.find(b'DSDT', abi)
    dsdt = dec[d:d + struct.unpack('<I', dec[d + 4:d + 8])[0]]
    yn = lambda c: 'yes' if c else 'no'
    msft, tpmf, cks = b'MSFT0101' in dsdt, b'\x08TPMF\x01' in dsdt, sum(dsdt) & 0xFF == 0
    print(f"  DSDT 0x{len(dsdt):X}: MSFT0101={yn(msft)}, TPMF=One={yn(tpmf)}, checksum={'ok' if cks else 'BAD'}")
    if a.stock:
        s = open(a.stock, 'rb').read(); s = s[0x1000:] if len(s) == 0x801000 else s
        for lo, hi, n in ((0, 0x250000, 'descriptor/ME/NVRAM'), (0x6E0000, 0x700000, 'FIT/boot block'), (0x7FE000, 0x800000, 'reset vector FV')):
            print(f"  {n:20s} {'identical to stock' if s[lo:hi] == img[lo:hi] else 'DIFFERS from stock'}")
    sys.exit(0 if ok1 and ok2 and ok3 else 1)

if __name__ == '__main__':
    main()
