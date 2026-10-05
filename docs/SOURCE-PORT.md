<!--
SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
SPDX-License-Identifier: Apache-2.0
-->
# Toward a native LineageOS port

A native port (a `device/sonim/xp8800` tree built inside LineageOS, and
eventually an official device) needs one thing that does not exist yet: a
kernel built from source. [FEASIBILITY.md](FEASIBILITY.md#4-kernel-the-blocker-for-a-native-port)
explains why. This page is the plan for getting there, in order of effort.

## Step 0: collect the facts from your own phone

```sh
tools/kernel-facts.py "$BACKUP/boot_a.bin.zst" --out work/kernel-facts
# if the kernel has no embedded config, from a running phone:
adb shell zcat /proc/config.gz > work/xp8.config
tools/kernel-facts.py "$BACKUP/boot_a.bin.zst" --config work/xp8.config
```

It prints the exact kernel version string, boot header layout and command
line, splits the appended device trees (with their `qcom,msm-id` and
`qcom,board-id`), and marks the options LineageOS cares about
(`CONFIG_BPF_SYSCALL`, `CONFIG_CGROUP_BPF`, `CONFIG_USERFAULTFD`, `CONFIG_PSI`,
`CONFIG_EROFS_FS`, encryption). Keep `work/kernel-facts/`: the DTBs and
config are the starting point for steps 2 and 3. Do not publish `Image`.

## Step 1: ask Sonim for the source (cheapest, decisive)

The XP8 ships a GPLv2 Linux kernel in binary form, which obliges the
distributor to provide the corresponding source on request. Ask Sonim's
support or legal contact in writing for the complete kernel source of the
XP8800 build `8A.0.0-03-10.0.0-00.40.00` (kernel `4.4.205-perf+`, the
version string from step 0), including the defconfig and device-tree sources.
Several requests over time strengthen the case; publish the reply.

With source in hand, the port becomes ordinary work:

1. Build the kernel unchanged and boot it with the GSI from this repo to
   prove the toolchain.
2. Backport eBPF the way other 4.4 LineageOS kernels did (the cgroup-BPF and
   `BPF_PROG_TYPE_CGROUP_SKB` series), enable `CONFIG_BPF_SYSCALL` and
   `CONFIG_CGROUP_BPF`; optionally backport `userfaultfd` and PSI.
3. Write `device/sonim/xp8800` against the facts in FEASIBILITY.md (A/B,
   legacy system-as-root, no dynamic partitions, boot header v0 with
   appended DTB, VNDK 29 vendor), reusing ndoo's vendor findings (fstab,
   shim, vibrator, IMS numbering) as device-tree code instead of image
   patches.
4. Extract blobs with LineageOS's extract-utils from the stock Android 10
   image, with the source of every blob noted as the charter requires.
5. Get SELinux to enforcing; it is permissive today.

## Step 2: no source, rebuild from CodeLinaro (hard, uncertain)

The XP8 kernel is Qualcomm's msm-4.4 for `sdm660` plus Sonim changes. The
Qualcomm part is public on CodeLinaro (the former CodeAurora). A rebuild:

1. Pick the CodeLinaro msm-4.4 tag from the sdm660 Android 10 release line
   (the `LA.UM.8.2.r1-*` series, to be confirmed against CodeLinaro's tag
   list) whose sublevel is closest to 4.4.205, and merge stable up to `.205`.
2. Use the extracted config from step 0 as the defconfig, the extracted DTBs
   as the device tree (decompile with `dtc -I dtb -O dts`; Qualcomm DT
   bindings in that tree should mostly match).
3. Boot it with fastboot (`fastboot boot` stalls on this ABL for large
   images, per genesisXP8; write to `boot_b` with ndoo's slot-B tooling
   instead), and find what is missing. Expect missing drivers for Sonim
   specific hardware: PTT/programmable keys, panel or touch variants,
   charger and battery glue, camera sensor bits. Each one is a
   reverse-engineering task.

This yields a kernel you can build, but not Sonim's kernel: hardware that
works on stock may not work, and it would still need maintainers willing to
own it before it could be considered for official status.

## Step 3: mainline (research project)

SDM630 has upstream Linux support (Sony's Xperia XA2 *pioneer* was among
the first SDM630 boards upstreamed). A mainline kernel with an XP8 device tree would bring modern
eBPF, EROFS and PSI for free, but needs every peripheral driver upstream or
ported, and the Android 10 vendor blobs expect the downstream kernel's
interfaces (GPU, camera, audio, modem). Realistic only as a long-term
community effort.

## What does not help

- A prebuilt-kernel `device/sonim/xp8800` tree today. It gains nothing over
  the GSI (same kernel, same BPF-less patch stack needed), and the LineageOS
  charter forbids prebuilt kernels on non-GKI devices.
- Kernel source from other SDM630 phones. Same SoC, different board: panel,
  touch, PMIC configuration, keys and camera differ.
