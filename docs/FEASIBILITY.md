<!--
SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
SPDX-License-Identifier: Apache-2.0
-->
# Can LineageOS run on the Sonim XP8 (XP8800)?

Short answer:

- **A native LineageOS port** (device tree, vendor tree and kernel built from
  the LineageOS source tree, the way official devices are built) **is not
  possible today.** Sonim never published the XP8's kernel source, and
  everything LineageOS needs from the kernel goes through that source.
- **LineageOS running on the XP8 is possible** with the LineageOS 23.2
  (Android 16 QPR2) *generic system image* (GSI), on the stock kernel and a
  vendor partition built from your own phone's stock firmware. That is what
  this repository builds. It is unofficial, uses SELinux permissive and an
  unlocked bootloader, and has known gaps listed at the end.

The rest of this document is the reasoning, one layer at a time, from the
hardware up. Status as of October 2026.

## 1. What "porting LineageOS" requires

An official LineageOS device is built from source with three device-specific
inputs:

| Input | What it is | Where it comes from |
|---|---|---|
| Device tree | `device/<oem>/<codename>`: board config, partitions, fstab, overlays, HAL selection | Written by the porter |
| Vendor tree | `vendor/<oem>/<codename>`: the proprietary blobs | Extracted from stock firmware |
| Kernel | `kernel/<oem>/<platform>`: kernel source + defconfig | **Published by the OEM** (GPLv2) |

The LineageOS
[device support requirements](https://github.com/LineageOS/charter/blob/main/device-support-requirements.md)
add rules on top. The two that matter here:

- *"Non-GKI devices MUST NOT ship a prebuilt kernel."* The XP8 is a 2018,
  4.4-kernel, non-GKI device.
- *"All devices MUST be configured for SELinux Enforcing."*

The alternative to a native port is a GSI: one system image built for every
Treble-compliant phone, which runs on the phone's own kernel and vendor
partition. LineageOS does not publish GSIs itself; TrebleDroid-based
LineageOS GSIs are maintained by community builders.

## 2. Hardware: not a blocker

| | XP8800 | Source |
|---|---|---|
| SoC | Qualcomm SDM630 (Snapdragon 630), platform `sdm660`, octa-core Cortex-A53, Adreno 508 | [GSMArena](https://www.gsmarena.com/sonim_xp8-9147.php), [ndoo technical.md](https://github.com/ndoo/sonim-xp8-gsi/blob/main/docs/technical.md) |
| RAM / storage | 4 GB (3.7 GB usable) / 64 GB eMMC | same |
| Display | 5.0" 1080×1920 | same |
| Launched with | Android 7.1.1; last stock Android 10 (`8A.0.0-03-10.0.0-00.40.00`, Sept 2020 patch) | same |

The SDM630/660 family is well understood in the custom-ROM world (Sony's
Xperia XA2 *pioneer*, for example, has a LineageOS wiki page). Nothing about
the silicon prevents LineageOS. The blockers are all in software Sonim
controls.

## 3. Bootloader: solved by the community, with risk

- Sonim has no unlock programme. The stock Android 10 bootloader (ABL) has no
  `fastboot flashing` command at all.
- The XP8 exposes Qualcomm EDL (emergency download, USB `05c6:9008`) from any
  state, and a Sonim-signed firehose loader exists.
- The community found that the AT&T Android 8.1 **userdebug** ABL is signed
  with the same root certificate, boots stock Android 10, and *does* accept
  `fastboot flashing unlock`. Writing it to `abl_a` over EDL unlocks the phone
  ([ndoo/sonim-xp8-gsi](https://github.com/ndoo/sonim-xp8-gsi),
  [genesisXP8](https://github.com/HoldYouClose1988/genesisXP8),
  [XDA thread](https://xdaforums.com/t/sonim-xp8-root.3851187/)).

So the bootloader can be unlocked, but only by writing a foreign bootloader
over EDL. ndoo's scripts expect the phone on the Android 10 build above and
make a full EDL backup (including IMEI/NV data) first. This repository uses
those scripts as-is.

The Android 10 requirement rules out units that never received Android 10.
A Sprint XP8 (product `XP8823`) checked in October 2026 was on Android 8.1
(`8A.0.5-04-8.1.0-29.64.00`, patch 2020-06-01) with no update offered, and
the community file host's XP8 folder has only Android 7.1.1 and 8.1 debug
images. Cross-flashing another variant's Android 10 over EDL is untested here
and risky: ndoo reports that an AT&T unit flashed with Android 10 stopped
registering on the network.

## 4. Kernel: the blocker for a native port

Facts about the stock kernel (from ndoo's analysis of the running phone):

| Fact | Consequence |
|---|---|
| `4.4.205-perf+`, **source not published** by Sonim | No kernel can be built from source for the XP8. Charter: no native port. |
| `CONFIG_BPF_SYSCALL` **off** (no eBPF) | LineageOS has required eBPF since LineageOS 19 (Android 12). 4.4-kernel devices stayed supported only because maintainers backported eBPF into their kernel *source* ([XDA on LineageOS 19](https://www.xda-developers.com/lineageos-19-android-12/)). No source, no backport. |
| No EROFS driver (EROFS needs 5.4+) | Only ext4 system images can mount. |
| No `userfaultfd` | ART uses its fallback garbage collector (works, slower). |
| cgroup v1 memcg only, no PSI | lmkd falls back to older memory-pressure signals. |
| Pre-4.6 ext4 encryption via Qualcomm ICE | File-based encryption v1 only; no metadata encryption. |

Could the kernel be rebuilt without Sonim? In principle: the base is
Qualcomm's msm-4.4 tree (CodeLinaro, formerly CodeAurora), and the XP8's
device trees ship inside its boot image. In practice: Sonim's board drivers
(PTT and programmable keys, panel, touch, charger, camera sensor glue) are not
in that tree, every missing one is found only by trial on hardware, and the
result is still not Sonim's kernel. [SOURCE-PORT.md](SOURCE-PORT.md) lays out
that path, starting with a GPL source request, and
[`tools/kernel-facts.py`](../tools/kernel-facts.py) extracts what a rebuild
needs from your own boot image.

**Conclusion for a native port: blocked until kernel source exists.** Even a
prebuilt-kernel build from the LineageOS tree would not work as-is, because
mainline LineageOS assumes eBPF; it would need the same BPF-less framework
patches that the GSI already carries (section 6).

## 5. Treble and vendor: workable

- Stock Android 10 is **not** Treble-enabled (`ro.treble.enabled=false`,
  VNDK lite, VNDK 29), with legacy system-as-root, A/B slots, no dynamic
  partitions, a 4 GiB `system_a` and a 1 GiB `vendor_a`.
- But the vendor SELinux policy is already split, and the stock device tree
  carries a disabled early-mount node for `vendor`. ndoo's tooling builds a
  real `vendor.img` from the stock `system_a` contents, enables that node in
  the boot image's appended DTB, switches userdata to FBE v1, and adds the
  shims and services an Android 16 system needs from an Android 10 vendor
  (AIDL vibrator, `libxp8shim`, overlays, a fixed `xtra-daemon`).
- With that, ndoo boots TrebleDroid's Android 16 GSI on the XP8, with calls,
  VoLTE, Wi-Fi, mobile data, fingerprint and audio reported working.

This is the foundation the LineageOS route stands on: if TrebleDroid boots,
a TrebleDroid-based LineageOS GSI built for the same constraints should too.

## 6. Choosing a LineageOS GSI that fits these constraints

The candidate is MisterZtr's
[LineageOS 23.2 TrebleDroid GSI](https://github.com/MisterZtr/LineageOS_gsi)
(build of 2026-05-24, Android 16 QPR2). Checked against the XP8, one patch at
a time from its build repository:

| XP8 constraint | What the GSI does | Verdict |
|---|---|---|
| No EROFS in kernel | Ships both EROFS and EXT4 builds | **EXT4 only** |
| Vendor is VNDK 29 | MisterZtr's base patch *replaces* TrebleDroid's `PRODUCT_EXTRA_VNDK_VERSIONS += 28 29` with `30`; the EXT4 targets (`bvN4`, `bgN4`) add `28 29` back. EROFS targets have no VNDK 29 | **EXT4 only**, again |
| 4 GiB `system_a` | GAPPS EXT4 unpacks to 3.2 GB, VANILLA EXT4 to 2.5 GB | Fits |
| No eBPF | TrebleDroid "BPF-less kernel" Connectivity/netd patches, null checks for `sLocalNetBlockedUidMap`, restricted-networking-mode disabled when the BPF map is missing, and a further graceful-fallback patch for firewall/stats maps | Covered in the GSI itself |
| Pre-4.14 kernel | bionic patches tolerating `MADV_WIPEONFORK` and `epoll_pwait2` failures | Covered |
| HIDL fingerprint vs Android 16's virtual AIDL sensor | "Prefer HIDL when AIDL fingerprint sensor is virtual" | Covered |
| XP8 IMS HAL numbering differs from phh's IMS app | Not in the GSI | Added by this repo (ndoo's ImsCafXp8) |
| Android 16 rejects Messaging as SMS app without two permissions | Not in the GSI | Added by this repo (vendor bind mount, ndoo's approach) |
| ndoo's TrebleDroid OTA certificate | Not wanted | Never applied: it would let ndoo's TrebleDroid OTAs overwrite LineageOS |

Two of ndoo's system-side patches (tethering APEX and `AuthService`) target
problems the LineageOS GSI's own source patches appear to address (the
null checks and the HIDL-fingerprint preference above); a phone test will
confirm. They are also written
against Android 16 r1 smali line numbers and would not apply to QPR2 cleanly,
so they are off by default (`--ndoo-system-patches` tries them).

## 7. What you get, and what you give up

Expected to work (verified by ndoo on TrebleDroid with the same boot and
vendor images; **not yet verified on LineageOS**, since no build here has run
on a phone): boot, calls, SMS, VoLTE, Wi-Fi, mobile data, fingerprint,
vibration, speaker audio, storage encryption (FBE v1).

Known limitations, all from the kernel:

- no per-app data usage, data limits or per-app network firewall (no eBPF)
- slower garbage collection (no `userfaultfd`), older memory-pressure handling
- FBE v1 only

Security trade-offs, which you should weigh before flashing:

- **SELinux permissive** (ndoo's boot image sets `androidboot.selinux=permissive`).
  Official LineageOS requires enforcing.
- **Unlocked bootloader with a foreign ABL**; verified boot shows orange.
  Anyone with the phone in hand can reflash it.
- Stock security patch level of the kernel and vendor stays at September 2020.
  LineageOS updates the Android framework, not the kernel or the Qualcomm
  firmware.

Untested here and worth checking on the phone: camera, NFC, the PTT and
programmable keys, FM radio, the magnetic connector, LiveDisplay.

## 8. Decision

| Route | Possible now? | Why |
|---|---|---|
| Official LineageOS device | No | Kernel source unavailable; charter forbids prebuilt non-GKI kernels and requires SELinux enforcing |
| Unofficial native build (LineageOS tree + prebuilt kernel) | Not practical | Same BPF-less patch stack as the GSI, plus a device tree for a legacy-SAR, non-dynamic, header-v0 layout, with no gain over the GSI while the kernel is prebuilt |
| **LineageOS 23.2 GSI + XP8 boot/vendor** | **Yes (this repo)** | Every constraint above is met by an existing, patched component |
| Native port later | If Sonim releases source, or a CodeLinaro rebuild boots | See [SOURCE-PORT.md](SOURCE-PORT.md) |
