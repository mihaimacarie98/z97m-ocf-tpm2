# Dead ends and lessons

This is the honest log of what failed, in order, so nobody has to repeat it.

| Build | Change | Result | Lesson |
|---|---|---|---|
| v1 | All 5 TPM2 modules inserted into the nested **DXE** FV | No POST | PEIMs placed in a DXE volume never run. |
| v2 | PEIMs moved to the PEI FV, DXE drivers in the nested FV | No POST | — |
| v3 | No recompression: DXE drivers in the outer FV's free space | No POST | Structure was not the problem. |
| v4 | **Whole TCG framework** swapped (from the Killer P2.60A donor), XIP PEIMs rebased | **Boots** | ASRock's TPM2 betas replace the framework; adding modules isn't enough. |
| v5 | Same as v4, Extreme6 donor | Boots, identical behavior | Donor choice doesn't matter. |
| v6 | Donor `Device(_SB.TPM)` grafted into the DSDT | No TPM in Windows | Its `_STA` depends on `TPMF`, which only the donor firmware sets. |
| v7 | + `TPMF=One` | Still nothing | — |
| v8/v9 | Minimal 116-byte `MSFT0101` device (v9 also drops the extra Names) | Windows enumerates `ACPI\MSFT0101`, but `tpm.msc` shows **0x8028001E** | The device works. The **TPM2 table** is missing. |
| v10 | Control build: stock DSDT + `TPMF=One` | — | Used to rule out a parser abort. |
| tpmboot | Pre-boot app publishes the TPM2 table | **TPM ready, 2.0** | Final architecture. |

## Theories that were wrong
- **TPM interrupt not wired on a clone module.** `INT_ENABLE=0x8` and `INT_VECTOR=0` show the firmware polls.
- **Bad clone module.** A genuine ASRock TPM2-S behaves identically. `INTERFACE_ID=0xFFFFFFFF` is normal for the SLB9665.
- **TrEEDxe picks CRB instead of FIFO.** Disassembly shows `IsCrbInterface()` correctly chooses FIFO.
- **AML parser aborts inside the grafted region.** The "canary" devices used to test this (lid, dock, EC, batteries, WMI1) are never materialized even on stock, so they proved nothing.
- **Duplicate `\_SB.TPM` object.** There isn't one.

## Practical lessons
- **Check the socket first.** Failed verifies at random addresses and no-POST after a good flash were bent DIP-8 legs, not bad images.
- **Prove the chip before touching firmware.** Raw TIS from the UEFI shell with `mm` (`usb/nsh/tpmtest.nsh`: `TPM2_Startup` and `SelfTest` both returned 0) separated hardware problems from software problems on day one.
- **Read what Windows actually received.** `HKLM\HARDWARE\ACPI\DSDT` contains the loaded DSDT: compare its length, and decompile it with iasl. `Get-PnpDevice -PresentOnly:$false` shows whether the ACPI device materialized. The exact `tpm.msc` error code points straight at the missing piece.
- **Hidden setup options** can be found by extracting the IFR from the Setup module and writing the `Setup` variable with `setup_var.efi`. Watch out for forced-2.0 (`0x33=1`) on this board: it hangs before the shell loads, and the way out is a CMOS clear.
- **Toolchain gotchas:** `uefi_firmware`'s `LzmaCompress` corrupts inputs over 1 MiB. UEFIExtract NE binaries need a newer glibc than Ubuntu 20.04 has. Debian's iasl (acpica-tools 20200925) runs fine. gnu-efi's Makefiles break on paths with spaces.
- **Secure Boot:** shim needs `.sbat`, and the section must be well-formed. Every rebuild changes the hash, so MokManager must enroll it again.
