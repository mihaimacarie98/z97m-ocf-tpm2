# V9 -> V11 migration: removes the shim -> tpmboot boot chain from the Windows EFI partition.
# Run in an ADMIN PowerShell *before* flashing V11 (after this, until V11 is flashed,
# Windows will not see the TPM).  Suspend BitLocker first if it is on.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
if ($bl -and $bl.ProtectionStatus -eq 'On') {
    Write-Host "BitLocker is ON for $env:SystemDrive - suspending it for 2 reboots so the firmware change doesn't trigger recovery."
    Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 2 | Out-Null
}
$drive = 'S:'
mountvol $drive /S
try {
    if (Test-Path "$drive\EFI\BOOT\BOOTX64.BAK") {
        Copy-Item "$drive\EFI\BOOT\BOOTX64.BAK" "$drive\EFI\BOOT\BOOTX64.EFI" -Force
        Remove-Item "$drive\EFI\BOOT\BOOTX64.BAK"
        Write-Host "restored original \EFI\BOOT\BOOTX64.EFI"
    } else {
        Copy-Item "$drive\EFI\Microsoft\Boot\bootmgfw.efi" "$drive\EFI\BOOT\BOOTX64.EFI" -Force
        Write-Host "no backup found - \EFI\BOOT\BOOTX64.EFI set to the Windows boot manager"
    }
    Remove-Item "$drive\EFI\BOOT\mmx64.efi", "$drive\EFI\BOOT\grubx64.efi" -ErrorAction SilentlyContinue
    if (Test-Path "$drive\EFI\tpmboot") { Remove-Item "$drive\EFI\tpmboot" -Recurse -Force; Write-Host "removed \EFI\tpmboot" }
} finally { mountvol $drive /D }

# delete the "TPM Boot" firmware entries, keep Windows Boot Manager first
$cur = $null
foreach ($line in (bcdedit /enum firmware)) {
    if ($line -match '^identifier\s+(\{[0-9a-f-]+\})') { $cur = $Matches[1] }
    elseif ($line -match '^description\s+TPM Boot' -and $cur) { bcdedit /delete $cur | Out-Null; Write-Host "deleted boot entry $cur" }
}
bcdedit /set '{fwbootmgr}' displayorder '{bootmgr}' /addfirst | Out-Null
Write-Host "Done. Now flash V11, then check tpm.msc and msinfo32."
