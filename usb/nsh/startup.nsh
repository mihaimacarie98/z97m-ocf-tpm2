@echo -off
# V11 stick - runs automatically when the stick boots (press ESC during the countdown to skip).
# Detects V11 firmware by the volatile variable TpmBootDxe that the in-BIOS driver publishes.
#   V11 BIOS found, old shim chain still on the disk: removes the chain (restores
#       \EFI\BOOT\BOOTX64.EFI, deletes \EFI\tpmboot), sets firmware TPM support OFF, shows status.
#   V11 BIOS found, nothing to clean: changes nothing, shows status, stays in the shell.
#   No V11 BIOS (still V9): dry run - loads tpmdxe.efi from the stick as a driver and starts
#       Windows, so tpm.msc shows whether the driver works on this board. Needs Secure Boot OFF.
echo "=== Z97M OC Formula TPM 2.0 stick (V11) ==="

set STICK none
set ESP none
for %i run (0 9)
  if exist fs%i:\setup_var.efi then
    if exist fs%i:\tpmdxe.efi then
      set STICK fs%i
    endif
  endif
  if exist fs%i:\EFI\Microsoft\Boot\bootmgfw.efi then
    set ESP fs%i
  endif
endfor
if %STICK% == none then
  echo "ERROR: this stick's files were not found (setup_var.efi, tpmdxe.efi). Re-copy the stick."
  goto END
endif
if %ESP% == none then
  echo "ERROR: no Windows EFI partition found (\EFI\Microsoft\Boot\bootmgfw.efi)."
  goto END
endif
echo "Stick: %STICK%:   Windows EFI partition: %ESP%:"
echo "TPM setup values (0x26 support, 0x21 state, 0x33 device select, 0x4A1 auto detect):"
%STICK%:\setup_var.efi Setup:0x26 Setup:0x21 Setup:0x33 Setup:0x4A1

echo "V11 driver status (3 values: DID_VID, Startup rc, TPM2 table status; 0 = OK):"
dmpstore TpmBootDxe -guid 78c18031-b5ae-4112-a635-70285b920a2f
if %lasterror% == 0x0 then
  goto V11
endif

# ---------------- V9 BIOS: dry run of the V11 driver ----------------
echo "V11 BIOS not detected. Dry run: loading tpmdxe.efi from the stick (needs Secure Boot OFF)..."
load %STICK%:\tpmdxe.efi
if not %lasterror% == 0x0 then
  echo "The driver could not be loaded - Secure Boot is probably ON. Turn it off for the dry run."
  goto END
endif
dmpstore TpmBootDxe -guid 78c18031-b5ae-4112-a635-70285b920a2f
echo "Driver ran. Starting Windows in 10 s - then check tpm.msc (should say ready, 2.0)."
echo "Afterwards turn Secure Boot back ON; your V9 setup is unchanged."
stall 10000000
%ESP%:\EFI\Microsoft\Boot\bootmgfw.efi
goto END

# ---------------- V11 BIOS ----------------
:V11
echo "V11 BIOS detected (TpmBootDxe ran at boot)."
if not exist %ESP%:\EFI\tpmboot\shimx64.efi then
  echo "No old shim chain on the disk - nothing to do. Remove the stick and type: reset"
  goto END
endif
echo "[1/2] Removing the old shim chain (not needed with V11)"
if exist %ESP%:\EFI\BOOT\BOOTX64.BAK then
  cp -q %ESP%:\EFI\BOOT\BOOTX64.BAK %ESP%:\EFI\BOOT\BOOTX64.EFI
  rm -q %ESP%:\EFI\BOOT\BOOTX64.BAK
else
  cp -q %ESP%:\EFI\Microsoft\Boot\bootmgfw.efi %ESP%:\EFI\BOOT\BOOTX64.EFI
endif
if exist %ESP%:\EFI\BOOT\mmx64.efi then
  rm -q %ESP%:\EFI\BOOT\mmx64.efi
endif
if exist %ESP%:\EFI\BOOT\grubx64.efi then
  rm -q %ESP%:\EFI\BOOT\grubx64.efi
endif
rm -q %ESP%:\EFI\tpmboot
echo "[2/2] TPM setup variables: firmware TPM support OFF (the V11 driver starts the TPM)"
%STICK%:\setup_var.efi Setup:0x26=0x0 Setup:0x21=0x0 Setup:0x4A1=0x0 Setup:0x33=0x2
echo " "
echo "Done. The old 'TPM Boot (Secure)' entry now points to a deleted file; the firmware skips it."
echo "To delete it: in Windows run migrate\remove_shim_chain.ps1, or here: bcfg boot dump, then bcfg boot rm N"
echo "Remove the stick and type: reset"
:END
