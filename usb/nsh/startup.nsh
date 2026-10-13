@echo -off
# Runs automatically when the stick boots (press ESC during the shell's countdown to skip).
#   First run : sets the TPM setup variables, installs shim + MokManager + tpmboot on the
#               Windows EFI partition (boot entry "TPM Boot (Secure)" + \EFI\BOOT fallback),
#               then reboots into it (firmware -> shim -> tpmboot -> Windows).
#   Later runs: already installed -> changes nothing, shows the TPM state and stays in the shell
#               (so a stick left first in the boot order can't cause a reboot loop).
# Re-running is safe: files and the boot entry are only added once (no duplicate entries).
echo "=== Z97M OC Formula TPM 2.0 stick: automatic setup ==="

# --- locate this stick and the Windows EFI system partition ---
set STICK none
set ESP none
for %i run (0 9)
  if exist fs%i:\setup_var.efi then
    if exist fs%i:\sb\shimx64.efi then
      set STICK fs%i
    endif
  endif
  if exist fs%i:\EFI\Microsoft\Boot\bootmgfw.efi then
    set ESP fs%i
  endif
endfor
if %STICK% == none then
  echo "ERROR: this stick's files were not found (setup_var.efi, sb\shimx64.efi). Re-copy the stick."
  goto END
endif
if %ESP% == none then
  echo "ERROR: no Windows EFI partition found (\EFI\Microsoft\Boot\bootmgfw.efi)."
  echo "Is Windows installed in UEFI mode on a GPT disk, and is the disk connected?"
  goto END
endif
echo "Stick: %STICK%:   Windows EFI partition: %ESP%:"

echo "Current TPM setup values (0x26 support, 0x21 state, 0x33 device select, 0x4A1 auto detect):"
%STICK%:\setup_var.efi Setup:0x26 Setup:0x21 Setup:0x33 Setup:0x4A1

if exist %ESP%:\EFI\tpmboot\shimx64.efi then
  echo "Already installed - nothing changed. TPM ID (001a15d1 = Infineon SLB9665; FFFFFFFF = not decoded yet, tpmboot opens it):"
  mm FED40F00 -MMIO -w 4 -n
  echo "Remove the stick and type: reset      (manual tools: tpmboot.efi, install_sb.nsh, tpm_fw_on.nsh, tpmtest.nsh)"
  goto END
endif

# --- first run ---
echo "[1/3] TPM setup variables: firmware TPM support OFF (no splash freeze, tpmboot starts the TPM)"
%STICK%:\setup_var.efi Setup:0x26=0x0 Setup:0x21=0x0 Setup:0x4A1=0x0 Setup:0x33=0x2

echo "[2/3] Installing shim + MokManager + tpmboot to %ESP%:\EFI\tpmboot"
if not exist %ESP%:\EFI\tpmboot then
  mkdir %ESP%:\EFI\tpmboot
endif
cp -q %STICK%:\sb\shimx64.efi %ESP%:\EFI\tpmboot\shimx64.efi
cp -q %STICK%:\sb\mmx64.efi   %ESP%:\EFI\tpmboot\mmx64.efi
cp -q %STICK%:\sb\grubx64.efi %ESP%:\EFI\tpmboot\grubx64.efi
if not exist %ESP%:\EFI\BOOT then
  mkdir %ESP%:\EFI\BOOT
endif
if exist %ESP%:\EFI\BOOT\BOOTX64.EFI then
  if not exist %ESP%:\EFI\BOOT\BOOTX64.BAK then
    cp -q %ESP%:\EFI\BOOT\BOOTX64.EFI %ESP%:\EFI\BOOT\BOOTX64.BAK
  endif
endif
cp -q %STICK%:\sb\shimx64.efi %ESP%:\EFI\BOOT\BOOTX64.EFI
cp -q %STICK%:\sb\mmx64.efi   %ESP%:\EFI\BOOT\mmx64.efi
cp -q %STICK%:\sb\grubx64.efi %ESP%:\EFI\BOOT\grubx64.efi
if not exist %ESP%:\EFI\tpmboot\shimx64.efi then
  echo "ERROR: copying to the EFI partition failed."
  goto END
endif

echo "[3/3] Boot entry 'TPM Boot (Secure)' at position 0"
bcfg boot add 0 %ESP%:\EFI\tpmboot\shimx64.efi "TPM Boot (Secure)"

echo " "
echo "Installed. If Secure Boot is not on yet: BIOS - Boot - Secure Boot - Install default keys + Enabled."
echo "With Secure Boot ON, the first boot shows a blue 'Verification failed' box once:"
echo "press a key - Enroll hash from disk - Windows disk, first partition - EFI\tpmboot\grubx64.efi"
echo "- Continue - Yes - Reboot"
echo " "
echo "Rebooting in 15 s - REMOVE THE STICK. (Ctrl+C stops the script.)"
stall 15000000
reset
:END
