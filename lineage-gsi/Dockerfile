# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
#
# Build environment for lineage-gsi/*.sh: ndoo's build image
# (third_party/sonim-xp8-gsi/build/Dockerfile, same pinned base) plus 7-Zip
# for the LineageOS GSI archives.
FROM --platform=linux/amd64 debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      7zip \
      android-sdk-libsparse-utils \
      binutils \
      ca-certificates \
      curl \
      device-tree-compiler \
      diffutils \
      e2fsprogs \
      file \
      git \
      openjdk-21-jre-headless \
      openssl \
      patch \
      patchelf \
      python3 \
      tar \
      unzip \
      xz-utils \
      zip \
      zstd \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
# The checkout is mounted here, possibly owned by another uid.
RUN git config --system --add safe.directory '*'
WORKDIR /src
