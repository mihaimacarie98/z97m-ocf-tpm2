@echo -off
echo === Secure Boot installer: Microsoft-signed shim -> tpmboot -> Windows ===
for %i run (0 8)
  if exist fs%i:\EFI\Microsoft\Boot\bootmgfw.efi then
    echo Windows ESP = fs%i:
    for %j run (0 8)
      if exist fs%j:\sb\shimx64.efi then
        if not exist fs%i:\EFI\tpmboot then
          mkdir fs%i:\EFI\tpmboot
        endif
        cp -q fs%j:\sb\shimx64.efi fs%i:\EFI\tpmboot\shimx64.efi
        cp -q fs%j:\sb\mmx64.efi   fs%i:\EFI\tpmboot\mmx64.efi
        cp -q fs%j:\sb\grubx64.efi fs%i:\EFI\tpmboot\grubx64.efi
        if not exist fs%i:\EFI\BOOT then
          mkdir fs%i:\EFI\BOOT
        endif
        if exist fs%i:\EFI\BOOT\BOOTX64.EFI then
          if not exist fs%i:\EFI\BOOT\BOOTX64.BAK then
            cp -q fs%i:\EFI\BOOT\BOOTX64.EFI fs%i:\EFI\BOOT\BOOTX64.BAK
          endif
        endif
        cp -q fs%j:\sb\shimx64.efi fs%i:\EFI\BOOT\BOOTX64.EFI
        cp -q fs%j:\sb\mmx64.efi   fs%i:\EFI\BOOT\mmx64.efi
        cp -q fs%j:\sb\grubx64.efi fs%i:\EFI\BOOT\grubx64.efi
      endif
    endfor
    if not exist fs%i:\EFI\tpmboot\shimx64.efi then
      echo ERROR: sb\shimx64.efi not found on the USB stick - copy the sb folder to the stick root
      goto DONE
    endif
    echo Boot entry "TPM Boot (Secure)" at position 0 -> shim:
    bcfg boot add 0 fs%i:\EFI\tpmboot\shimx64.efi "TPM Boot (Secure)"
    bcfg boot dump
    echo DONE. Type: reset
    echo Next boot with Secure Boot ON shows a blue "Verification failed" box once:
    echo   press any key -> Enroll hash from disk -> pick EFI\tpmboot\grubx64.efi -> Continue -> Yes -> Reboot
    goto DONE
  endif
endfor
echo ERROR: no drive with \EFI\Microsoft\Boot\bootmgfw.efi found
:DONE
