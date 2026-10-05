#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Make work/ndoo: a copy of third_party/sonim-xp8-gsi whose vendor recipe
# matches the system image built by lineage-gsi/build-system.sh.
#
# usage: lineage-gsi/prepare-vendor.sh
#
# ndoo's vendor.img carries a patched Messaging and bind-mounts it over
# /system/product/app/messaging. When build-system.sh could not build that
# component (no Messaging in the GSI, or no oat files for it), the matching
# lines are dropped from the copy's vendor/fs_config.tsv and vendor/xp8-gsi.rc.
# Everything else in ndoo's vendor recipe (fstab with FBE, AIDL vibrator,
# libxp8shim, overlays, props, xtra-daemon fix) does not depend on the system
# image and is used unchanged. The submodule itself is never modified.
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
[ $# -eq 0 ] || { sed -n '5,17s/^# \{0,1\}//p' "$0" >&2; exit 2; }
check_ndoo

DST=$WORK/ndoo
C=$OUT/components/messaging
rm -rf "$DST"
mkdir -p "$DST"
# Tracked files only: no .git, no cache/work/out of a standalone ndoo checkout.
git -C "$NDOO" ls-files -z | (cd "$NDOO" && tar --null -T - -cf -) | tar -C "$DST" -xf -

fsc=$DST/vendor/fs_config.tsv
rc=$DST/vendor/xp8-gsi.rc
grep -q '^etc/xp8/messaging' "$fsc" || die "$fsc has no Messaging entries: ndoo layout changed"
grep -q 'mount none /vendor/etc/xp8/messaging ' "$rc" || die "$rc has no Messaging bind mount: ndoo layout changed"

if [ ! -f "$C/messaging.apk" ]; then
    say "no Messaging component: vendor.img will not override the GSI's Messaging"
    sed -i '/^etc\/xp8\/messaging/d' "$fsc"
    sed -i '/mount none \/vendor\/etc\/xp8\/messaging /d' "$rc"
elif [ ! -f "$C/oat/arm64/messaging.odex" ]; then
    say "Messaging component without oat files: dropping them from the vendor recipe"
    sed -i '/^etc\/xp8\/messaging\/oat/d' "$fsc"
else
    say "Messaging component with oat files: ndoo's vendor recipe unchanged"
fi
say "ready: $DST"
