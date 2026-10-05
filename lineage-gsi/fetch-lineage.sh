#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Get the LineageOS 23.2 EXT4 GSI into cache/lineage/<variant>.img.
#
# usage: lineage-gsi/fetch-lineage.sh [--variant gapps|vanilla] [--local FILE]
#   --variant V   gapps (default) or vanilla
#   --local FILE  use an archive (.7z/.xz/.gz) or raw .img you already downloaded,
#                 e.g. because SourceForge sent your script a captcha page.
#                 Its sha256 is still checked against inputs.lock when pinned.
#
# The download's sha256 is checked against lineage-gsi/inputs.lock. When the
# lock holds "-" the hash is recorded there (trust on first use); commit it.
set -euo pipefail

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
usage() { sed -n '5,15s/^# \{0,1\}//p' "$0" >&2; exit 2; }

VARIANT=gapps LOCAL=
while [ $# -gt 0 ]; do
    case $1 in
        --variant) VARIANT=$2; shift 2 ;;
        --local) LOCAL=$2; shift 2 ;;
        -h|--help) usage ;;
        *) die "unknown argument $1" ;;
    esac
done
valid_variant "$VARIANT"
need_tools curl

LOCK=$LGSI/inputs.lock
read -r url pin < <(awk -v v="$VARIANT" '$1 == v { print $2, $3 }' "$LOCK")
[ -n "${url:-}" ] || die "no $VARIANT entry in $LOCK"
D=$CACHE/lineage
IMG=$D/$VARIANT.img
mkdir -p "$D"

if [ -n "$LOCAL" ]; then
    [ -f "$LOCAL" ] || die "no such file: $LOCAL"
    src=$LOCAL
else
    name=${url%/download}
    name=${name##*/}
    src=$D/$name
    if [ ! -f "$src" ]; then
        say "downloading $name (about 1 GB)"
        curl -fL --retry 3 -o "$src.part" "$url"
        # SourceForge answers some clients with an HTML page instead of the file.
        if head -c 512 "$src.part" | grep -qi '<html'; then
            rm -f "$src.part"
            die "SourceForge returned a web page, not the archive. Download it in a browser:
  $url
then run: $0 --variant $VARIANT --local /path/to/$name"
        fi
        mv "$src.part" "$src"
    fi
fi

got=$(sha256 "$src")
if [ "$pin" = - ]; then
    say "first fetch of $VARIANT: pinning sha256 $got in inputs.lock (commit this change)"
    tmp=$LOCK.tmp
    awk -v v="$VARIANT" -v h="$got" '$1 == v && $3 == "-" { sub(/-$/, h) } { print }' "$LOCK" > "$tmp"
    mv "$tmp" "$LOCK"
elif [ "$got" != "$pin" ]; then
    die "sha256 mismatch for $src: got $got, inputs.lock pins $pin"
fi

say "unpacking to $IMG"
case $src in
    *.7z)
        z=$(find_7z)
        # The archive should hold exactly one image; refuse to guess otherwise.
        mapfile -t imgs < <("$z" l -slt "$src" | awk -F' = ' '$1 == "Path" && $2 ~ /\.img$/ { print $2 }')
        [ ${#imgs[@]} -eq 1 ] || die "expected one .img in $src, found ${#imgs[@]}: ${imgs[*]:-none}"
        "$z" e -so "$src" "${imgs[0]}" > "$IMG.part" ;;
    *.xz) xz -dc "$src" > "$IMG.part" ;;
    *.gz) gzip -dc "$src" > "$IMG.part" ;;
    *.img) cp "$src" "$IMG.part" ;;
    *) die "unknown archive type: $src" ;;
esac
mv "$IMG.part" "$IMG"
say "$IMG: $(du -h --apparent-size "$IMG" | cut -f1)"
