#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build out/system.img for the Sonim XP8 from the LineageOS 23.2 EXT4 GSI.
#
# usage: lineage-gsi/build-system.sh [options]
#   --variant V            gapps (default) or vanilla
#   --gsi FILE             use this system image instead of cache/lineage/V.img
#   --gms-queryable        gapps only: add ndoo's RRO listing Play services in
#                          config_forceQueryablePackages (try it if Google apps
#                          cannot see Play services)
#   --ndoo-system-patches  also try ndoo's tethering-APEX and AuthService smali
#                          patches (written for TrebleDroid android-16.0.0_r1;
#                          the LineageOS GSI carries its own fixes for both)
#   --stages LIST          comma-separated subset, for reruns on work/system:
#                          base,ims,gmsquery,messaging,ndoo-patches,final
#
# What changes compared with the downloaded GSI:
#   ims        ImsCafXp8: phh's CAF IMS app with the XP8 HAL's transaction
#              numbering (ndoo's stage, unchanged). Needed for VoLTE.
#   messaging  out/components/messaging: Messaging with the two permissions
#              Android 16 wants from an SMS app. Goes into vendor.img, which
#              bind-mounts it over the system copy (no change to system.img).
# Never applied: ndoo's otacerts stage. It would make update_engine accept
# ndoo's TrebleDroid OTAs, which would replace LineageOS.
#
# Needs: third_party/sonim-xp8-gsi/build/fetch.sh sdk/ tools/ keys/ ims/
#        lineage-gsi/fetch-lineage.sh (or --gsi)
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
usage() { sed -n '5,25s/^# \{0,1\}//p' "$0" >&2; exit 2; }

VARIANT=gapps GSI='' GMSQ=0 NDOOP=0 STAGES=''
while [ $# -gt 0 ]; do
    case $1 in
        --variant) VARIANT=$2; shift 2 ;;
        --gsi) GSI=$2; shift 2 ;;
        --gms-queryable) GMSQ=1; shift ;;
        --ndoo-system-patches) NDOOP=1; shift ;;
        --stages) STAGES=$2; shift 2 ;;
        -h|--help) usage ;;
        *) die "unknown argument $1" ;;
    esac
done
valid_variant "$VARIANT"
[ $GMSQ = 0 ] || [ "$VARIANT" = gapps ] || die "--gms-queryable is for the gapps variant"
check_ndoo
need_tools python3 debugfs e2fsck resize2fs openssl unzip java

# --- ndoo's stage library ------------------------------------------------------
# Everything in ndoo's build-system.sh above its stage runner: tool setup and
# the debugfs helpers (q_put, q_commit, dump...) plus stage_ims, stage_gmsquery,
# stage_apexfix and stage_services. Both anchors must match exactly, so a
# different submodule revision fails here rather than half-working.
export ROOT=$NDOO
lib=$NDOO/build/build-system.sh
# shellcheck disable=SC2016  # literal line to match, not to expand
anchor_tools='. "$(dirname "$0")/lib/tools.sh"'
anchor_all='all=(base gapps gmsquery apexfix ims launcher3 services messaging otacerts final)'
if ! grep -qxF "$anchor_tools" "$lib" || ! grep -qxF "$anchor_all" "$lib"; then
    die "$lib changed shape (anchors not found); check the submodule revision"
fi
# shellcheck disable=SC1090
. <(awk -v t="$anchor_tools" -v a="$anchor_all" '
    $0 == a { exit }
    $0 == t { print ". \"$ROOT/build/lib/tools.sh\""; next }
    { print }' "$lib")
# From here: W=$WORK/system, IMG=$W/system.img, SIZE=4G, and ndoo's helpers.

CHECK=$W/check.json
jget() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print("" if v in (None, False, []) else v)' "$CHECK" "$1"; }

# Apps that need the platform signature (ImsCafXp8, Messaging) are signed with
# the AOSP test key, so the GSI must be signed with it too.
PLATFORM_OK=''
platform_ok() {
    if [ -z "$PLATFORM_OK" ]; then
        local got want
        dump /system/framework/framework-res.apk "$W/framework-res.apk" ||
            die "no framework-res.apk in the image"
        got=$("${APKSIGNER[@]}" verify --print-certs "$W/framework-res.apk" 2>/dev/null |
            awk -F': ' '/^Signer #1 certificate SHA-256 digest/ { print $2; exit }')
        want=$(openssl x509 -in "$KEYS/platform.x509.pem" -outform der | sha256sum | cut -d' ' -f1)
        rm -f "$W/framework-res.apk"
        if [ "$got" = "$want" ]; then PLATFORM_OK=1; else
            PLATFORM_OK=0
            warn "the GSI's platform certificate (${got:-unreadable}) is not the AOSP test key"
        fi
    fi
    [ "$PLATFORM_OK" = 1 ]
}

APPLIED=()

# Runs a stage in a subshell with errexit active, returning its status.
# (In an if/&&/|| context bash would silently disable errexit inside it.)
try_stage() {
    local rc
    set +e
    ( set -e; "$@" )
    rc=$?
    set -e
    return $rc
}

stage_base() {
    local src=${GSI:-$CACHE/lineage/$VARIANT.img}
    [ -f "$src" ] || die "no $src: run lineage-gsi/fetch-lineage.sh --variant $VARIANT"
    log "base: $(basename "$src") grown to $SIZE"
    rm -f "$IMG"
    if [ "$(head -c 4 "$src" | od -An -tx4 | tr -d ' ')" = ed26ff3a ]; then
        need_tools simg2img
        simg2img "$src" "$IMG"
    else
        cp --sparse=always "$src" "$IMG"
    fi
    python3 "$LGSI/lib/check_gsi.py" "$IMG" --json "$CHECK" ||
        die "this image cannot boot on the XP8 (errors above)"
    truncate -s "$SIZE" "$IMG"
    resize2fs "$IMG" >/dev/null 2>&1
    # Shared (deduplicated) blocks must be unshared before debugfs writes.
    e2fsck -fy -E unshare_blocks "$IMG" >/dev/null 2>&1 || [ $? -le 1 ] ||
        die "e2fsck could not unshare blocks: not enough room in $SIZE?"
    e2fsck -fn "$IMG" >/dev/null 2>&1 || die "e2fsck reports errors in the grown image"
    APPLIED+=(base)
}

stage_ims_lineage() {
    if [ -n "$(jget bundled_ims)" ]; then
        warn "ims: the GSI already has an IMS app ($(jget bundled_ims)); not adding ImsCafXp8"
        return
    fi
    if exists /system/system_ext/priv-app/ImsCafXp8; then
        log "ims: ImsCafXp8 already present"; return
    fi
    if ! platform_ok; then
        warn "ims: skipped (needs a test-key GSI); VoLTE will not work"; return
    fi
    if try_stage stage_ims; then APPLIED+=(ims)
    else warn "ims: stage failed; image unchanged by it, VoLTE will not work"; fi
}

stage_gmsquery_lineage() {
    [ $GMSQ = 1 ] || return 0
    stage_gmsquery
    APPLIED+=(gmsquery)
}

stage_messaging_lineage() {
    local m=$W/messaging d=/system/product/app/messaging c=$OUT/components/messaging
    rm -rf "$m" "$c"
    if [ -z "$(jget messaging_apk)" ]; then
        warn "messaging: no $d/messaging.apk in the GSI; vendor.img will not override it"; return
    fi
    if ! platform_ok; then
        warn "messaging: skipped (needs a test-key GSI); it may not be selectable as SMS app"; return
    fi
    log "messaging: RECEIVE_WAP_PUSH/READ_CELL_BROADCASTS (out/components/messaging)"
    build_messaging() {
        mkdir -p "$m/m" "$c"
        dump "$d/messaging.apk" "$m/orig.apk"
        "${APKTOOL[@]}" d -s -f -o "$m/dec" "$m/orig.apk" >/dev/null
        python3 "$LGSI/lib/messaging_manifest.py" "$m/dec"
        "${APKTOOL[@]}" b -o "$m/rebuilt.apk" "$m/dec" >/dev/null
        unzip -q -d "$m/m" "$m/rebuilt.apk" AndroidManifest.xml
        python3 "$ROOT/build/lib/zipreplace.py" "$m/orig.apk" "$m/u.apk" --drop-v1-sig \
            AndroidManifest.xml="$m/m/AndroidManifest.xml"
        "$ZIPALIGN" -f -p 4 "$m/u.apk" "$m/a.apk"
        sign_apk platform "$m/a.apk" "$c/messaging.apk"
        # classes.dex is untouched, so the GSI's own oat files still match.
        if [ -n "$(jget messaging_oat)" ]; then
            mkdir -p "$c/oat/arm64"
            dump "$d/oat/arm64/messaging.odex" "$c/oat/arm64/messaging.odex"
            dump "$d/oat/arm64/messaging.vdex" "$c/oat/arm64/messaging.vdex"
        fi
    }
    if try_stage build_messaging; then APPLIED+=(messaging)
    else rm -rf "$c"; warn "messaging: failed; vendor.img will not override Messaging"; fi
    rm -rf "$m"
}

stage_ndoo_patches() {
    [ $NDOOP = 1 ] || return 0
    local s
    for s in apexfix services; do
        if try_stage "stage_$s"; then APPLIED+=("$s")
        else warn "$s: ndoo's patch does not apply to this GSI; skipped (image unchanged by it)"; fi
    done
}

stage_final() {
    log "final: fsck and out/system.img"
    e2fsck -fn "$IMG" >/dev/null 2>&1
    mv "$IMG" "$OUT/system.img"
    python3 - "$CHECK" "$OUT/lineage-gsi.json" "$VARIANT" "${APPLIED[@]}" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
r.update(variant=sys.argv[3], stages=sys.argv[4:])
json.dump(r, open(sys.argv[2], 'w'), indent=1, sort_keys=True)
PY
    # flash.sh checks system.img against out/SHA256SUMS before writing it.
    (cd "$OUT" && sha256sum system.img | tee SHA256SUMS)
}

all=(base ims gmsquery messaging ndoo-patches final)
if [ -n "$STAGES" ]; then IFS=, read -r -a stages <<< "$STAGES"; else stages=("${all[@]}"); fi
for s in "${stages[@]}"; do
    [[ " ${all[*]} " == *" $s "* ]] || die "unknown stage: $s"
    [ "$s" = base ] || [ -f "$IMG" ] || die "no $IMG: run the base stage first"
    [ "$s" = base ] || [ -f "$CHECK" ] || die "no $CHECK: run the base stage first"
    start=$SECONDS
    case $s in
        base) stage_base ;;
        ims) stage_ims_lineage ;;
        gmsquery) stage_gmsquery_lineage ;;
        messaging) stage_messaging_lineage ;;
        ndoo-patches) stage_ndoo_patches ;;
        final) stage_final ;;
    esac
    echo "   ($s: $((SECONDS - start)) s)"
done
rm -rf "$CTX" "$CMDS"
say "applied: ${APPLIED[*]:-nothing}"
