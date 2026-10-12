---
name: aptio-tpm2-port
description: Methodology for porting a discrete TPM 2.0 stack into an AMI Aptio IV BIOS (Haswell/Broadwell era: Z87/Z97/H97/X99 boards) that never got official TPM 2.0 support, using a same-vendor donor BIOS that has it. Covers module selection, PEI XIP rebasing, nested LZMA DXE FV rebuild, checksums, verification and flashing safety. Use when asked to "add TPM 2.0 to <old board> BIOS" or to adapt firmware/build_tpm2_bios.py to another board.
---

# Porting TPM 2.0 into an AMI Aptio IV BIOS

The reference implementation is `firmware/build_tpm2_bios.py`, for the ASRock Z97M OC Formula with the Z97 Extreme6 P2.80A as donor. Read it first, and parameterize it instead of rewriting it.

## 0. Set expectations
The firmware port alone did **not** make Windows see the TPM on the reference board. It also needed a DSDT `MSFT0101` device (see `windows-tpm2-acpi`) and a pre-boot app to publish the TPM2 table (see `uefi-tpm2-preboot`). Tell the user this up front. Many boards need all three parts.

## 1. Pick the donor
- Use the same vendor and the same platform (chipset and Aptio generation). Vendors that shipped "TPM2 beta" BIOSes for siblings, as ASRock did for the Z97 Extreme6 and Fatal1ty Z97 Killer, are ideal.
- Diff the donor against its *own* previous non-TPM2 release to find the real TPM2 delta. On ASRock this was **the whole TCG framework**, not just the 5 visible TPM2 modules:
  - PEI: TcgPlatformSetupPeiPolicy, TcgPei, TcgPeiplatform, AmiTcgPlatformPeiBefore/AfterMem replaced; TpmClearOnRollbackPei removed; TrEEPei and AmiTpm20PlatformPei added.
  - DXE: TcgDxe, TcgPlatformSetupPolicy, TcgDxeplatform, AmiTcgPlatformDxe, TCGSmm, TcgLegacy, AmiTcgNvflagSample, TpmClearOnRollback replaced; TrEEDxe, Tpm20PlatformDxe, Tpm20Acpi added.
  - Adding only the 5 TPM2 modules gives **no POST**.
- Match modules by FFS GUID. GUIDs are stable across ASRock boards.

## 2. Tooling (it works on old glibc)
- `pip install uefi_firmware`: use its `efi_compressor.LzmaDecompress` (the EDK2 decoder) as the oracle. **Its LzmaCompress is broken above 1 MiB.** Compress with Python `lzma.compress(..., format=FORMAT_ALONE, filters=[LZMA1 dict 0x800000 lc3 lp0 pb2])`, then patch the 8-byte size field at offset 5 to the real length. Always decompress the result with the EDK2 decoder and compare.
- UEFITool/UEFIExtract NE builds need a recent glibc. Python walking of FV/FFS (see `walk()`) is enough.

## 3. Rules for each region
- **PEI FV:** PEIMs execute in place (XIP), so a PE32 PEIM moved to a new offset must be **rebased**. Set ImageBase to `flash_base + file_offset + section_offset`, and add the delta to every `IMAGE_REL_BASED_HIGHLOW` relocation (see `rebase_pe32_in_ffs`). Compressed PEIMs (they run from RAM) don't need it. Put new PEIMs inside an existing pad file and shrink the pad, so microcode, the FIT and the boot-block offsets don't move. Then assert that they are byte-identical to stock.
- **DXE:** the main DXE FV is usually a nested FV in an LZMA GUID-defined section. Rebuild the file list with 8-byte alignment, append new drivers, grow `FvLength` and the block map if needed (the donor's size is a safe target), and recompute the FV header checksum. Keep the section trailer that follows the FV in the decompressed stream.
- **FFS checksums:** header checksum over 24 bytes, with State and IntegrityCheck.File zeroed. If attribute 0x40 is set, the body checksum goes in byte 17.
- Assert everything: the file count in the replaced region, size limits, a decompress round-trip, and identity of the untouched regions (`firmware/verify_image.py` is the template).

## 3b. Adding your own driver
A small custom DXE driver (e.g. `tpmdxe/`) can fill gaps the vendor stack leaves, such as publishing the TPM2 table. Append it to the nested DXE FV as an FFS DRIVER file with a minimal depex. Firmware-volume code is trusted by Secure Boot, so this is cleaner than any boot-chain workaround. Always offer a no-flash dry run first (shell `load driver.efi`).

## 4. Setup gating
Ported TPM menus are often hidden, or their defaults are off. Extract the IFR from the Setup module, find the varstore offsets (on the reference board: `0x26` support, `0x21` state, `0x33` device select, `0x4A1` ASRock auto-detect), and write them with `setup_var.efi` from a UEFI shell. Test forced-2.0 last: it can hang before the shell, and the recovery is a CMOS clear.

## 5. Safety protocol with the user
- Insist on an external programmer, two identical dumps, and a known-good fallback image (stock ROM minus its 4 KiB header).
- When flashes fail, suspect the socket or clip contact before blaming the image.
- Prove the TPM chip works with raw TIS from the shell (`usb/nsh/tpmtest.nsh`) before you spend time on firmware.
- Keep a numbered build log (v1, v2, …) with exactly one change per build, and say what each test will distinguish.
