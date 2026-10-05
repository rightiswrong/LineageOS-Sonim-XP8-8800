<!--
SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
SPDX-License-Identifier: Apache-2.0
-->
# LineageOS for the Sonim XP8 (XP8800)

Unofficial LineageOS 23.2 (Android 16 QPR2) for the Sonim XP8, model XP8800
(Snapdragon 630, 2018, last stock Android 10).

> [!WARNING]
> **Status: built and tested offline, not yet run on a phone.** Installing
> needs an EDL bootloader swap that can brick the phone if done wrong, wipes
> all data, and leaves SELinux permissive and the bootloader unlocked.

## Can LineageOS be ported to the XP8?

- **Native port (device tree + kernel from source, official-style): no, not
  today.** Sonim never published the XP8 kernel source. LineageOS forbids
  prebuilt kernels on devices like this, and the eBPF support LineageOS has
  needed since version 19 can only be added to a 4.4 kernel by patching its
  source.
- **LineageOS on the XP8: yes, as a GSI.** The community has unlocked the
  bootloader and made the stock Android 10 vendor Treble-capable
  ([ndoo/sonim-xp8-gsi](https://github.com/ndoo/sonim-xp8-gsi)), and a
  TrebleDroid-based LineageOS 23.2 GSI
  ([MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi))
  already carries the fixes this kernel needs. This repository joins the two
  and checks every constraint before anything is flashed.

The full step-by-step reasoning is in **[docs/FEASIBILITY.md](docs/FEASIBILITY.md)**.

## How it fits together

| Partition | Comes from | Built by |
|---|---|---|
| `system_a` | LineageOS 23.2 **EXT4** GSI + XP8 IMS app | `lineage-gsi/build.sh` (this repo) |
| `vendor_a` | Your phone's stock Android 10 vendor + ndoo's fixes (fstab/FBE, vibrator, shim, overlays) + patched Messaging | `lineage-gsi/assemble.sh` → ndoo's `assemble.sh` |
| `boot_a` | Your phone's stock kernel, vendor early-mount enabled | same |
| `abl_a` | AT&T 8.1 userdebug bootloader (unlockable) | ndoo's `unlock.sh` |

Why only the EXT4 GSI: the stock 4.4.205 kernel has no EROFS driver, and only
the EXT4 LineageOS targets include VNDK 29, which the XP8's vendor needs.
`lineage-gsi/lib/check_gsi.py` refuses any image that breaks these rules.

## Install

See **[docs/INSTALL.md](docs/INSTALL.md)**. In short:

```sh
git clone --recurse-submodules https://github.com/rightiswrong/LineageOS-Sonim-XP8-8800
cd LineageOS-Sonim-XP8-8800
third_party/sonim-xp8-gsi/scripts/dump-stock.sh "$BACKUP"     # 1 back up (EDL)
third_party/sonim-xp8-gsi/scripts/unlock.sh --abl work/userdebug/abl.elf "$BACKUP"  # 2 unlock
lineage-gsi/build.sh --variant gapps                          # 3 system.img
lineage-gsi/assemble.sh "$BACKUP"                             # 4 boot.img, vendor.img
third_party/sonim-xp8-gsi/scripts/flash.sh --dir out --wipe   # 5 flash
```

## Expected state

| | |
|---|---|
| Expected to work (works on ndoo's TrebleDroid build with the same boot/vendor) | boot, calls, SMS, VoLTE, Wi-Fi, mobile data, fingerprint, vibration, audio, FBE |
| Unknown, please test | camera, NFC, PTT/programmable keys, FM radio, magnetic connector |
| Not possible on this kernel | per-app data usage and firewall (no eBPF), EROFS, FBE v2 |
| Security | SELinux permissive, unlocked bootloader, kernel/vendor patch level Sept 2020 |

## Repository layout

| Path | What |
|---|---|
| `docs/FEASIBILITY.md` | Why a native port is blocked and why the GSI route works |
| `docs/INSTALL.md` | Back up, unlock, build, assemble, flash |
| `docs/SOURCE-PORT.md` | Plan for a native port: GPL request, CodeLinaro rebuild, mainline |
| `lineage-gsi/` | Build scripts: fetch and check the GSI, add the XP8 IMS app, adapt ndoo's vendor recipe |
| `tools/kernel-facts.py` | Reads your `boot_a` dump: kernel version, DTBs, config, missing LineageOS features |
| `tests/` | Offline tests (synthetic images; no downloads, no phone) |
| `third_party/sonim-xp8-gsi` | ndoo's toolkit (MIT), pinned submodule: EDL backup, unlock, assemble, flash, restore |

## Credits

- [ndoo (Andrew Yong)](https://github.com/ndoo/sonim-xp8-gsi): the XP8 unlock,
  vendor and boot work this builds on.
- [HoldYouClose1988/genesisXP8](https://github.com/HoldYouClose1988/genesisXP8)
  and the [XDA XP8 thread](https://xdaforums.com/t/sonim-xp8-root.3851187/):
  the original unlock research.
- [MisterZtr](https://github.com/MisterZtr/LineageOS_gsi) and the
  [TrebleDroid](https://github.com/TrebleDroid) contributors: the LineageOS GSI
  and its legacy-kernel patches.
- [The LineageOS Project](https://lineageos.org).

Not affiliated with Sonim Technologies or the LineageOS Project. Apache-2.0
(see [LICENSE](LICENSE)); third-party components keep their own licenses
([NOTICE.md](NOTICE.md)).
