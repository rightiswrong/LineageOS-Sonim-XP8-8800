#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Offline tests for lineage-gsi/: synthetic system images and a stub SDK
# cache, no downloads, no phone. Checks the parts that decide whether an
# image is flashed at all, and the glue around ndoo's scripts.
#
# usage: tests/test-pipeline.sh     (needs e2fsprogs, python3, openssl, xz, git)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export CACHE=$T/cache WORK=$T/work OUT=$T/out
pass=0
ok() { echo "ok   $*"; pass=$((pass + 1)); }
fail() { echo "FAIL $*" >&2; exit 1; }

# --- synthetic GSIs ----------------------------------------------------------
mkimg() { # name: populate $T/root/<name> first
    mke2fs -q -t ext4 -b 4096 -d "$T/root/$1" "$T/$1.img" 64M
}
tree() { # name vndk... : a system-as-root GSI layout
    local r=$T/root/$1 v; shift
    mkdir -p "$r/system/system_ext/apex" "$r/system/system_ext/etc/selinux/mapping" \
        "$r/system/product/app/messaging" "$r/system/apex" "$r/system/framework"
    cat > "$r/system/build.prop" <<'EOF'
ro.system.build.version.release=16
ro.system.build.version.sdk=36
ro.system.build.tags=test-keys
ro.system.build.type=userdebug
ro.lineage.version=23.2-20260524-UNOFFICIAL
ro.lineage.display.version=23.2-20260524-UNOFFICIAL-EXT4
EOF
    for v; do
        : > "$r/system/system_ext/apex/com.android.vndk.v$v.apex"
        : > "$r/system/system_ext/etc/selinux/mapping/$v.0.cil"
    done
    echo apk > "$r/system/product/app/messaging/messaging.apk"
    echo apex > "$r/system/apex/com.android.tethering.capex"
    echo res > "$r/system/framework/framework-res.apk"
}

tree good 29 30 && mkimg good
tree novndk29 30 && mkimg novndk29
cp "$T/good.img" "$T/erofs.img"
printf '\xe2\xe1\xf5\xe0' | dd of="$T/erofs.img" bs=1 seek=1024 conv=notrunc status=none
cp "$T/good.img" "$T/sparse.img"
printf '\x3a\xff\x26\xed' | dd of="$T/sparse.img" bs=1 seek=0 conv=notrunc status=none

# --- check_gsi.py ------------------------------------------------------------
chk=$REPO/lineage-gsi/lib/check_gsi.py
python3 "$chk" "$T/good.img" --json "$T/good.json" >/dev/null 2>&1 || fail "good image rejected"
python3 - "$T/good.json" <<'PY' || fail "good image report"
import json, sys
r = json.load(open(sys.argv[1]))
assert r['fs'] == 'ext4' and r['vndk'] == [29, 30] and r['mapping_29'], r
assert r['messaging_apk'] and not r['messaging_oat'], r
assert r['tethering'] == 'com.android.tethering.capex', r
assert r['props']['ro.system.build.tags'] == 'test-keys', r
PY
ok "check_gsi accepts an EXT4 image with VNDK 29 and reports its contents"
for bad in novndk29:'no VNDK 29' erofs:'EROFS image' sparse:'sparse image'; do
    n=${bad%%:*} want=${bad#*:}
    if out=$(python3 "$chk" "$T/$n.img" 2>&1); then fail "$n image accepted"; fi
    grep -q "$want" <<< "$out" || fail "$n: expected '$want' in: $out"
    ok "check_gsi rejects the $n image ($want)"
done
truncate -s 5G "$T/big.img" && cp "$T/good.img" "$T/big.tmp" && dd if="$T/big.tmp" of="$T/big.img" conv=notrunc status=none
out=$(python3 "$chk" "$T/big.img" 2>&1) && fail "oversized image accepted"
grep -q 'system_a holds' <<< "$out" && ok "check_gsi rejects an image larger than system_a"

# --- stub SDK cache (only what ndoo's tools.sh checks for) ---------------------
mkdir -p "$T/stub/android-16/lib" "$T/stub/android-36" "$CACHE/sdk" "$CACHE/tools" "$CACHE/keys"
for t in aapt2 zipalign; do printf '#!/bin/sh\nexit 0\n' > "$T/stub/android-16/$t"; chmod +x "$T/stub/android-16/$t"; done
: > "$T/stub/android-16/lib/apksigner.jar"
: > "$T/stub/android-36/android.jar"
(cd "$T/stub" && zip -qr "$CACHE/sdk/build-tools_r36_linux.zip" android-16 && zip -qr "$CACHE/sdk/platform-36_r02.zip" android-36)
for j in apktool.jar apktool_2.10.0.jar smali.jar baksmali.jar avbtool.py; do : > "$CACHE/tools/$j"; done
openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=t -days 1 -keyout "$CACHE/keys/platform.pem" \
    -out "$CACHE/keys/platform.x509.pem" 2>/dev/null

# --- build-system.sh end to end on the good image ------------------------------
# The stub apksigner cannot read a certificate, so the platform-key check must
# fail closed: IMS and Messaging skipped with warnings, image still produced.
log=$T/build.log
"$REPO/lineage-gsi/build-system.sh" --gsi "$T/good.img" > "$log" 2>&1 || { cat "$log"; fail "build-system.sh"; }
[ -f "$OUT/system.img" ] || fail "no out/system.img"
[ "$(stat -c %s "$OUT/system.img")" = $((4 * 1024 ** 3)) ] || fail "system.img is not 4 GiB"
e2fsck -fn "$OUT/system.img" >/dev/null 2>&1 || fail "system.img fails fsck"
(cd "$OUT" && sha256sum -c --quiet SHA256SUMS) || fail "out/SHA256SUMS does not verify system.img"
debugfs -R 'cat /system/build.prop' "$OUT/system.img" 2>/dev/null | grep -q lineage || fail "content lost"
if ! grep -q 'ims: skipped' "$log" || ! grep -q 'messaging: skipped' "$log"; then cat "$log"; fail "platform check"; fi
[ ! -e "$OUT/components/messaging" ] || fail "messaging component built without platform key"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["stages"]==["base"] and r["variant"]=="gapps", r' \
    "$OUT/lineage-gsi.json" || fail "lineage-gsi.json"
ok "build-system.sh: grows to 4 GiB, keeps content, fails closed on an unknown platform key"
! grep -q 'otacerts' "$log" || fail "otacerts ran"
ok "build-system.sh never runs ndoo's otacerts stage"

if "$REPO/lineage-gsi/build-system.sh" --gsi "$T/erofs.img" > "$log" 2>&1; then fail "erofs built"; fi
grep -q 'cannot boot on the XP8' "$log" || { cat "$log"; fail "erofs message"; }
ok "build-system.sh refuses an EROFS image"

# --- prepare-vendor.sh ---------------------------------------------------------
"$REPO/lineage-gsi/prepare-vendor.sh" >/dev/null
fsc=$WORK/ndoo/vendor/fs_config.tsv rc=$WORK/ndoo/vendor/xp8-gsi.rc
if grep -q '^etc/xp8/messaging' "$fsc" || grep -q '/vendor/etc/xp8/messaging ' "$rc"; then fail "messaging not dropped"; fi
grep -q '^etc/xp8/xp8-vibrator' "$fsc" || fail "other vendor entries lost"
git -C "$REPO/third_party/sonim-xp8-gsi" diff --quiet || fail "submodule modified"
ok "prepare-vendor.sh drops Messaging when it was not built, leaves the submodule clean"
mkdir -p "$OUT/components/messaging" && : > "$OUT/components/messaging/messaging.apk"
"$REPO/lineage-gsi/prepare-vendor.sh" >/dev/null
if ! grep -q '^etc/xp8/messaging/messaging.apk' "$fsc" || grep -q '^etc/xp8/messaging/oat' "$fsc"; then fail "oat drop"; fi
ok "prepare-vendor.sh keeps Messaging but drops missing oat files"
mkdir -p "$OUT/components/messaging/oat/arm64" && : > "$OUT/components/messaging/oat/arm64/messaging.odex"
"$REPO/lineage-gsi/prepare-vendor.sh" >/dev/null
diff -q "$fsc" "$REPO/third_party/sonim-xp8-gsi/vendor/fs_config.tsv" >/dev/null || fail "recipe changed"
ok "prepare-vendor.sh leaves ndoo's recipe unchanged when Messaging is complete"

# --- messaging_manifest.py -----------------------------------------------------
d=$T/dec && mkdir -p "$d"
cat > "$d/apktool.yml" <<'EOF'
version: 2.9.3
sdkInfo:
  minSdkVersion: '36'
  targetSdkVersion: '24'
packageInfo:
  forcedPackageId: '127'
EOF
cat > "$d/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8" standalone="no"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.android.messaging">
    <uses-permission android:name="android.permission.READ_CELL_BROADCASTS"/>
    <uses-permission android:name="android.permission.READ_SMS"/>
</manifest>
EOF
python3 "$REPO/lineage-gsi/lib/messaging_manifest.py" "$d" >/dev/null
grep -q 'targetSdkVersion="24"' "$d/AndroidManifest.xml" || fail "uses-sdk"
[ "$(grep -c RECEIVE_WAP_PUSH "$d/AndroidManifest.xml")" = 1 ] || fail "WAP_PUSH"
[ "$(grep -c READ_CELL_BROADCASTS "$d/AndroidManifest.xml")" = 1 ] || fail "duplicate CELL_BROADCASTS"
if grep -q sdkInfo "$d/apktool.yml" || ! grep -q packageInfo "$d/apktool.yml"; then fail "apktool.yml"; fi
python3 "$REPO/lineage-gsi/lib/messaging_manifest.py" "$d" | grep -q 'nothing to add' || fail "not idempotent"
ok "messaging_manifest.py adds only missing permissions, keeps targetSdk, is idempotent"

# --- fetch-lineage.sh pinning ----------------------------------------------------
cp "$REPO/lineage-gsi/inputs.lock" "$T/inputs.lock.orig"
restore() { cp "$T/inputs.lock.orig" "$REPO/lineage-gsi/inputs.lock"; }
trap 'restore; rm -rf "$T"' EXIT
xz -T0 -1 -c "$T/good.img" > "$T/gsi.img.xz"
"$REPO/lineage-gsi/fetch-lineage.sh" --variant vanilla --local "$T/gsi.img.xz" >/dev/null
h=$(sha256sum "$T/gsi.img.xz" | cut -d' ' -f1)
grep -q "^vanilla .* $h\$" "$REPO/lineage-gsi/inputs.lock" || fail "hash not pinned"
cmp -s "$CACHE/lineage/vanilla.img" "$T/good.img" || fail "unpacked image differs"
ok "fetch-lineage.sh pins the first hash and unpacks the image"
printf x >> "$T/gsi.img.xz"
if "$REPO/lineage-gsi/fetch-lineage.sh" --variant vanilla --local "$T/gsi.img.xz" 2>"$log"; then fail "bad hash accepted"; fi
grep -q 'sha256 mismatch' "$log" || fail "mismatch message"
ok "fetch-lineage.sh refuses a file that differs from the pinned hash"

echo "all $pass tests passed"
