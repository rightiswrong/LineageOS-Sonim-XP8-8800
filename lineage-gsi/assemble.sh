#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build out/boot.img and out/vendor.img from YOUR stock EDL backup, to go with
# the LineageOS out/system.img. Wraps ndoo's scripts/assemble.sh (run from the
# work/ndoo copy that lineage-gsi/prepare-vendor.sh made).
#
# usage: lineage-gsi/assemble.sh [--magisk] [--keep-work] STOCK_DIR
#   STOCK_DIR   the backup from third_party/sonim-xp8-gsi/scripts/dump-stock.sh
#               (needs boot_a.bin[.zst] and system_a.bin[.zst]; read only)
#   --magisk    root boot.img with Magisk (off by default)
#
# The images contain your phone's proprietary files. Do not publish them.
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
usage() { sed -n '5,15s/^# \{0,1\}//p' "$0" >&2; exit 2; }

args=() STOCK=
while [ $# -gt 0 ]; do
    case $1 in
        --magisk|--keep-work) args+=("$1"); shift ;;
        -h|--help) usage ;;
        -*) die "unknown option $1" ;;
        *) [ -z "$STOCK" ] || usage; STOCK=$1; shift ;;
    esac
done
[ -n "$STOCK" ] || usage
[ -f "$OUT/system.img" ] || die "no $OUT/system.img: run lineage-gsi/build.sh first"
[ -d "$OUT/components" ] || die "no $OUT/components: run lineage-gsi/build.sh first"

"$LGSI/prepare-vendor.sh"
exec "$WORK/ndoo/scripts/assemble.sh" --components "$OUT/components" --out "$OUT" \
    --work "$WORK/assemble" "${args[@]}" "$STOCK"
