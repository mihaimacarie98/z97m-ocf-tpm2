@echo -off
echo === tpmboot installer: boot entry + ESP fallback path ===
for %i run (0 8)
  if exist fs%i:\EFI\Microsoft\Boot\bootmgfw.efi then
    echo Windows ESP = fs%i:
    if not exist fs%i:\EFI\tpmboot then
      mkdir fs%i:\EFI\tpmboot
    endif
    for %j run (0 8)
      if exist fs%j:\tpmboot.efi then
        cp -q fs%j:\tpmboot.efi fs%i:\EFI\tpmboot\tpmboot.efi
      endif
    endfor
    if not exist fs%i:\EFI\tpmboot\tpmboot.efi then
      echo ERROR: tpmboot.efi not found on any drive - put it in the root of the USB stick
      goto DONE
    endif
    echo 1. fallback path: backing up \EFI\BOOT\BOOTX64.EFI to BOOTX64.BAK and installing shim there
    if exist fs%i:\EFI\BOOT\BOOTX64.EFI then
      if not exist fs%i:\EFI\BOOT\BOOTX64.BAK then
        cp -q fs%i:\EFI\BOOT\BOOTX64.EFI fs%i:\EFI\BOOT\BOOTX64.BAK
      endif
    endif
    if not exist fs%i:\EFI\BOOT then
      mkdir fs%i:\EFI\BOOT
    endif
    cp -q fs%i:\EFI\tpmboot\tpmboot.efi fs%i:\EFI\BOOT\BOOTX64.EFI
    echo 2. boot entry "TPM Boot" at position 0:
    bcfg boot add 0 fs%i:\EFI\tpmboot\tpmboot.efi "TPM Boot"
    bcfg boot dump
    echo DONE. Type: reset
    goto DONE
  endif
endfor
echo ERROR: no drive with \EFI\Microsoft\Boot\bootmgfw.efi found
:DONE
