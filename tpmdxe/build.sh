#!/usr/bin/env bash
# Build tpmdxe.efi (x86-64 UEFI boot-service driver, subsystem 11) with gnu-efi 3.0.17.
# firmware/build_tpm2_bios.py --tpmdxe tpmdxe/tpmdxe.efi wraps it in an FFS DRIVER file.
# It can also be tested without flashing: UEFI shell (Secure Boot off) -> `load tpmdxe.efi`.
set -euo pipefail
cd "$(dirname "$0")"
GNUEFI_VER=3.0.17
GNUEFI_SHA=7807e903349343a7a142ebb934703a2872235e89688cf586c032b0a1087bcaf4
# gnu-efi's Makefiles break on paths with spaces, so build outside the checkout (shared with tpmboot).
B=${TPMBOOT_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tpmboot-build}; G=$B/gnu-efi-$GNUEFI_VER
mkdir -p "$B"

if [ ! -f $G/x86_64/gnuefi/libgnuefi.a ]; then
  tarball=$B/gnu-efi-$GNUEFI_VER.tar.bz2
  [ -f $tarball ] || curl -fL -o $tarball "https://sourceforge.net/projects/gnu-efi/files/gnu-efi-$GNUEFI_VER.tar.bz2/download"
  echo "$GNUEFI_SHA  $tarball" | sha256sum -c -
  tar -xjf $tarball -C $B
  make -C $G ARCH=x86_64 lib gnuefi inc >/dev/null
fi

CFLAGS="-I$G/inc -I$G/inc/x86_64 -I$G/inc/protocol -fpic -fno-stack-protector -fshort-wchar -mno-red-zone \
 -DEFI_FUNCTION_WRAPPER -fno-strict-aliasing -ffreestanding -maccumulate-outgoing-args -Wall"
gcc $CFLAGS -c tpmdxe.c -o $B/tpmdxe.o
ld -nostdlib -znocombreloc -T $G/gnuefi/elf_x86_64_efi.lds -shared -Bsymbolic \
  -L$G/x86_64/lib -L$G/x86_64/gnuefi $G/x86_64/gnuefi/crt0-efi-x86_64.o $B/tpmdxe.o \
  -o $B/tpmdxe.so -lefi -lgnuefi "$(gcc -print-libgcc-file-name)"
objcopy -j .text -j .sdata -j .data -j .dynamic -j .dynsym -j .rel -j .rela -j .rel.* -j .rela.* -j .reloc \
  --target=efi-bsdrv-x86_64 --subsystem=11 $B/tpmdxe.so tpmdxe.efi
python3 - tpmdxe.efi <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read(); pe = struct.unpack('<I', d[0x3C:0x40])[0]; opt = pe + 24
assert struct.unpack('<H', d[pe + 4:pe + 6])[0] == 0x8664, "not x86-64"
sub = struct.unpack('<H', d[opt + 68:opt + 70])[0]
assert sub == 11, f"subsystem {sub}, expected 11 (EFI boot service driver)"
print(f"tpmdxe.efi: x86-64, subsystem 11 (boot service driver), {len(d)} bytes")
EOF
