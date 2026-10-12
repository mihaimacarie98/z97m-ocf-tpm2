@echo -off
echo === V11 dry run: load TpmBootDxe as a driver, then start Windows (no flashing) ===
echo Secure Boot must be OFF for this test (the driver is unsigned outside the firmware).
for %j run (0 8)
  if exist fs%j:\tpmdxe.efi then
    load fs%j:\tpmdxe.efi
    acpiview -s TPM2
    for %i run (0 8)
      if exist fs%i:\EFI\Microsoft\Boot\bootmgfw.efi then
        echo Starting Windows from fs%i: - then check tpm.msc
        fs%i:\EFI\Microsoft\Boot\bootmgfw.efi
      endif
    endfor
    echo ERROR: Windows boot manager not found
    goto DONE
  endif
endfor
echo ERROR: tpmdxe.efi not found on the stick
:DONE
