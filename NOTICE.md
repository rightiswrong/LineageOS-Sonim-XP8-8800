<!--
SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
SPDX-License-Identifier: Apache-2.0
-->
# Notices

This repository's own files are licensed under Apache-2.0 ([LICENSE](LICENSE)).

It contains no Sonim, Qualcomm or Google binaries. The build downloads or
derives these at build time, each under its own terms:

| Component | Where it comes from | License |
|---|---|---|
| `third_party/sonim-xp8-gsi` (submodule) | [ndoo/sonim-xp8-gsi](https://github.com/ndoo/sonim-xp8-gsi) | MIT, with Apache-2.0 / BSD-3-Clause parts (see its `NOTICE.md`) |
| LineageOS 23.2 GSI | [MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi) builds of LineageOS and TrebleDroid | Apache-2.0 and others (AOSP/LineageOS); GAPPS variant includes Google apps under Google's terms |
| phh IMS app, SDK tools, AOSP test keys, apktool, smali | pinned in `third_party/sonim-xp8-gsi/build/inputs.lock` | their respective licenses |
| Your `boot.img` and `vendor.img` | built from **your own** phone's stock firmware | Sonim / Qualcomm proprietary: do not redistribute |
