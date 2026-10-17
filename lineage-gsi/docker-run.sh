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
# On Windows run this from Git Bash with Docker Desktop. The repository path
# must not contain spaces.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "docker-run: $*" >&2; exit 1; }
usage() { sed -n '5,19s/^# \{0,1\}//p' "$0" >&2; exit 2; }

# Git Bash (MSYS) rewrites /paths in arguments and Docker needs Windows paths.
case $(uname -s) in
    MINGW*|MSYS*|CYGWIN*) WIN=1; export MSYS_NO_PATHCONV=1 ;;
    *) WIN=0 ;;
esac
hostpath() { if [ "$WIN" = 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

mounts=()
while [ $# -gt 0 ]; do
    case $1 in
        --stock) [ -d "$2" ] || die "no directory $2"
                 mounts+=(-v "$(hostpath "$(cd "$2" && pwd)"):/stock:ro"); shift 2 ;;
        --file) [ -f "$2" ] || die "no file $2"
                mounts+=(-v "$(hostpath "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"):/input/$(basename "$2"):ro"); shift 2 ;;
        --) shift; break ;;
        -h|--help) usage ;;
        *) die "unknown option $1 (put the command after --)" ;;
    esac
done
[ $# -gt 0 ] || usage
command -v docker >/dev/null || die "docker is not installed"

img=xp8-lineage-build
docker image inspect "$img" >/dev/null 2>&1 ||
    docker build --platform linux/amd64 -t "$img" "$(hostpath "$REPO/lineage-gsi")"
tty=()
[ -t 0 ] && [ -t 1 ] && tty=(-it)
# Windows has no host uid to map; Docker Desktop's file sharing handles ownership.
user=()
[ "$WIN" = 1 ] || user=(-u "$(id -u):$(id -g)")
exec docker run --rm "${tty[@]}" --platform linux/amd64 "${user[@]}" -e HOME=/tmp \
    -v "$(hostpath "$REPO"):/src" "${mounts[@]}" -w /src "$img" "$@"
