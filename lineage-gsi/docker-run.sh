#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Run a command from this checkout inside the lineage-gsi/Dockerfile image.
# Needed on macOS and Windows; optional on Linux.
#
# usage: lineage-gsi/docker-run.sh [--stock DIR] [--file FILE] -- COMMAND [ARGS...]
#   --stock DIR   mount your stock backup read-only at /stock
#   --file FILE   mount one downloaded file read-only at /input/<name>
# examples:
#   lineage-gsi/docker-run.sh -- lineage-gsi/build.sh --variant gapps
#   lineage-gsi/docker-run.sh --file ~/Downloads/LineageOS-23.2-20260524-GAPPS-EXT4-GSI.7z \
#       -- lineage-gsi/build.sh --local /input/LineageOS-23.2-20260524-GAPPS-EXT4-GSI.7z
#   lineage-gsi/docker-run.sh --stock ~/xp8-backup -- lineage-gsi/assemble.sh /stock
#
# Flashing is not done in Docker: run scripts/flash.sh on the host (USB access).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "docker-run: $*" >&2; exit 1; }
usage() { sed -n '5,18s/^# \{0,1\}//p' "$0" >&2; exit 2; }

mounts=()
while [ $# -gt 0 ]; do
    case $1 in
        --stock) [ -d "$2" ] || die "no directory $2"
                 mounts+=(-v "$(cd "$2" && pwd):/stock:ro"); shift 2 ;;
        --file) [ -f "$2" ] || die "no file $2"
                mounts+=(-v "$(cd "$(dirname "$2")" && pwd)/$(basename "$2"):/input/$(basename "$2"):ro"); shift 2 ;;
        --) shift; break ;;
        -h|--help) usage ;;
        *) die "unknown option $1 (put the command after --)" ;;
    esac
done
[ $# -gt 0 ] || usage
command -v docker >/dev/null || die "docker is not installed"

img=xp8-lineage-build
docker image inspect "$img" >/dev/null 2>&1 ||
    docker build --platform linux/amd64 -t "$img" "$REPO/lineage-gsi"
tty=()
[ -t 0 ] && [ -t 1 ] && tty=(-it)
exec docker run --rm "${tty[@]}" --platform linux/amd64 -u "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$REPO:/src" "${mounts[@]}" -w /src "$img" "$@"
