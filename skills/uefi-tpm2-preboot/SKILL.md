---
name: uefi-tpm2-preboot
description: Build or adapt a small pre-boot UEFI application (tpmboot.efi, gnu-efi) that brings up a TIS/FIFO TPM 2.0 itself (TPM2_Startup, SelfTest, optional Clear), opens the PCH LPC decode window if firmware left it closed, installs the TPM2 ACPI table, and chain-loads the Windows Boot Manager. Use when firmware will not initialize or publish a TPM 2.0 but the chip answers at 0xFED40000.
---

# Pre-boot TPM 2.0 bring-up (tpmboot)

Source: `tpmboot/tpmboot.c`, about 120 lines. Build: `tpmboot/build.sh` (gnu-efi 3.0.17, sha256-pinned download, link-time `.sbat`). The build is reproducible: the reference binary's sha256 is `17ac5f2b…`.

## Prerequisites to confirm first
1. The chip answers. From a UEFI shell, `mm FED40F00 -MMIO -w 4 -n` returns a vendor/device ID rather than `FFFFFFFF` (Infineon SLB9665 = `001A15D1`). If it reads FF, try with firmware TPM support enabled, or rely on the LPC step below.
2. Raw commands work. `usb/nsh/tpmtest.nsh` sends Startup and SelfTest through `mm`; response bytes 7–10 must be `00 00 00 00`.
3. Windows has an ACPI device for the TPM (`MSFT0101`); see `windows-tpm2-acpi`. The app only adds the *table*.

## Design rules
- **Never block boot.** Every TPM step is best-effort, and the program always ends by starting `\EFI\Microsoft\Boot\bootmgfw.efi` (found by scanning all SimpleFileSystem handles). Print status, and pause about 3 s so the user can photograph it.
- **TIS FIFO, polling only:** request locality 0 (ACCESS = 0x02, wait for bit 0x20), set commandReady (STS = 0x40), write the command bytes one at a time while burstCount > 0, write GO (0x20), wait for STS valid|dataAvail (0x90), read while dataAvail, then set commandReady and release the locality. The rc is response bytes 6–9, big-endian.
- `TPM2_Startup(SU_CLEAR)` = `80 01 00 00 00 0C 00 00 01 44 00 00`. rc `0x100` (TPM_RC_INITIALIZE) means it has already started, which is fine.
- `TPM2_SelfTest(YES)` = `80 01 00 00 00 0B 00 00 01 43 01`.
- `TPM2_Clear(TPM_RH_PLATFORM)` with an empty password session works when no firmware has set platform auth. Gate it behind a one-shot flag file on the ESP and delete the file afterwards.
- **TPM2 table:** 52 bytes, revision 3, PlatformClass 0, ControlArea 0, StartMethod **6** (TIS). Install it through `EFI_ACPI_TABLE_PROTOCOL` (`ffe06bdd-6107-46a6-7bb2-5a9c7ec5275c`); the protocol recomputes the RSDT/XSDT. Choose OEM IDs that match the firmware's other tables.
- **LPC decode (Intel 8/9-series PCH):** if DID_VID reads FF, set the LPC bridge's (B0:D31:F0) command-register memory-enable bit and write **LGMR** (config 0x98) = `0xFED40000 | 1` through CF8/CFC, then probe again. For other chipsets, look up the generic memory decode register in that PCH's datasheet.

## Build gotchas
- gnu-efi's Makefiles fail on paths that contain spaces. Build outside the checkout (`TPMBOOT_BUILD_DIR`).
- Flags: `-fpic -fno-stack-protector -fshort-wchar -mno-red-zone -DEFI_FUNCTION_WRAPPER -ffreestanding -maccumulate-outgoing-args`. Link crt0 + `-lefi -lgnuefi` + libgcc, then `objcopy --target=efi-app-x86_64 --subsystem=10`.
- To run under shim/Secure Boot, the binary needs a `.sbat` section. Add it at **link time**: a linker-script output section after `.data`, filled with an object made from the CSV by `objcopy -I binary`, and keep it with `-j .sbat`. Check the result with `tools/pe_sbat.py check`.
- Any rebuild changes the Authenticode hash, so the user must enroll it in MokManager again. Tell them this before they reboot.

## Installing
`usb/nsh/install_sb.nsh` (Secure Boot) puts shim, MokManager and the app (named `grubx64.efi`) in `\EFI\tpmboot\` and in the `\EFI\BOOT\` fallback, and adds a `bcfg` entry at position 0. `install_tpmboot.nsh` is the variant for Secure Boot off.
