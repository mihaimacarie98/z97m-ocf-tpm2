---
name: shim-secure-boot
description: Run a custom or unsigned EFI program with Secure Boot ON, on firmware that only has Microsoft's keys and no "enroll EFI image" option, by using the Microsoft-signed shim plus MokManager hash enrollment. Covers choosing matching signed shim/MokManager binaries, the mandatory .sbat section, and the errors "Verification failed (0x1A) Security Violation", "malformed section header", and red AMI Secure Boot Violation. Use whenever a user must boot their own .efi under Secure Boot.
---

# Secure Boot via signed shim + MOK

## Chain
Firmware (Microsoft UEFI CA 2011 in db) → `shimx64.efi` (signed by Microsoft) → `grubx64.efi` (yours; trusted through a MOK **hash**) → anything your program starts with `BS->LoadImage`, which shim verifies (e.g. `bootmgfw.efi`, signed by Microsoft).

## Pick binaries that belong together
- shim's embedded vendor cert must have signed MokManager. Use **Debian** `shim-signed` (`/usr/lib/shim/shimx64.efi.signed`) together with Debian `shim-helpers-amd64-signed` (`mmx64.efi.signed`). `usb/make_usb.sh` pins shim-signed 1.51+16.1-2 and helpers 1+16.1+2 by sha256.
- **Ubuntu's plain `/usr/lib/shim/shimx64.efi` is unsigned**; the signed builds are `shimx64.efi.signed.latest` / `.dualsigned`. Check for an Authenticode signature: PE data directory 4 (certificate table) must have size > 0.
- Layout: shim, `mmx64.efi` and `grubx64.efi` in the same directory. Name your program `grubx64.efi`, because shim loads that name by default.

## The .sbat requirement (shim 15.3+)
- A second stage **without** a `.sbat` section is refused even when its hash is enrolled. The user sees "Verification failed / Security Violation" again after enrolling.
- The section must be a valid PE section: VA ≥ SizeOfHeaders, VA+size ≤ SizeOfImage, raw data inside the file, aligned to SectionAlignment/FileAlignment, and sections sorted by VA.
- **`objcopy --add-section .sbat=file` on a finished PE puts the section at VA 0 on top of the headers.** shim then reports **"malformed section header"**. Do one of these instead:
  - At link time, add an output section in the linker script after `.data` (see `tpmboot/build.sh`).
  - For prebuilt binaries, run `tools/pe_sbat.py add IN OUT --component "name,1,Vendor,pkg,ver,url"`. It appends a section header (it needs 40 free bytes after the table), with VA = end of image and raw data = end of file, and updates SizeOfImage.
  - Always run `tools/pe_sbat.py check` before giving a file to the user.
- CSV: line 1 is `sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md`; line 2 is your component with generation 1.

## User procedure (firmware side)
1. If keys were cleared (Setup Mode), use Key Management → **Install default Secure Boot keys**. Then set Secure Boot Enabled.
2. On the first boot, shim shows the blue "Verification failed (0x1A)". Press a key → MokManager → **Enroll hash from disk** → choose the right volume → select `grubx64.efi` → Continue → Yes → Reboot.
   - Volume names in MokManager are cryptic. The ESP is usually the first partition of the NVMe/SSD (`PciRoot…/Pci(0x1C,…)/…`), and a USB stick shows its volume label. "System Reserved" partitions on old MBR disks are the wrong choice.
3. Each **different file needs its own enrollment**, e.g. the stick's shell and the ESP's program. So does every rebuild.

## Error map
| Error | Who | Fix |
|---|---|---|
| Red/white AMI "Secure Boot Violation" before any shim screen | Firmware rejects shim | Keys are missing: install the default keys. Or a corrupted or unsigned shim was used. |
| Blue "Verification failed (0x1A)" on the first boot | shim, expected | Enroll the hash |
| Same box again after enrolling | shim | Missing `.sbat`, the file changed after enrollment, or the wrong file or volume was enrolled |
| "malformed section header" | shim's PE loader | Bad `.sbat` placement; rebuild as above |
| Boots, but Windows says Secure Boot Off | — | Secure Boot isn't enabled in setup, or the firmware is still in Setup Mode |
