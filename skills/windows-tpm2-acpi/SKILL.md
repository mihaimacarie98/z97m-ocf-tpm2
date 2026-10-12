---
name: windows-tpm2-acpi
description: Diagnose and fix why Windows does not see a discrete TPM 2.0 at the ACPI level. Covers the DSDT MSFT0101 device, the TPM2 ACPI table, binary AML patching inside AMI's AmiBoardInfo, and Windows-side evidence (registry DSDT dump, PnP state, tpm.msc error codes such as 0x8028001E). Use when tpm.msc says "Compatible TPM cannot be found" or shows TPM 1.2 errors on a 2.0 chip.
---

# Windows ↔ TPM 2.0 over ACPI

## What Windows requires
1. A namespace device: `_HID "MSFT0101"` (tpm.sys also matches `PNP0C31`), `_STA` = 0x0F, and `_CRS` = `Memory32Fixed(RW, 0xFED40000, 0x5000)` for TIS/FIFO.
2. A **TPM2 table** (rev 3+, StartMethod 6 for TIS/FIFO, 7 for CRB). It decides whether tpm.sys speaks 2.0 or 1.2.
3. A started TPM.

## Read the symptom
| tpm.msc / PnP | Meaning |
|---|---|
| "Compatible TPM cannot be found", no `ACPI\MSFT0101` or `ACPI\PNP0C31` in `Get-PnpDevice -PresentOnly:$false` | No device in the namespace, or its `_STA` returns 0 |
| `ACPI\MSFT0101\1` present, but "TPM 1.2: tag value invalid **0x8028001E**" | The device works and the driver talks to the chip, but there is **no TPM2 table**, so Windows sends 1.2 commands |
| Code 10 / not ready | No `TPM2_Startup`, or the start method is wrong |

## Gather evidence before changing anything (PowerShell, admin)
```powershell
# DSDT that Windows actually loaded: compare its length with your build, then decompile with iasl -d
$v=(Get-Item 'HKLM:\HARDWARE\ACPI\DSDT').GetSubKeyNames()[0]; $p="HKLM:\HARDWARE\ACPI\DSDT\$v"
$k=(Get-Item $p).GetSubKeyNames()[0]; $q="$p\$k"; $r=(Get-Item $q).GetSubKeyNames()[0]
[IO.File]::WriteAllBytes("$env:TEMP\dsdt.aml",(Get-ItemProperty "$q\$r").'00000000')
Get-PnpDevice -PresentOnly:$false | ? { $_.InstanceId -match 'MSFT0101|PNP0C31' }
Get-Tpm; tpmtool getdeviceinformation
```
Don't use "canary" devices to test for AML parser aborts unless they materialize on the *stock* firmware. Lid, EC, battery and WMI devices often have `_STA` = 0 on desktops, so their absence proves nothing.

## Patching the DSDT in AMI firmware
- On Aptio IV, the DSDT is embedded in the **AmiBoardInfo** DXE driver (GUID `9f3a0016-ae55-4288-829d-d22fd344c347`), and data follows it. **It must not grow**: remove something at least as big as what you add.
- iasl often can't recompile AMI's decompiled DSDT. Patch the AML in binary: splice at object boundaries (`5B 82` = Device, `10` = Scope, then PkgLength), fix the header length and checksum (byte 9 makes the sum 0 mod 256), then fix the FFS checksums.
- Use a **minimal** device that has no dependency on firmware-set globals. Vendor devices gate `_STA` on names such as `TPMF`, which only their own firmware sets at runtime. Template: `firmware/acpi/min_tpm.dsl`, 116 bytes of AML.
- Remove or neutralize the old TPM 1.2 stub (`PNP0C31` under LPCB). Also check for a `PNP0C01` reservation of 0xFED40000 that switches on `TPMF`.
- Verify with `iasl -d` on the extracted AML, then check what Windows actually loaded (above).

## Getting the TPM2 table published
The firmware's `Tpm20Acpi` driver only installs it when the TrEE/Tcg2 protocol exists. If the firmware's TPM2 init doesn't complete (the reference board misdetects the SLB9665 as 1.2 because `INTERFACE_ID` reads 0xFFFFFFFF), install the table from a pre-boot EFI app through `EFI_ACPI_TABLE_PROTOCOL` before Windows starts. See the `uefi-tpm2-preboot` skill and `tpmboot/tpmboot.c`.
