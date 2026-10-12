@echo -off
echo === Z97M OC Formula TPM 2.0 stick ===
for %i run (0 8)
  if exist fs%i:\setup_var.efi then
    fs%i:
    echo Current TPM setup values (0x26 support, 0x21 state, 0x33 device select, 0x4A1 auto detect):
    setup_var.efi Setup:0x26 Setup:0x21 Setup:0x33 Setup:0x4A1
    goto HELP
  endif
endfor
echo setup_var.efi not found on any drive
:HELP
echo Commands:
echo   tpm_fw_off.nsh     firmware TPM support OFF (recommended, no boot freeze; tpmboot opens the TPM itself)
echo   tpm_fw_on.nsh      firmware TPM support ON, TPM state off (fallback if tpmboot says not reachable)
echo   tpmboot.efi        run the shim now: starts TPM, adds TPM2 ACPI table, boots Windows
echo   install_sb.nsh     install signed shim + tpmboot on the Windows EFI partition (Secure Boot)
echo   install_tpmboot.nsh  install tpmboot only (Secure Boot off)
echo   test_tpmdxe.nsh    V11 dry run: load the in-BIOS driver from the stick, then boot Windows
echo   tpmtest.nsh / tpmclear.nsh / diag.nsh   manual TIS tests
