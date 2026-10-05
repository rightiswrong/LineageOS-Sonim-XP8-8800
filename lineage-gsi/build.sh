#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build everything that does not need your phone: out/system.img (LineageOS
# 23.2 for the XP8) and out/components (ndoo's vibrator, shim and overlays).
# Then run lineage-gsi/assemble.sh with your stock backup for boot and vendor.
#
# usage: lineage-gsi/build.sh [--variant gapps|vanilla] [--local FILE] [build-system.sh options]
#   --local FILE   the LineageOS GSI archive you downloaded yourself
#   other options go to lineage-gsi/build-system.sh (--gms-queryable, ...)
#
# Runs natively on Linux, or anywhere through lineage-gsi/docker-run.sh.
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
usage() { sed -n '5,13s/^# \{0,1\}//p' "$0" >&2; exit 2; }

VARIANT=gapps LOCAL=() PASS=()
while [ $# -gt 0 ]; do
    case $1 in
        --variant) VARIANT=$2; shift 2 ;;
        --local) LOCAL=(--local "$2"); shift 2 ;;
        -h|--help) usage ;;
        *) PASS+=("$1"); shift ;;
    esac
done
valid_variant "$VARIANT"
check_ndoo
[ "$(uname -s)" = Linux ] || die "run on Linux, or through lineage-gsi/docker-run.sh"

say "1/4 ndoo inputs (SDK build-tools, NDK, apktool/smali, AOSP test keys, phh IMS)"
"$NDOO/build/fetch.sh" sdk/ tools/ keys/ ims/
say "2/4 LineageOS GSI ($VARIANT)"
"$LGSI/fetch-lineage.sh" --variant "$VARIANT" "${LOCAL[@]}"
say "3/4 components (ndoo build-components.sh)"
ROOT=$NDOO "$NDOO/build/build-components.sh"
say "4/4 system image"
"$LGSI/build-system.sh" --variant "$VARIANT" "${PASS[@]}"

cat <<EOF
$PROG: done: $OUT/system.img and $OUT/components
Next, with your stock EDL backup (see docs/INSTALL.md):
  lineage-gsi/assemble.sh /path/to/backup
  third_party/sonim-xp8-gsi/scripts/flash.sh --dir out --wipe
EOF
