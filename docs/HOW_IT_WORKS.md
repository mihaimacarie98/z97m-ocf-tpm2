# How it works

## What Windows needs to use a discrete TPM 2.0

1. **An ACPI namespace device** with `_HID "MSFT0101"` (or `_CID PNP0C31`), `_STA` returning 0x0F, and `_CRS` covering the TIS window `0xFED40000`, length `0x5000`. Without it, tpm.sys never loads, and `tpm.msc` says *"Compatible TPM cannot be found"*.
2. **A `TPM2` ACPI table.** tpm.sys reads it to decide the TPM family and the start method. If it's missing, Windows assumes TPM **1.2**, sends 1.2-format commands, and the 2.0 chip rejects them: `tpm.msc` shows *"TPM 1.2: The tag value sent … is invalid (0x8028001E = TPM_BAD_TAG)"*. Seeing that error proves the device, the driver and the LPC bus all work, and only the table is missing.
3. **A started TPM** (`TPM2_Startup(CLEAR)`). Normally the firmware does this.

Stock P2.50 provides none of these.

## Firmware part (`firmware/build_tpm2_bios.py`)

The image layout is AMI Aptio IV, 8 MiB: descriptor at 0x0, ME at 0x1000, NVRAM stores at 0x200000 and 0x220000, main FV at 0x250000, PEI FV at 0x700000, then microcode, FIT and the boot block.

- **TCG framework swap.** ASRock's TPM2 betas don't just add five modules. They replace the whole TCG framework with TPM2-aware builds. Running the new TrEE modules on top of the old 1.2-only framework hangs PEI/DXE with no POST. That was the cause of the first three failed builds.
  - PEI: 5 modules (TcgPlatformSetupPeiPolicy, TcgPei, TcgPeiplatform, AmiTcgPlatformPei Before/AfterMem) are replaced in place, and TpmClearOnRollbackPei is removed. Three of them are XIP PE32 images, so they are **rebased**: ImageBase is set to the new flash address and the HIGHLOW relocations are re-applied.
  - TrEEPei and AmiTpm20PlatformPei go into the space of the big PEI pad file, so nothing else in the PEI FV moves. Microcode, FIT and everything after stay byte-identical.
  - DXE: the nested FV is LZMA-compressed inside the main FV (GUID `ae717c2f-…`). It is decompressed, 8 framework drivers are replaced, TrEEDxe, Tpm20PlatformDxe and Tpm20Acpi are appended, and the FV grows from 0xB0D000 to 0xB56000 (the donor's own size). Then it is recompressed.
  - **LZMA:** Python `lzma` FORMAT_ALONE (LZMA1, dict 0x800000, lc3 lp0 pb2), with the 8-byte uncompressed-size field patched in. The result is checked with the EDK2 decoder (`uefi_firmware.efi_compressor.LzmaDecompress`). Don't use that package's `LzmaCompress`: it corrupts inputs larger than 1 MiB.
- **DSDT.** The DSDT is embedded in the AmiBoardInfo driver (`9f3a0016-…`), and real data follows it, so the new DSDT must not grow. The builder removes the TPM 1.2 stub (`Device(_SB.PCI0.LPCB.TPM)` plus its `Scope`, 0x447 bytes) and inserts a 116-byte minimal device compiled from `acpi/min_tpm.dsl`. It also flips `Name(TPMF, Zero)` to `One`, which makes the stock `TPMX` device (a PNP0C01 reservation of the same range) hide itself. The edit is done in binary AML, because iasl can't round-trip AMI's DSDT.
  - The donors' own `Device(_SB.TPM)` was tried first. It needs runtime globals (`TPMF`, `TTDP`, …) that only the donor firmware sets. The minimal device has no such dependencies.
- **Donor choice.** Z97 Extreme6 P2.80A (2021) is used. The Fatal1ty Z97 Killer P2.60A (2018) was also tried and behaved identically.

## Why the firmware's own TPM2 path isn't used

With the stack ported, `Device Select = Auto` boots, but the firmware treats the SLB9665 as TPM 1.2. Its `INTERFACE_ID` register (0x30) reads 0xFFFFFFFF, which is normal for this chip. So the firmware never installs the TrEE protocol, and `Tpm20Acpi`, which depends on TrEE, never publishes the TPM2 table. Forced `2.0` hangs in DXE before the shell can load. With firmware TPM support on, the 1.2 init path also freezes the splash screen now and then. Decoding why would need hardware debugging (serial/POST). Instead, the job moved to a pre-boot app.

## tpmboot.efi

`tpmboot/tpmboot.c` is a ~120-line gnu-efi application that polls the TIS FIFO directly (no interrupts):

1. Reads `DID_VID` (0xFED40F00); 0x001A15D1 is the SLB9665. If it reads 0xFFFFFFFF, the TPM range isn't decoded because firmware TPM support is off. It then enables memory decode on the PCH LPC bridge (B0:D31:F0, command register bit 1) and points **LGMR** (config offset 0x98) at `0xFED40000 | enable`, which opens a 64 KiB LPC memory window. Then it probes again.
2. Sends `TPM2_Startup(SU_CLEAR)` (rc 0x100 = already started, which is fine) and `TPM2_SelfTest(full)`.
3. Installs a 52-byte `TPM2` table: revision 3, PlatformClass 0 (client), ControlArea 0, **StartMethod 6** (TIS/FIFO), through `EFI_ACPI_TABLE_PROTOCOL`. The table is in place before `ExitBootServices`, so Windows sees it.
4. One-shot `TPM2_Clear(TPM_RH_PLATFORM)` if `\EFI\tpmboot\clear` exists on the ESP. Platform auth is empty because no firmware ever set it.
5. `LoadImage`/`StartImage` on `\EFI\Microsoft\Boot\bootmgfw.efi`. On any failure it still boots Windows.

## Secure Boot chain

The firmware ships Microsoft's keys, and it has no "enroll EFI image" option. So the chain is:

`BOOTX64.EFI / shimx64.efi` (signed by Microsoft UEFI CA 2011) → `grubx64.efi` (= tpmboot, trusted through a **MOK hash** enrolled with MokManager) → `bootmgfw.efi` (signed by Microsoft).

- shim's vendor certificate has to match MokManager's signer. Debian `shim-signed` and Debian `shim-helpers-amd64-signed` go together. Ubuntu's plain `/usr/lib/shim/shimx64.efi` is **unsigned**; its signed builds are the `.signed.*` files.
- shim 15.3+ refuses any second stage without a **`.sbat`** section, even if its hash is enrolled. The section has to be a real, aligned PE section after the headers. `objcopy --add-section` gets this wrong, and shim reports "malformed section header". `tools/pe_sbat.py` validates and adds the section correctly.
- tpmboot starts bootmgfw with `BS->LoadImage`, and shim hooks that call to verify bootmgfw's Microsoft signature, so the chain stays verified end to end. Windows reports Secure Boot **On** because the firmware is in user mode with Secure Boot enabled.
