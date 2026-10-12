---
name: z97m-ocf-tpm2
description: End-to-end procedure to give an ASRock Z97M OC Formula working TPM 2.0 plus Secure Boot in Windows (for Windows 11, or anti-cheat such as Battlefield 6 / EA Javelin). It builds the modded BIOS from the official ASRock ROMs, assembles the USB stick, and walks the user through flashing, setup variables, shim/MokManager enrollment and verification. Use when the user has this board, or asks to repeat this repo's procedure.
---

# Z97M OC Formula: TPM 2.0 + Secure Boot, end to end

The repo root holds `firmware/`, `tpmboot/`, `usb/`, `tools/` and `docs/`. Read `docs/INSTALL.md` before guiding the user. This skill is the operating checklist.

## Ground rules
- The user flashes with an **external SPI programmer** (DIP-8 socket). Never suggest flashing modded firmware without confirming the user has a programmer and a verified dump of their own chip.
- Don't invent UI. This board has **no Dr. Debug display** and **no Security tab**: Secure Boot is under the **Boot** tab, and the TPM menu is hidden (it is set through the `Setup` variable).
- Give honest odds, and don't present a new theory as certain. Verify it with a test the user can run.
- Never redistribute ASRock ROMs or user dumps. Dumps contain the MAC, serial and UUID.

## Step 1: inputs (on the user's PC, Linux or WSL)
1. `Z97MOCF2.50` (sha256 `4f896e21…`) and `Z97Ex62.80A` (sha256 `f096bc69…`); URLs are in docs/INSTALL.md. The 2.80A beta link may return 403. If it does, the user has to get the file from ASRock support or the forum. Don't substitute another donor without re-validating the offsets.
2. `pip install uefi_firmware`.

## Step 2: build and verify
```bash
python3 firmware/build_tpm2_bios.py --stock Z97MOCF2.50 --donor Z97Ex62.80A --out Z97MOCF_TPM2_8MB.bin
python3 firmware/verify_image.py Z97MOCF_TPM2_8MB.bin --stock Z97MOCF2.50   # must exit 0
```
The expected output sha256 is `c6893a97275c1ed39000e7edeaa348c82ab97642668a9506ec69f1c043b4032c` (the builder prints "MATCHES"). If the user has a dump, check that two reads are identical and the dump doesn't end in a long 0xFF run, then run `firmware/merge_nvram.py --dump … --mod … --out flash_me.bin`.

## Step 3: USB stick
`bash usb/make_usb.sh`, then copy the contents of `usb/out/` to a FAT32 stick. It needs gcc and binutils for tpmboot; `tpmboot/build.sh` downloads gnu-efi 3.0.17.

## Step 4: guide the user on the board, in this order
1. Flash the 8 MiB image and verify. If a verify fails at a random address, or the board doesn't POST after a good verify, re-seat the chip (bad socket contact).
2. Boot the stick (F11). The shell auto-runs `startup.nsh`, which prints the current values. Run `tpm_fw_off.nsh`, then `reset`. **Never set `Setup:0x33=1`** (forced 2.0 hangs before the shell; recovery is a CMOS clear).
3. On the stick, run `tpmboot.efi`. Expect `DID_VID=001a15d1`, `Startup … OK`, `SelfTest … OK`, `TPM2 ACPI table: Success`, and then Windows boots. If it prints `TPM still not reachable`, run `tpm_fw_on.nsh` and accept an occasional splash freeze.
4. Run `install_sb.nsh`, then `reset`.
5. BIOS, Boot tab, Secure Boot: Install default keys, then Enabled.
6. On the first boot, the blue "Verification failed" appears. Have the user press a key, choose **Enroll hash from disk**, pick the NVMe/SSD first partition, and select `EFI\tpmboot\grubx64.efi`. For the stick, the entry is `EFI\BOOT\grubx64.efi` on the stick's volume.
7. Verify: `tpm.msc` shows ready, 2.0. `msinfo32` shows Secure Boot On. `Get-Tpm`, `Confirm-SecureBootUEFI`.

## Diagnosis map
Go through the `docs/INSTALL.md` troubleshooting table. The key facts:
- `0x8028001E` means the TPM2 table is missing, so tpmboot didn't run.
- "Compatible TPM cannot be found" means there is no MSFT0101 device: the firmware isn't flashed, or the wrong image is flashed.
- "malformed section header" means a bad `.sbat` (fix with `tools/pe_sbat.py`).
- A red AMI violation before shim means the keys are missing.
For anything deeper, use the `windows-tpm2-acpi`, `uefi-tpm2-preboot` and `shim-secure-boot` skills.
