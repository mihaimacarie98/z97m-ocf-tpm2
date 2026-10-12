#!/usr/bin/env bash
# Build tpmboot.efi (x86-64 UEFI application) with gnu-efi 3.0.17 and a link-time .sbat section.
# Needs: gcc, binutils (ld, objcopy), make, curl, python3.  Tested on Ubuntu 20.04 (WSL).
set -euo pipefail
cd "$(dirname "$0")"
GNUEFI_VER=3.0.17
GNUEFI_SHA=7807e903349343a7a142ebb934703a2872235e89688cf586c032b0a1087bcaf4
# gnu-efi's Makefiles break on paths with spaces, so build outside the checkout.
B=${TPMBOOT_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tpmboot-build}; G=$B/gnu-efi-$GNUEFI_VER
mkdir -p "$B"

if [ ! -f $G/x86_64/gnuefi/libgnuefi.a ]; then
  tarball=$B/gnu-efi-$GNUEFI_VER.tar.bz2
  [ -f $tarball ] || curl -fL -o $tarball "https://sourceforge.net/projects/gnu-efi/files/gnu-efi-$GNUEFI_VER.tar.bz2/download"
  echo "$GNUEFI_SHA  $tarball" | sha256sum -c -
  tar -xjf $tarball -C $B
  make -C $G ARCH=x86_64 lib gnuefi inc >/dev/null
fi

# gnu-efi linker script + a page-aligned .sbat output section after .data.
# (Adding .sbat afterwards with `objcopy --add-section` puts it at VA 0 on top of the
#  PE headers -> shim rejects the file with "malformed section header".)
python3 - "$G/gnuefi/elf_x86_64_efi.lds" "$B/tpmboot.lds" <<'EOF'
import sys
t = open(sys.argv[1]).read()
i = t.index('  .data :'); j = t.index('}', i) + 1
open(sys.argv[2], 'w').write(t[:j] + '\n  . = ALIGN(4096);\n  .sbat : { *(.sbat) }\n' + t[j:])
EOF

CFLAGS="-I$G/inc -I$G/inc/x86_64 -I$G/inc/protocol -fpic -fno-stack-protector -fshort-wchar -mno-red-zone \
 -DEFI_FUNCTION_WRAPPER -fno-strict-aliasing -ffreestanding -maccumulate-outgoing-args"
gcc $CFLAGS -c tpmboot.c -o $B/tpmboot.o
objcopy -I binary -O elf64-x86-64 -B i386:x86-64 \
  --rename-section .data=.sbat,alloc,load,readonly,data,contents sbat.csv $B/sbat.o
ld -nostdlib -znocombreloc -T $B/tpmboot.lds -shared -Bsymbolic \
  -L$G/x86_64/lib -L$G/x86_64/gnuefi $G/x86_64/gnuefi/crt0-efi-x86_64.o $B/tpmboot.o $B/sbat.o \
  -o $B/tpmboot.so -lefi -lgnuefi "$(gcc -print-libgcc-file-name)"
objcopy -j .text -j .sdata -j .data -j .sbat -j .dynamic -j .dynsym -j .rel -j .rela -j .rel.* -j .rela.* -j .reloc \
  --target=efi-app-x86_64 --subsystem=10 $B/tpmboot.so tpmboot.efi
python3 ../tools/pe_sbat.py check tpmboot.efi
echo "built $(pwd)/tpmboot.efi"
