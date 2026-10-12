#!/usr/bin/env bash
# Assemble the USB stick contents in usb/out/ (copy that folder's CONTENTS to a FAT32 stick).
#
#   \EFI\BOOT\BOOTX64.EFI  Microsoft-signed shim (Debian shim-signed 1.51+16.1-2)
#   \EFI\BOOT\mmx64.efi    MokManager signed by Debian (matches that shim's vendor cert)
#   \EFI\BOOT\grubx64.efi  pbatard UEFI Shell + .sbat  (what shim starts; enroll its hash once)
#   \sb\shimx64.efi, \sb\mmx64.efi, \sb\grubx64.efi(=tpmboot.efi)   used by install_sb.nsh
#   \tpmboot.efi, \tpmdxe.efi (V11 dry run), \setup_var.efi, \*.nsh
#
# Every download is pinned by sha256.  If Debian has dropped a version from its pool,
# set SHIM_DEB_URL / MM_DEB_URL to a snapshot.debian.org URL of the same file.
# Needs: curl, dpkg-deb (or ar+tar), python3; tpmboot needs gcc/binutils (see tpmboot/build.sh).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd); OUT=out; DL=${XDG_CACHE_HOME:-$HOME/.cache}/z97m-tpm2-dl
mkdir -p "$DL"

SHIM_DEB_URL=${SHIM_DEB_URL:-http://ftp.debian.org/debian/pool/main/s/shim-signed/shim-signed_1.51+16.1-2_amd64.deb}
SHIM_DEB_SHA=993868c31cca3eab054a0c51c124a4a8b3904f49fb002feb4b09cb9415200e74
MM_DEB_URL=${MM_DEB_URL:-http://ftp.debian.org/debian/pool/main/s/shim-helpers-amd64-signed/shim-helpers-amd64-signed_1+16.1+2_amd64.deb}
MM_DEB_SHA=6a6d340710ffc067198af33785d1e04836b2cc0d259ec4b080a06604d333a8cb
SHELL_URL=https://github.com/pbatard/UEFI-Shell/releases/download/26H1/shellx64.efi
SHELL_SHA=4ea080ddd576117cd04f5c02d16712ea5d9249c0752214d8e4055e460d7b11e0
SETUPVAR_URL=https://github.com/datasone/setup_var.efi/releases/download/0.3.1/setup_var.efi
SETUPVAR_SHA=cbe5777b61276d3f3506a28b34845326e92f6c171bff59177e3912fe20f49840
# outputs (verified on the reference hardware)
SHIM_SHA=637d7916c0b0b9cb505612f39e8c47b47894957f15a1e711b22a2ae5bbec286d
MM_SHA=3480a42892865d356a15759cb2271bfeb009d5687c153896d3983c354cd2d949
SHELL_SBAT_SHA=7c08292f542bf37646d8467644bc7d532174d5b21c57ae8eb8d1aa5bd935baf9

fetch() {  # url sha dest
  [ -f "$3" ] && echo "$2  $3" | sha256sum -c --quiet - 2>/dev/null && return
  curl -fsSL -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --quiet - || { echo "checksum mismatch: $1"; rm -f "$3"; exit 1; }
}
deb_extract() {  # deb member dest
  local t; t=$(mktemp -d)
  if command -v dpkg-deb >/dev/null; then dpkg-deb -x "$1" "$t"
  else (cd "$t" && ar x "$1" && tar -xf data.tar.*); fi
  cp "$t/$2" "$3"; rm -rf "$t"
}

fetch "$SHIM_DEB_URL" $SHIM_DEB_SHA "$DL/shim-signed.deb"
fetch "$MM_DEB_URL"   $MM_DEB_SHA   "$DL/shim-helpers.deb"
fetch "$SHELL_URL"    $SHELL_SHA    "$DL/shellx64.efi"
fetch "$SETUPVAR_URL" $SETUPVAR_SHA "$DL/setup_var.efi"

rm -rf $OUT; mkdir -p $OUT/EFI/BOOT $OUT/sb
deb_extract "$DL/shim-signed.deb"  usr/lib/shim/shimx64.efi.signed $OUT/sb/shimx64.efi
deb_extract "$DL/shim-helpers.deb" usr/lib/shim/mmx64.efi.signed   $OUT/sb/mmx64.efi
python3 "$ROOT/tools/pe_sbat.py" add "$DL/shellx64.efi" $OUT/EFI/BOOT/grubx64.efi \
  --component "uefishell,1,Local,uefi-shell,1,https://local" >/dev/null

[ -f "$ROOT/tpmboot/tpmboot.efi" ] || bash "$ROOT/tpmboot/build.sh"
cp "$ROOT/tpmboot/tpmboot.efi" $OUT/tpmboot.efi
cp "$ROOT/tpmboot/tpmboot.efi" $OUT/sb/grubx64.efi
[ -f "$ROOT/tpmdxe/tpmdxe.efi" ] || bash "$ROOT/tpmdxe/build.sh"
cp "$ROOT/tpmdxe/tpmdxe.efi" $OUT/tpmdxe.efi                  # V11 driver, for test_tpmdxe.nsh
cp $OUT/sb/shimx64.efi $OUT/EFI/BOOT/BOOTX64.EFI
cp $OUT/sb/mmx64.efi   $OUT/EFI/BOOT/mmx64.efi
cp "$DL/setup_var.efi" $OUT/setup_var.efi
cp nsh/*.nsh $OUT/
cp "$DL/shellx64.efi" $OUT/shell_unsigned.efi   # plain shell: rename to \EFI\BOOT\BOOTX64.EFI if Secure Boot stays off

echo "$SHIM_SHA  $OUT/sb/shimx64.efi
$MM_SHA  $OUT/sb/mmx64.efi
$SHELL_SBAT_SHA  $OUT/EFI/BOOT/grubx64.efi" | sha256sum -c -
python3 "$ROOT/tools/pe_sbat.py" check $OUT/tpmboot.efi | tail -1
echo "USB tree ready in $(pwd)/$OUT - copy its contents to the root of a FAT32 stick"
