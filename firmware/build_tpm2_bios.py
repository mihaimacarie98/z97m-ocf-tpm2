#!/usr/bin/env python3
"""Build a TPM 2.0-capable BIOS for the ASRock Z97M OC Formula from official ASRock files.

Inputs (not redistributed here, download them yourself):
  --stock  Z97MOCF2.50   ASRock Z97M OC Formula P2.50 ROM  (8 MiB + 4 KiB capsule header)
  --donor  Z97Ex62.80A   ASRock Z97 Extreme6 P2.80A TPM2 beta ROM (same format)

What it does (AMI Aptio IV):
  PEI FV   - replaces the 5-module TCG PEI cluster with the donor's TPM2-aware builds,
             removes TpmClearOnRollbackPei, rebases the 3 XIP PE32 PEIMs to their new
             flash address, inserts TrEEPei + AmiTpm20PlatformPei into the big pad file.
  DXE FV   - (LZMA-compressed nested FV) replaces 8 TCG framework drivers, inserts
             TrEEDxe + Tpm20PlatformDxe + Tpm20Acpi, grows the FV 0xB0D000 -> 0xB56000.
  DSDT     - inside AmiBoardInfo: removes the TPM 1.2 stub Device/Scope, inserts a minimal
             Device(_SB.TPM) {_HID "MSFT0101", TIS @ 0xFED40000}, sets TPMF=One.
  All FFS/FV/ACPI checksums are recomputed; recompression is verified with the EDK2
  LZMA decoder.  Everything outside the main FV and the PEI cluster stays byte-identical
  (descriptor, ME, NVRAM, microcode, FIT, boot block).

Output for the reference inputs is byte-identical to the image tested on real hardware
(sha256 c6893a97275c1ed39000e7edeaa348c82ab97642668a9506ec69f1c043b4032c).

Requires: python3, pip install uefi_firmware   (only its EDK2 LzmaDecompress is used)
"""
import argparse, hashlib, lzma, struct, sys
from uefi_firmware import efi_compressor

STOCK_SHA = '4f896e21e5f817fde2c20c08ce7df5ca707dc8449613b9ac833d21eccd8db326'   # Z97MOCF2.50
DONOR_SHA = 'f096bc699880657902837245eb02743392d5e94e0e03f05ebdfa3d82174875e2'   # Z97Ex62.80A
RESULT_SHA = 'c6893a97275c1ed39000e7edeaa348c82ab97642668a9506ec69f1c043b4032c'

# module name -> FFS GUID (identical GUIDs in stock and donor)
GUIDS = {
    'TcgPlatformSetupPeiPolicy': '0fe9da53-043d-4265-a94d-fd77fede2eb4',
    'TcgPei':                    '34989d8e-930a-4a95-ab04-2e6cfdff6631',
    'TcgPeiplatform':            '6b844c5b-6b75-42ca-8e8e-1cb94412b59b',
    'AmiTcgPlatformPeiAfterMem': '9b3f28d5-10a6-46c8-ba72-bd40b847a71a',
    'AmiTcgPlatformPeiBeforeMem':'e9312938-e56b-4614-a252-cf7d2f377e26',
    'TpmClearOnRollbackPei':     'de9bf6a0-e353-4c5c-adb3-00fcb212d965',
    'TrEEPei':                   '20341ce2-d448-4b5e-9411-fe9826402dcf',
    'AmiTpm20PlatformPei':       '0d8039ff-49e9-4cc9-a806-bb7c31b0bcb0',
    'TcgDxe':                    '5e9caba3-f2b1-497a-adac-24f575e9cde9',
    'TcgPlatformSetupPolicy':    '196ca3d8-9a5a-4735-b328-8ffc1d93d188',
    'TcgDxeplatform':            '2688b232-9c02-4c12-be1f-857c0ff2aae3',
    'AmiTcgPlatformDxe':         'a29a63e3-e4e7-495f-8a6a-07738300cbb3',
    'TCGSmm':                    'fd93f9e1-3c73-46e0-b7b8-2bba3f718f6c',
    'TcgLegacy':                 '858ebe6f-360f-415b-b7dc-463aaeb03412',
    'AmiTcgNvflagSample':        '50f6096d-7c98-4c78-9a1d-c5a1833b6a88',
    'TpmClearOnRollback':        'fd2cb3f1-9520-4c24-bcb3-2c73f0c2b7ec',
    'TrEEDxe':                   '12345756-fca3-49bd-8dae-c7bae8389aff',
    'Tpm20PlatformDxe':          '0718ad81-f26a-4850-a6ec-f268e309d707',
    'Tpm20Acpi':                 '4c8bdf60-2085-4577-8a46-96cb180967bc',
    'AmiBoardInfo':              '9f3a0016-ae55-4288-829d-d22fd344c347',
}
NESTED_FV_FILE = bytes.fromhex('2f7c71ae421a2b4f886178b79ca07e07')  # ae717c2f-... (compressed DXE FV)
PAD_GUID = bytes.fromhex('856543e40979604ab5c6ecdea6ebfb54')

# iasl output of acpi/min_tpm.dsl: Device(_SB.TPM) {_HID "MSFT0101", _CID PNP0C31, _UID 1,
# _STR "TPM 2.0 Device", _STA 0x0F, _CRS Memory32Fixed(RW, 0xFED40000, 0x5000)}  (116 bytes)
MIN_TPM_AML = bytes.fromhex(
    '5b8242072e5f53425f54504d5f085f4849440d4d5346543031303100085f4349440c41d00c31085f55494401'
    '085f53545211210a1e540050004d00200032002e0030002000440065007600690063006500000014095f5354'
    '4100a40a0f085f43525311110a0e860900010000d4fe005000007900')

FLASH_BASE = 0xFF800000
PEI, PEISZ = 0x700000, 0xFE000            # PEI FV (flash offset, size)
OUTER, OUTERSZ = 0x250000, 0x490000       # main FV that holds the nested DXE FV file
NESTED_OLD, NESTED_NEW = 0xB0D000, 0xB56000
BIGPAD_SIZE = 0x37EE0
DSDT_STUB_OFF, DSDT_STUB_LEN = 0xFF1A, 0xB8 + 0x38F   # stock Device(LPCB.TPM) + Scope(...TPM)
DSDT_STOCK_LEN = 0x10AB2


def le(s):
    p = s.split('-')
    return struct.pack('<IHH', int(p[0], 16), int(p[1], 16), int(p[2], 16)) + bytes.fromhex(p[3] + p[4])

def g(name): return le(GUIDS[name])
def align4(x): return (x + 3) & ~3
def align8(x): return (x + 7) & ~7

def walk(img, base, limit):
    """[(offset, guid16, type, size)] of the FFS files in the FV at img[base:base+limit]."""
    hlen = struct.unpack('<H', img[base + 0x30:base + 0x32])[0]
    o = base + hlen; out = []
    while o < base + limit - 24:
        if img[o:o + 16] == b'\xFF' * 16: break
        sz = int.from_bytes(img[o + 20:o + 23], 'little')
        out.append((o, bytes(img[o:o + 16]), img[o + 18], sz))
        o = align8(o + sz)
    return out

def getfile(img, base, limit, guid16):
    for o, gg, ft, sz in walk(img, base, limit):
        if gg == guid16: return bytes(img[o:o + sz])
    raise KeyError(guid16.hex())

def fix_ffs(f):
    f = bytearray(f)
    if f[19] & 0x40:                                   # FFS_ATTRIB_CHECKSUM -> body checksum
        f[17] = (0x100 - sum(f[24:]) % 256) % 256
    t = bytearray(f[:24]); t[16] = 0; t[17] = 0; t[23] = 0
    f[16] = (0x100 - sum(t) % 256) % 256
    return bytes(f)

def rebase_pe32_in_ffs(ffs, new_file_flash_addr):
    """XIP PEIMs run in place: set ImageBase to the new flash address and re-apply relocs."""
    f = bytearray(ffs); o = 24
    while o < len(f) - 4:
        ssz = int.from_bytes(f[o:o + 3], 'little'); st = f[o + 3]
        if st == 0x10:                                 # EFI_SECTION_PE32
            img_off = o + 4
            new_base = (new_file_flash_addr + img_off) & 0xFFFFFFFF
            peoff = struct.unpack('<I', f[img_off + 0x3C:img_off + 0x40])[0]
            opt = img_off + peoff + 24
            assert struct.unpack('<H', f[opt:opt + 2])[0] == 0x10B
            old_base = struct.unpack('<I', f[opt + 0x1C:opt + 0x20])[0]
            delta = (new_base - old_base) & 0xFFFFFFFF
            struct.pack_into('<I', f, opt + 0x1C, new_base)
            relrva, relsz = struct.unpack('<II', f[opt + 0x88:opt + 0x90])
            assert relrva and relsz, "no reloc table"
            r = img_off + relrva; rend = r + relsz; applied = 0
            while r < rend:
                page, bsz = struct.unpack('<II', f[r:r + 8])
                if bsz < 8: break
                for k in range(8, bsz, 2):
                    e = struct.unpack('<H', f[r + k:r + k + 2])[0]
                    typ, off = e >> 12, e & 0xFFF
                    if typ == 3:                       # IMAGE_REL_BASED_HIGHLOW
                        a = img_off + page + off
                        v = struct.unpack('<I', f[a:a + 4])[0]
                        struct.pack_into('<I', f, a, (v + delta) & 0xFFFFFFFF); applied += 1
                    elif typ != 0:
                        raise Exception(f"reloc type {typ}")
                r += bsz
            return fix_ffs(bytes(f)), delta, applied
        o = align4(o + ssz)
    raise Exception("no PE32")

def mk_pad(size):
    h = bytearray(PAD_GUID) + bytearray(8)
    h[18] = 0xF0; h[19] = 0x00
    h[20:23] = size.to_bytes(3, 'little'); h[23] = 0xF8
    t = bytearray(h); t[16] = 0; t[17] = 0; t[23] = 0
    h[16] = (0x100 - sum(t) % 256) % 256
    h[17] = 0xAA
    return bytes(h) + b'\xFF' * (size - 24)

def nested_fv(img):
    """(file offset, decompressed section stream) of the compressed nested DXE FV."""
    i = img.find(NESTED_FV_FILE)
    ss = int.from_bytes(img[i + 24:i + 27], 'little')
    return i, bytes(efi_compressor.LzmaDecompress(img[i + 33:i + 24 + ss], ss - 9))

def load_rom(path, want_sha, label, force):
    raw = open(path, 'rb').read()
    sha = hashlib.sha256(raw).hexdigest()
    if sha != want_sha:
        msg = f"{label}: sha256 {sha} != expected {want_sha}"
        if not force: sys.exit(msg + "\n(use --force to try anyway; offsets are only validated for the reference files)")
        print("WARNING:", msg)
    if len(raw) == 0x801000: raw = raw[0x1000:]        # strip ASRock capsule header
    assert len(raw) == 0x800000, f"{label}: unexpected size {len(raw):#x}"
    return raw


def patch_dsdt(abi_ffs):
    """Return AmiBoardInfo FFS with the TPM 2.0 DSDT. DSDT must not grow (data follows it)."""
    ffs = bytearray(abi_ffs)
    off = ffs.find(b'DSDT')
    s = bytes(ffs[off:off + struct.unpack('<I', ffs[off + 4:off + 8])[0]])
    assert len(s) == DSDT_STOCK_LEN, f"DSDT length {len(s):#x}"
    assert s[DSDT_STUB_OFF:DSDT_STUB_OFF + 2] == b'\x5b\x82', "TPM 1.2 stub Device not where expected"
    assert s[DSDT_STUB_OFF + 0xB8:DSDT_STUB_OFF + 0xB9] == b'\x10', "TPM 1.2 stub Scope not where expected"
    n = bytearray(s[:DSDT_STUB_OFF] + MIN_TPM_AML + s[DSDT_STUB_OFF + DSDT_STUB_LEN:])
    assert n.count(b'\x08TPMF\x00') == 1
    k = n.find(b'\x08TPMF\x00'); n[k + 5] = 1           # Name(TPMF, Zero) -> One (hides TPMX reservation)
    struct.pack_into('<I', n, 4, len(n)); n[9] = 0; n[9] = (0x100 - sum(n) % 256) % 256
    assert sum(n) & 0xFF == 0
    ffs[off:off + len(n)] = n
    ffs[off + len(n):off + len(s)] = b'\x00' * (len(s) - len(n))
    print(f"DSDT: 0x{len(s):X} -> 0x{len(n):X}, MSFT0101 device inserted, TPMF=One")
    return fix_ffs(bytes(ffs))


def build(stock, donor):
    img = bytearray(stock)

    # ---------- PEI FV ----------
    sfiles = {gg: (o, sz) for o, gg, ft, sz in walk(stock, PEI, PEISZ)}
    order = ['TcgPlatformSetupPeiPolicy', 'TcgPei', 'TcgPeiplatform', 'AmiTcgPlatformPeiAfterMem', 'AmiTcgPlatformPeiBeforeMem']
    XIP = {'TcgPlatformSetupPeiPolicy', 'TcgPeiplatform', 'AmiTcgPlatformPeiBeforeMem'}
    cl_start = sfiles[g('TcgPlatformSetupPeiPolicy')][0]
    tcorb = sfiles[g('TpmClearOnRollbackPei')]
    cl_end = align8(tcorb[0] + tcorb[1])
    inregion = [gg for gg, (o, sz) in sfiles.items() if cl_start <= o < cl_end]
    assert len(inregion) == 6, f"unexpected files in PEI cluster region: {len(inregion)}"
    newreg = bytearray()
    for n in order:
        f = getfile(donor, PEI, PEISZ, g(n))
        start = align8(cl_start + len(newreg))
        newreg += b'\xFF' * (start - cl_start - len(newreg))
        if n in XIP:
            f, delta, nrel = rebase_pe32_in_ffs(f, FLASH_BASE + start)
            print(f"PEI  {n}: 0x{start:X}, rebased by 0x{delta:X} ({nrel} relocs)")
        else:
            print(f"PEI  {n}: 0x{start:X}")
        newreg += f
    padp = align8(cl_start + len(newreg))
    newreg += b'\xFF' * (padp - cl_start - len(newreg))
    padsz = cl_end - padp
    assert padsz >= 24 or padsz == 0
    if padsz: newreg += mk_pad(padsz)
    assert len(newreg) == cl_end - cl_start
    img[cl_start:cl_end] = newreg

    bigpad = next((o for o, gg, ft, sz in walk(stock, PEI, PEISZ) if ft == 0xF0 and sz == BIGPAD_SIZE), None)
    assert bigpad, "big PEI pad file not found"
    chunk = bytearray()
    for n in ('TrEEPei', 'AmiTpm20PlatformPei'):
        f = getfile(donor, PEI, PEISZ, g(n))
        start = align8(bigpad + len(chunk))
        chunk += b'\xFF' * (start - bigpad - len(chunk)) + f
        print(f"PEI  insert {n}: 0x{start:X} (0x{len(f):X} bytes)")
    ps = align8(bigpad + len(chunk))
    chunk += b'\xFF' * (ps - bigpad - len(chunk)) + mk_pad(bigpad + BIGPAD_SIZE - ps)
    assert len(chunk) == BIGPAD_SIZE
    img[bigpad:bigpad + BIGPAD_SIZE] = chunk

    # ---------- nested DXE FV ----------
    i, dec_old = nested_fv(stock)
    assert dec_old[3] == 0x17, "nested section is not an FV image"
    sn = dec_old[4:4 + NESTED_OLD]
    _, kdec = nested_fv(donor)
    kfvh = kdec.find(b'_FVH')
    ksz = struct.unpack('<Q', kdec[kfvh - 0x28 + 0x20:kfvh - 0x28 + 0x28])[0]
    kn = kdec[kfvh - 0x28:kfvh - 0x28 + ksz]

    repl = {g(n): getfile(kn, 0, len(kn), g(n)) for n in
            ['TcgDxe', 'TcgPlatformSetupPolicy', 'TcgDxeplatform', 'AmiTcgPlatformDxe',
             'TCGSmm', 'TcgLegacy', 'AmiTcgNvflagSample', 'TpmClearOnRollback']}
    repl[g('AmiBoardInfo')] = patch_dsdt(getfile(sn, 0, len(sn), g('AmiBoardInfo')))
    ins = [getfile(kn, 0, len(kn), g(n)) for n in ('TrEEDxe', 'Tpm20PlatformDxe', 'Tpm20Acpi')]

    hlen = struct.unpack('<H', sn[0x30:0x32])[0]
    nv = bytearray(sn[:hlen]); nrepl = 0
    for o, gg, ft, sz in walk(sn, 0, len(sn)):
        f = repl.get(gg)
        if f is None: f = sn[o:o + sz]
        else: nrepl += 1
        nv += b'\xFF' * (align8(len(nv)) - len(nv)) + f
    assert nrepl == 9, nrepl
    for f in ins:
        nv += b'\xFF' * (align8(len(nv)) - len(nv)) + f
    print(f"DXE  9 modules replaced, 3 inserted, FV 0x{NESTED_OLD:X} -> 0x{NESTED_NEW:X}")
    assert len(nv) <= NESTED_NEW
    nv += b'\xFF' * (NESTED_NEW - len(nv))
    struct.pack_into('<Q', nv, 0x20, NESTED_NEW)
    struct.pack_into('<I', nv, 0x38, NESTED_NEW // 0x1000)       # block map: num blocks
    struct.pack_into('<H', nv, 0x32, 0)
    struct.pack_into('<H', nv, 0x32, (0x10000 - (sum(struct.unpack('<36H', nv[:0x48])) & 0xFFFF)) & 0xFFFF)

    # EDK2-compatible LZMA: LZMA1 "alone" header with the 8-byte size field filled in.
    # (uefi_firmware's LzmaCompress is broken for >1 MiB inputs, so python's lzma is used.)
    stream = struct.pack('<I', (NESTED_NEW + 4) | (0x17 << 24)) + bytes(nv) + dec_old[NESTED_OLD + 4:]
    filt = [{'id': lzma.FILTER_LZMA1, 'dict_size': 0x800000, 'lc': 3, 'lp': 0, 'pb': 2}]
    comp = bytearray(lzma.compress(stream, format=lzma.FORMAT_ALONE, filters=filt))
    struct.pack_into('<Q', comp, 5, len(stream))
    comp = bytes(comp)
    assert bytes(efi_compressor.LzmaDecompress(comp, len(comp))) == stream, "EDK2 decoder mismatch"
    print(f"LZMA 0x{len(stream):X} -> 0x{len(comp):X} bytes (verified with EDK2 decoder)")

    secsize = 9 + len(comp)
    f4 = bytearray(stock[i:i + 24])
    f4[20:23] = (24 + secsize).to_bytes(3, 'little')
    f4 = bytearray(bytes(f4) + struct.pack('<I', secsize | (0x01 << 24)) + struct.pack('<IB', len(stream), 2) + comp)
    new_outer = bytearray(stock[OUTER:i]) + fix_ffs(bytes(f4))
    assert len(new_outer) <= OUTERSZ, "main FV overflow"
    new_outer += b'\xFF' * (OUTERSZ - len(new_outer))
    img[OUTER:OUTER + OUTERSZ] = new_outer
    return bytes(img)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--stock', required=True, help='Z97MOCF2.50 (ASRock Z97M OC Formula P2.50 ROM)')
    ap.add_argument('--donor', required=True, help='Z97Ex62.80A (ASRock Z97 Extreme6 P2.80A TPM2 beta ROM)')
    ap.add_argument('--out', default='Z97MOCF_TPM2_8MB.bin', help='output 8 MiB SPI image')
    ap.add_argument('--force', action='store_true', help='accept inputs with unexpected checksums')
    a = ap.parse_args()
    out = build(load_rom(a.stock, STOCK_SHA, 'stock', a.force), load_rom(a.donor, DONOR_SHA, 'donor', a.force))
    open(a.out, 'wb').write(out)
    sha = hashlib.sha256(out).hexdigest()
    print(f"wrote {a.out}  sha256 {sha}")
    print("MATCHES the hardware-tested image" if sha == RESULT_SHA else "NOTE: differs from the hardware-tested image")

if __name__ == '__main__':
    main()
