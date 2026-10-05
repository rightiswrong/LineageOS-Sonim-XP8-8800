# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared paths and helpers for lineage-gsi/*.sh. Source it; defines only.

REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
LGSI=$REPO/lineage-gsi
# ndoo/sonim-xp8-gsi, pinned as a submodule: unlock, boot and vendor tooling.
NDOO=$REPO/third_party/sonim-xp8-gsi
NDOO_COMMIT=bbaea8ff1c9bd30d667c28015baf3a2d95ab98ed

# One cache/work/out for both projects, so ndoo's scripts and ours share
# downloads and outputs. ndoo's build/lib/tools.sh honours these variables.
export CACHE=${CACHE:-$REPO/cache}
export WORK=${WORK:-$REPO/work}
export OUT=${OUT:-$REPO/out}

PROG=${PROG:-$(basename "$0" .sh)}

die() { echo "$PROG: $*" >&2; exit 1; }
say() { echo "$PROG: $*"; }
warn() { echo "$PROG: warning: $*" >&2; }

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

need_tools() {
    local t
    for t in "$@"; do command -v "$t" >/dev/null || die "missing tool: $t"; done
}

# 7-Zip ships under several names depending on the distribution.
find_7z() {
    local t
    for t in 7z 7zz 7za; do
        command -v "$t" >/dev/null && { echo "$t"; return 0; }
    done
    die "missing tool: 7z (install 7zip / p7zip-full, or use lineage-gsi/docker-run.sh)"
}

check_ndoo() {
    [ -f "$NDOO/build/build-system.sh" ] ||
        die "third_party/sonim-xp8-gsi is empty: run git submodule update --init"
    local head
    head=$(git -C "$NDOO" rev-parse HEAD 2>/dev/null || echo unknown)
    [ "$head" = "$NDOO_COMMIT" ] ||
        warn "third_party/sonim-xp8-gsi is at $head, these scripts were written against $NDOO_COMMIT"
}

valid_variant() {
    case $1 in gapps|vanilla) ;; *) die "variant must be gapps or vanilla, not '$1'" ;; esac
}
