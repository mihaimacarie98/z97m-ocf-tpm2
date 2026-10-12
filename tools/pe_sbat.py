#!/usr/bin/env python3
"""Check or add the SBAT section that shim 15.3+ requires in every second-stage EFI binary.

  pe_sbat.py check FILE.efi
      Validates the section table the way shim's loader does (section inside the image,
      not overlapping the headers, raw data inside the file, alignment) and prints .sbat.
  pe_sbat.py add IN.efi OUT.efi --component NAME,GEN,VENDOR,PACKAGE,VERSION,URL
      Appends a correct .sbat section to an already-built PE (e.g. a prebuilt UEFI shell):
      new section header after the last one, VA = end of image, raw data at end of file,
      SizeOfImage updated.  Needs 40 free bytes after the section table.

Do NOT use `objcopy --add-section .sbat=...` on a PE: it places the section at VA 0 on top
of the headers and shim refuses the file with "malformed section header".
Note: changing a binary changes its Authenticode hash - re-enroll it in MokManager."""
import argparse, struct, sys

SBAT_HEADER = 'sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md\n'

def align(x, a): return (x + a - 1) // a * a

def parse(d):
    pe = struct.unpack('<I', d[0x3C:0x40])[0]
    assert d[pe:pe + 4] == b'PE\0\0', "not a PE file"
    n = struct.unpack('<H', d[pe + 6:pe + 8])[0]
    opt = pe + 24; st = opt + struct.unpack('<H', d[pe + 20:pe + 22])[0]
    sa, fa = struct.unpack('<II', d[opt + 32:opt + 40])
    soi, soh = struct.unpack('<II', d[opt + 56:opt + 64])
    secs = []
    for i in range(n):
        o = st + i * 40
        secs.append((d[o:o + 8].rstrip(b'\0').decode(errors='replace'),) + struct.unpack('<IIII', d[o + 8:o + 24]))
    return dict(pe=pe, n=n, opt=opt, st=st, sa=sa, fa=fa, soi=soi, soh=soh, secs=secs)

def check(d, verbose=True):
    p = parse(d); ok = True; sbat = None
    if verbose: print(f"SectionAlign=0x{p['sa']:X} FileAlign=0x{p['fa']:X} SizeOfImage=0x{p['soi']:X} SizeOfHeaders=0x{p['soh']:X}")
    for nm, vsz, va, rsz, ra in p['secs']:
        bad = []
        if va < p['soh']: bad.append('inside headers')
        if va + max(vsz, rsz) > p['soi']: bad.append('beyond SizeOfImage')
        if rsz and ra + rsz > len(d): bad.append('raw beyond file')
        if va % p['sa'] or (rsz and ra % p['fa']): bad.append('misaligned')
        if nm == '.sbat': sbat = d[ra:ra + min(vsz, rsz)].rstrip(b'\0').decode(errors='replace')
        if verbose: print(f"  {nm:8s} VA=0x{va:06X} VSz=0x{vsz:06X} Raw=0x{ra:06X} RSz=0x{rsz:06X} {'<-- ' + ', '.join(bad) if bad else 'ok'}")
        ok &= not bad
    vas = [s[2] for s in p['secs']]
    if vas != sorted(vas): ok = False; verbose and print("  sections not sorted by VA")
    if sbat is None: ok = False; verbose and print("  no .sbat section (shim 15.3+ will refuse this file)")
    elif verbose: print("  .sbat: " + sbat.replace('\n', ' | '))
    return ok

def add(d, component):
    d = bytearray(d); p = parse(d)
    if any(s[0] == '.sbat' for s in p['secs']): sys.exit("already has .sbat")
    table_end = p['st'] + p['n'] * 40
    first_raw = min(s[4] for s in p['secs'] if s[4])
    if first_raw - table_end < 40 or any(d[table_end:table_end + 40]):
        sys.exit("no free slot after the section table (relink with a .sbat section instead)")
    csv = (SBAT_HEADER + component.strip() + '\n').encode()
    va = align(max(s[2] + max(s[1], s[3]) for s in p['secs']), p['sa'])
    ra = align(len(d), p['fa']); rsz = align(len(csv), p['fa'])
    d += b'\0' * (ra - len(d)) + csv + b'\0' * (rsz - len(csv))
    d[table_end:table_end + 40] = b'.sbat\0\0\0' + struct.pack('<IIIIIIHHI', len(csv), va, rsz, ra, 0, 0, 0, 0, 0x40000040)
    struct.pack_into('<H', d, p['pe'] + 6, p['n'] + 1)
    struct.pack_into('<I', d, p['opt'] + 56, align(va + rsz, p['sa']))
    struct.pack_into('<I', d, p['opt'] + 64, 0)          # PE checksum: unused by UEFI, now stale
    return bytes(d)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0]); sp = ap.add_subparsers(dest='cmd', required=True)
    c = sp.add_parser('check'); c.add_argument('file')
    a = sp.add_parser('add'); a.add_argument('infile'); a.add_argument('outfile')
    a.add_argument('--component', required=True, help='e.g. "uefishell,1,Local,uefi-shell,1,https://example"')
    x = ap.parse_args()
    if x.cmd == 'check':
        ok = check(open(x.file, 'rb').read()); print("VALID for shim" if ok else "NOT valid for shim"); sys.exit(0 if ok else 1)
    out = add(open(x.infile, 'rb').read(), x.component)
    assert check(out, verbose=False), "result failed validation"
    open(x.outfile, 'wb').write(out); check(out); print(f"wrote {x.outfile}")
