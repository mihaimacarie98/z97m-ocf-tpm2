# Install guide

Hardware tested: ASRock Z97M OC Formula, i7-4790K, **ASRock TPM2-S** (Infineon SLB9665, 18-pin "18pin-1" LPC header). An SLB9665 clone module behaved the same way. The OS was Windows 11 on GPT/UEFI with CSM disabled.

## 0. Get the inputs

| File | Source | sha256 |
|---|---|---|
| `Z97MOCF2.50` | ASRock Z97M OC Formula BIOS P2.50: `https://download.asrock.com/BIOS/1150/Z97M%20OC%20Formula(2.50)ROM.zip` | `4f896e21e5f817fde2c20c08ce7df5ca707dc8449613b9ac833d21eccd8db326` |
| `Z97Ex62.80A` | ASRock Z97 Extreme6 BIOS **P2.80A** (TPM2 beta). The direct link `…/Z97%20Extreme6(2.80A)ROM.zip` returned 403 in 2026-10, so ask ASRock support or the ASRock forum TPM2 thread for it. | `f096bc699880657902837245eb02743392d5e94e0e03f05ebdfa3d82174875e2` |

Both are 8 MiB plus a 4 KiB ASRock header. The builder strips the header.

## 1. Build and flash the firmware

```bash
pip install uefi_firmware
python3 firmware/build_tpm2_bios.py --stock Z97MOCF2.50 --donor Z97Ex62.80A --out Z97MOCF_TPM2_8MB.bin
python3 firmware/verify_image.py Z97MOCF_TPM2_8MB.bin --stock Z97MOCF2.50
```

**Read your chip first and keep the dump.** Read it twice and compare. A bad socket contact gives reads that silently turn into 0xFF partway through. To keep your onboard MAC, DMI serial and UUID:

```bash
python3 firmware/merge_nvram.py --dump my_dump.bin --mod Z97MOCF_TPM2_8MB.bin --out flash_me.bin
```

Flash the full 8 MiB and verify. If a verify error shows up at a random address, or the board doesn't POST after a good verify, re-seat the DIP-8 chip. Bent or fatigued legs caused most of the "failed" flashes during development. Recovery: flash your dump, or the stock ROM without its 4 KiB header.

## 2. Make the USB stick

```bash
bash usb/make_usb.sh      # result in usb/out/
```

Copy the **contents** of `usb/out/` to the root of a FAT32 stick. The stick boots through the signed shim, so it works with Secure Boot on or off.

## 3. TPM setup variables

The TPM menu is hidden on this board, so the values are written with `setup_var.efi`. Boot the stick (F11, then the "UEFI: <stick>" entry). With Secure Boot on, the first boot shows a blue *Verification failed*. Press a key, then **Enroll hash from disk**, the stick, `EFI\BOOT\grubx64.efi`, Continue, Yes, Reboot.

In the shell:

```
tpm_fw_off.nsh       (Setup:0x26=0 0x21=0 0x4A1=0 0x33=2)  firmware TPM support OFF
reset
```

With firmware support **off**, the board never freezes at the splash screen, and tpmboot opens the TPM's LPC decode window itself. If tpmboot later prints `TPM still not reachable`, use `tpm_fw_on.nsh` instead (`0x26=1 0x21=0`). That setting can freeze at the splash screen now and then; press reset and it gets through.

| Offset in `Setup` (size 0x4A4) | Meaning |
|---|---|
| `0x26` | Security Device Support (0 = off) |
| `0x21` | TPM State |
| `0x33` | TPM Device Select (0 = 1.2, 1 = 2.0, 2 = Auto). **Never set 1**: forced 2.0 hangs at the splash screen. |
| `0x4A1` | ASRock "Auto Detect Security Device" (doesn't recognize TPM 2.0, so set it to 0) |

## 4. Test, then install

From the stick's shell, run `tpmboot.efi`. You should see:

```
tpmboot v3: DID_VID=001a15d1         (or: after LPC decode enable DID_VID=001a15d1)
tpmboot: Startup(CLEAR) rc=00000000 OK   (rc=00000100 = already started, also fine)
tpmboot: SelfTest rc=00000000 OK
tpmboot: TPM2 ACPI table: Success
```

Windows then starts by itself. Check `tpm.msc`: "ready for use", version 2.0.

To install permanently, run `install_sb.nsh` on the stick, then `reset`. It copies shim, MokManager and tpmboot (as `grubx64.efi`) to `\EFI\tpmboot\` on the Windows EFI partition. It also installs shim as the fallback `\EFI\BOOT\BOOTX64.EFI` (the original is saved as `BOOTX64.BAK`) and adds the boot entry **"TPM Boot (Secure)"** at position 0.

## 5. Secure Boot

1. BIOS, **Boot** tab, Secure Boot, Key Management: **Install default Secure Boot keys** (needed if the keys were ever cleared).
2. Secure Boot: **Enabled**. Save and reboot.
3. One time only: the blue *Verification failed (0x1A) Security Violation* box appears. Press a key, then **Enroll hash from disk**, pick the **NVMe/SSD first partition** (the ESP; not "System Reserved" and not the stick), select `EFI\tpmboot\grubx64.efi`, then Continue, Yes, Reboot.
4. Verify in Windows: `msinfo32` shows Secure Boot State **On**. `Confirm-SecureBootUEFI` returns `True`. `Get-Tpm` shows TpmPresent and TpmReady both `True`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Blue *Verification failed* comes back after enrolling | The file changed (a new build means a new hash), or it lacks a `.sbat` section. Re-enroll it. Every file in this repo has a valid `.sbat`. |
| Shim: **"malformed section header"** | `.sbat` was added with `objcopy --add-section`, which puts it on top of the PE header. Use `tools/pe_sbat.py add` or the link-time method in `tpmboot/build.sh`. |
| AMI red "Secure Boot Violation" *before* any blue shim screen | The firmware rejects shim itself because the keys are missing. Fix: **Install default Secure Boot keys**. |
| tpmboot `DID_VID=ffffffff` and still unreachable after the LPC step | Run `tpm_fw_on.nsh`. |
| `tpm.msc`: "TPM 1.2 … tag value invalid 0x8028001E" | The TPM2 ACPI table is missing because tpmboot didn't run. Check that the boot order starts with "TPM Boot (Secure)". |
| `tpm.msc`: "Compatible TPM cannot be found" | The DSDT has no `MSFT0101` device (stock firmware). Check with `verify_image.py`. |
| Windows says the TPM needs to be cleared | Admin cmd: `mountvol S: /S`, then `echo. > S:\EFI\tpmboot\clear`, then reboot. tpmboot sends `TPM2_Clear` once and deletes the flag. |
| Leftover boot entries | Run `bcdedit /enum firmware`, then `bcdedit /delete "{guid}"` (keep the quotes in PowerShell). Keep one "TPM Boot (Secure)" and `{bootmgr}`. |
| Undo | Disable Secure Boot. Shell: `bcfg boot rm 0`. Copy `BOOTX64.BAK` back over `BOOTX64.EFI`. Flash the stock ROM or your dump. |

Windows updates replace `\EFI\Microsoft\Boot\bootmgfw.efi` but don't touch `\EFI\tpmboot\`, so the chain survives them. A CMOS clear resets the boot order, and the `\EFI\BOOT\BOOTX64.EFI` fallback (= shim) covers that case. The Setup variables are reset too, so run `tpm_fw_off.nsh` again.
