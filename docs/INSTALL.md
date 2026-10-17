<!--
SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
SPDX-License-Identifier: Apache-2.0
-->
# Install LineageOS 23.2 on a Sonim XP8 (XP8800)

> [!CAUTION]
> This writes a foreign bootloader over Qualcomm EDL and replaces the OS. A
> mistake can hard-brick the phone, and your IMEI/NV data cannot be recreated
> without your own backup. It wipes all user data. Read
> [FEASIBILITY.md](FEASIBILITY.md#7-what-you-get-and-what-you-give-up) for
> what you give up (SELinux permissive, unlocked bootloader, 2020 kernel and
> vendor patch level). **This build has not yet been run on a phone.**

The unlock, backup, flashing and restore tooling is ndoo's
[sonim-xp8-gsi](https://github.com/ndoo/sonim-xp8-gsi), pinned in
`third_party/sonim-xp8-gsi`. Its [install.md](https://github.com/ndoo/sonim-xp8-gsi/blob/bbaea8ff1c9bd30d667c28015baf3a2d95ab98ed/docs/install.md)
is the authoritative guide for steps 1, 2 and 6; this page says where the
LineageOS route differs.

```
1 Back up ─ 2 Unlock ─ 3 Build (this repo) ─ 4 Assemble (this repo) ─ 5 Flash ─ 6 First boot
```

## Requirements

- An XP8800 on stock Android 10, build `8A.0.0-03-10.0.0-00.40.00`
  (Settings → About phone). ndoo's scripts check for exactly this build.
- A Linux or macOS computer (Windows: use WSL2 for the build steps), with
  `adb`/`fastboot`, Python 3, `zstd`, `xz`, git, and the EDL tool set up as in
  ndoo's [Prerequisites](https://github.com/ndoo/sonim-xp8-gsi/blob/bbaea8ff1c9bd30d667c28015baf3a2d95ab98ed/docs/install.md#prerequisites).
- Docker on macOS (or Linux without e2fsprogs/Java/7-Zip). About 30 GiB free.

```sh
git clone --recurse-submodules https://github.com/rightiswrong/LineageOS-Sonim-XP8-8800
cd LineageOS-Sonim-XP8-8800
```

Every command below runs from this repository's root. Do the setup in
ndoo's [Set up the working directory](https://github.com/ndoo/sonim-xp8-gsi/blob/bbaea8ff1c9bd30d667c28015baf3a2d95ab98ed/docs/install.md#set-up-the-working-directory)
here too, **skipping its `git clone`/`git checkout` lines**: it installs the
`edl` tool into `work/.venv`, the Sonim firehose loader into `work/loaders/`
and the AT&T userdebug ABL into `work/userdebug/`. Our build scripts never
touch those folders (they use only `work/ndoo` and `work/assemble`). Then
set, in every new shell:

```sh
export SERIAL=XXXXXXXX     # first column of 'adb devices'
export EDL=$PWD/work/.venv/bin/edl
export EDL_LOADER=$PWD/work/loaders/prog_emmc_ufs_firehose_Sdm660_ddr.elf
BACKUP=$PWD/backups/stock
```

### On Windows

Use **Git Bash** for every command, never PowerShell or `cmd`, and keep the
checkout in a path without spaces (for example `C:\xp8`). Follow ndoo's
[windows.md](https://github.com/ndoo/sonim-xp8-gsi/blob/bbaea8ff1c9bd30d667c28015baf3a2d95ab98ed/docs/windows.md)
for the tools, the Windows `edl` setup (which replaces the Linux one) and the
one-time Zadig WinUSB driver for EDL. Windows cannot run the build natively,
so steps 3 and 4 need **Docker Desktop** (WSL 2, administrator approval and a
restart):

- step 3: `lineage-gsi/docker-run.sh -- lineage-gsi/build.sh ...`
- step 4: `lineage-gsi/assemble.sh --docker "$BACKUP"` (run on the host; it
  starts its own container)

## 1. Back up (ndoo, unchanged)

```sh
third_party/sonim-xp8-gsi/scripts/dump-stock.sh "$BACKUP"
```

Copy the backup somewhere offline. It holds your IMEI/NV partitions.

## 2. Unlock (ndoo, unchanged)

```sh
third_party/sonim-xp8-gsi/scripts/unlock.sh --abl work/userdebug/abl.elf "$BACKUP"
```

If you already run ndoo's TrebleDroid GSI, you are unlocked; skip to step 3.

## 3. Build the LineageOS system image (this repo)

```sh
lineage-gsi/build.sh --variant gapps          # Linux
lineage-gsi/docker-run.sh -- lineage-gsi/build.sh --variant gapps   # macOS / any
```

`--variant vanilla` gives LineageOS without Google apps. The script fetches
ndoo's pinned build inputs, downloads the **EXT4** LineageOS 23.2 GSI,
checks it can work on the XP8 (ext4, fits 4 GiB, contains VNDK 29 and the
SELinux 29.0 mapping), adds the XP8 IMS app, and writes `out/system.img`,
`out/SHA256SUMS` and `out/components/`.

SourceForge sometimes answers scripts with a web page. Then download the
archive named in [`lineage-gsi/inputs.lock`](../lineage-gsi/inputs.lock) in
a browser and pass it in:

```sh
lineage-gsi/build.sh --variant gapps --local ~/Downloads/LineageOS-23.2-20260524-GAPPS-EXT4-GSI.7z
# Docker:
lineage-gsi/docker-run.sh --file ~/Downloads/LineageOS-23.2-20260524-GAPPS-EXT4-GSI.7z \
  -- lineage-gsi/build.sh --local /input/LineageOS-23.2-20260524-GAPPS-EXT4-GSI.7z
```

The first fetch records the archive's SHA-256 in `lineage-gsi/inputs.lock`.
Commit that change so later builds are checked against it.

Read the warnings the build prints. `ims: skipped` means VoLTE will not work;
`messaging: skipped` means Messaging may not be accepted as the SMS app.

## 4. Assemble boot and vendor from your backup (this repo)

```sh
lineage-gsi/assemble.sh "$BACKUP"                 # add --magisk for root
lineage-gsi/assemble.sh --docker "$BACKUP"                 # Windows and macOS
```

This runs ndoo's `assemble.sh` with a vendor recipe matched to the LineageOS
system image. `out/boot.img` and `out/vendor.img` contain Sonim and Qualcomm
files from your phone: do not share them.

## 5. Flash (ndoo, unchanged)

On the host, not in Docker. Phone in fastboot (power off, hold Vol- and
press Power):

```sh
third_party/sonim-xp8-gsi/scripts/flash.sh --dir out --wipe
```

`--wipe` is required the first time, including when coming from ndoo's
TrebleDroid GSI (different system image and keys).

## 6. First boot

The first boot formats and encrypts `/data` and can take several minutes;
one early reboot with reason `dm-verity enforcing` is expected (ndoo's
[First boot](https://github.com/ndoo/sonim-xp8-gsi/blob/bbaea8ff1c9bd30d667c28015baf3a2d95ab98ed/docs/install.md#7-first-boot-and-verify)).
Then:

```sh
third_party/sonim-xp8-gsi/scripts/verify-device.sh
```

Please report what works and what does not (camera, NFC, PTT and
programmable keys, FM radio, VoLTE) as an issue on this repository.

## Updating LineageOS later

Point `lineage-gsi/inputs.lock` at a newer **EXT4** release, rebuild (step 3),
re-assemble (step 4), and flash without wiping:

```sh
third_party/sonim-xp8-gsi/scripts/flash.sh --dir out
```

Do **not** use ndoo's `scripts/ota-update.sh`: it installs ndoo's TrebleDroid
builds, not LineageOS.

## Back to stock

ndoo's [restore.md](https://github.com/ndoo/sonim-xp8-gsi/blob/bbaea8ff1c9bd30d667c28015baf3a2d95ab98ed/docs/restore.md) restores
Android 10 from your backup and can relock the bootloader.
