# TPM 2.0 + Secure Boot on the ASRock Z97M OC Formula

ASRock never released a TPM 2.0 BIOS for the **Z97M OC Formula** (last BIOS P2.50, 2018). This repo makes a discrete LPC TPM 2.0 module (ASRock **TPM2-S**, Infineon SLB9665) work in Windows **with Secure Boot on**, which is what Windows 11 and anti-cheat systems such as EA Javelin (Battlefield 6) check for.

**Status:** working on real hardware (i7-4790K, ASRock TPM2-S). `tpm.msc` shows *"The TPM is ready for use"*, specification version 2.0, and `msinfo32` shows Secure Boot State *On*.

> You need an **external SPI programmer** (CH341A or similar) and you must be able to recover with it. The board's BIOS chip is a socketed DIP-8. Flashing modified firmware can brick a board, and you do it at your own risk.

## How it works (three parts)

| Part | What | Why |
|---|---|---|
| **Firmware** (`firmware/`) | Ports ASRock's TPM 2.0 stack (TrEE PEI/DXE, Tpm20 platform drivers, TPM2-aware TCG framework) from the Z97 Extreme6 P2.80A beta into stock P2.50. Replaces the DSDT's TPM 1.2 stub with a `MSFT0101` device. | Windows only finds a TPM 2.0 through an ACPI device with `_HID "MSFT0101"`. |
| **tpmboot.efi** (`tpmboot/`) | A small UEFI app that runs before Windows: `TPM2_Startup` + `SelfTest`, installs the **TPM2 ACPI table**, then chain-loads `bootmgfw.efi`. | Even with the stack ported, this board's firmware never publishes the TPM2 table. Without that table, Windows talks TPM **1.2** to the chip and fails with `0x8028001E`. |
| **Secure Boot chain** (`usb/`) | Microsoft-signed **shim** → `grubx64.efi` (= tpmboot, hash enrolled once in MokManager) → Windows Boot Manager. | This lets Secure Boot stay **on** with an unsigned pre-boot app and the default Microsoft keys. |

tpmboot can never block booting: if any TPM step fails, it still starts Windows.

## Quick start

```bash
# 1. Firmware: download the two official ASRock ROMs yourself (see docs/INSTALL.md)
pip install uefi_firmware
python3 firmware/build_tpm2_bios.py --stock Z97MOCF2.50 --donor Z97Ex62.80A --out Z97MOCF_TPM2_8MB.bin
python3 firmware/verify_image.py Z97MOCF_TPM2_8MB.bin --stock Z97MOCF2.50
#    optional: keep your MAC/serial from your own chip dump
python3 firmware/merge_nvram.py --dump my_dump.bin --mod Z97MOCF_TPM2_8MB.bin --out flash_me.bin

# 2. USB stick (downloads the signed shim/MokManager, UEFI shell and setup_var, all sha256-pinned; builds tpmboot)
bash usb/make_usb.sh        # -> usb/out/, copy its contents to a FAT32 stick
```

Then follow **[docs/INSTALL.md](docs/INSTALL.md)**: flash, set the TPM setup variables, run `install_sb.nsh`, enable Secure Boot, and enroll the hash once in MokManager.

Both builds are reproducible. `build_tpm2_bios.py` outputs exactly the image that was tested on hardware (sha256 `c6893a97…`), and `make_usb.sh` produces the same files as the stick that worked (tpmboot `17ac5f2b…`).

## Repo layout

```
firmware/   build_tpm2_bios.py (ROM builder), verify_image.py, merge_nvram.py, acpi/min_tpm.dsl
tpmboot/    tpmboot.c, build.sh (gnu-efi 3.0.17, link-time .sbat), sbat.csv
tools/      pe_sbat.py: check/add a shim-compatible .sbat section on any PE
usb/        make_usb.sh, nsh/ (UEFI shell scripts: installers, setup-variable presets, raw TIS tests)
docs/       INSTALL.md, HOW_IT_WORKS.md, LESSONS.md (every dead end and why)
skills/     Agent Skills (SKILL.md) to let an LLM agent repeat or adapt this work
```

## Agent skills

`skills/` holds five [Agent Skills](https://docs.claude.com/en/docs/claude-code/skills) that capture this whole process for LLM coding agents:

| Skill | Use it for |
|---|---|
| `z97m-ocf-tpm2` | Running the whole procedure for this board, end to end |
| `aptio-tpm2-port` | Porting a TPM 2.0 stack into another AMI Aptio IV board's BIOS |
| `windows-tpm2-acpi` | DSDT `MSFT0101` device, the TPM2 table, and Windows-side diagnosis |
| `uefi-tpm2-preboot` | Adapting tpmboot (TIS commands, TPM2 table, LPC decode, chain-load) |
| `shim-secure-boot` | Signed shim + MokManager + SBAT; fixes for "Security Violation" and "malformed section header" |

Install them in Claude Code as a plugin:
```
/plugin marketplace add mihaimacarie98/z97m-ocf-tpm2
/plugin install z97m-tpm2-skills@z97m-ocf-tpm2
```
Or copy `skills/*` into `~/.claude/skills/`. They are plain Markdown, so any agent that reads `SKILL.md` files can use them.

## What is *not* in this repo

There are no ASRock firmware images and no chip dumps. Dumps contain per-board data such as MAC, serial and UUID. The builder takes the official ROMs as inputs and checks their sha256. Third-party EFI binaries are downloaded from their upstream sources by `make_usb.sh` and verified against pinned hashes.

## Credits / licenses

- Code in this repo: MIT (see `LICENSE`).
- [rhboot/shim](https://github.com/rhboot/shim): Debian's Microsoft-signed build. MokManager is signed by Debian.
- [pbatard/UEFI-Shell](https://github.com/pbatard/UEFI-Shell) (EDK2 shell builds), [datasone/setup_var.efi](https://github.com/datasone/setup_var.efi) (Apache-2.0), [gnu-efi](https://sourceforge.net/projects/gnu-efi/).
- Donor TPM 2.0 modules: ASRock's own TPM2 beta BIOSes. The win-raid forum TPM 2.0 threads pointed at the DSDT requirement.
