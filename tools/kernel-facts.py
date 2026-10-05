#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
"""Report what the XP8's stock kernel can and cannot do for LineageOS.

usage: kernel-facts.py BOOT_IMG [--out DIR] [--config FILE]

BOOT_IMG  boot_a.bin (or .zst) from the EDL backup made by
          third_party/sonim-xp8-gsi/scripts/dump-stock.sh
--out     write Image, the appended DTBs and the kernel config here
--config  evaluate this kernel config instead of the embedded one, e.g. one
          pulled from a running phone: adb shell zcat /proc/config.gz > cfg

Reads a boot image header v0 (the XP8's format), gunzips Image.gz-dtb, splits
the appended device trees and extracts the IKCONFIG blob when the kernel was
built with one. Then it checks the options LineageOS depends on.

Use the output for a GPL source request to Sonim, or as the starting point
for rebuilding a kernel from CodeLinaro's msm-4.4 tree (docs/SOURCE-PORT.md).
"""
import argparse
import gzip
import json
import os
import re
import struct
import subprocess
import sys
import zlib

# option -> why it matters (needed state is "y")
CHECKS = [
    ('CONFIG_BPF_SYSCALL', 'eBPF: LineageOS 19+ netd and Connectivity need it; '
     'without it only BPF-less GSI patches keep networking alive'),
    ('CONFIG_CGROUP_BPF', 'eBPF programs on cgroups: per-app traffic accounting and firewall'),
    ('CONFIG_BPF_JIT', 'eBPF JIT (performance only)'),
    ('CONFIG_EROFS_FS', 'EROFS: needed to mount EROFS system images'),
    ('CONFIG_USERFAULTFD', 'userfaultfd: ART concurrent compacting GC'),
    ('CONFIG_PSI', 'pressure stall information: lmkd memory pressure'),
    ('CONFIG_FS_ENCRYPTION', 'fscrypt (4.13+ name): FBE v2 / metadata encryption'),
    ('CONFIG_EXT4_ENCRYPTION', 'ext4 encryption (pre-4.13 name): FBE v1 via ICE'),
    ('CONFIG_DM_VERITY', 'dm-verity'),
    ('CONFIG_ANDROID_BINDERFS', 'binderfs'),
    ('CONFIG_ZRAM', 'zram swap'),
    ('CONFIG_IKCONFIG_PROC', '/proc/config.gz'),
    ('CONFIG_SECURITY_SELINUX', 'SELinux'),
    ('CONFIG_MODULES', 'loadable modules'),
]


def read_input(path):
    data = open(path, 'rb').read()
    if path.endswith('.zst') or data[:4] == b'\x28\xb5\x2f\xfd':
        data = subprocess.run(['zstd', '-dc', path], check=True, capture_output=True).stdout
    return data


def parse_boot(data):
    if data[:8] != b'ANDROID!':
        sys.exit('kernel-facts: not an Android boot image (no ANDROID! magic)')
    (ksize, kaddr, rsize, raddr, ssize, saddr, tags, page, hver, osver) = struct.unpack_from('<10I', data, 8)
    name = data[48:64].split(b'\0')[0].decode('ascii', 'replace')
    cmd = data[64:64 + 512].split(b'\0')[0] + data[608:608 + 1024].split(b'\0')[0]
    h = dict(kernel_size=ksize, kernel_addr=hex(kaddr), ramdisk_size=rsize, ramdisk_addr=hex(raddr),
             second_size=ssize, tags_addr=hex(tags), page_size=page, header_version=hver,
             os_version=hex(osver), name=name, cmdline=cmd.decode('ascii', 'replace'))
    kernel = data[page:page + ksize]
    return h, kernel


def split_kernel(kernel):
    """Image.gz-dtb -> (Image, [dtb...]); a raw Image -> (Image, dtbs found after it)."""
    if kernel[:2] == b'\x1f\x8b':
        d = zlib.decompressobj(16 + zlib.MAX_WBITS)
        image = d.decompress(kernel)
        rest = d.unused_data
    else:
        image, rest = kernel, b''
        i = kernel.find(b'\xd0\x0d\xfe\xed')
        if i > 0:
            image, rest = kernel[:i], kernel[i:]
    dtbs, i = [], 0
    while True:
        i = rest.find(b'\xd0\x0d\xfe\xed', i)
        if i < 0 or i + 8 > len(rest):
            break
        size = struct.unpack_from('>I', rest, i + 4)[0]
        if size < 40 or i + size > len(rest):
            i += 4
            continue
        dtbs.append(rest[i:i + size])
        i += size
    return image, dtbs


def fdt_root_props(blob):
    """Root-node properties of a flattened device tree (no external tools)."""
    (magic, total, off_struct, off_strings, _, version, _, _, size_strings, size_struct) = \
        struct.unpack_from('>10I', blob, 0)
    strings = blob[off_strings:off_strings + size_strings]
    p, depth, props = off_struct, 0, {}
    while p < off_struct + size_struct:
        tok = struct.unpack_from('>I', blob, p)[0]
        p += 4
        if tok == 1:  # BEGIN_NODE
            end = blob.index(b'\0', p)
            p = (end + 4) & ~3
            depth += 1
        elif tok == 2:  # END_NODE
            depth -= 1
            if depth == 0:
                break
        elif tok == 3:  # PROP
            ln, nameoff = struct.unpack_from('>II', blob, p)
            p += 8
            val = blob[p:p + ln]
            p = (p + ln + 3) & ~3
            if depth == 1:
                name = strings[nameoff:strings.index(b'\0', nameoff)].decode()
                props[name] = val
        elif tok == 4:  # NOP
            continue
        elif tok == 9:  # END
            break
        else:
            break
    out = {}
    for k in ('model', 'compatible'):
        if k in props:
            out[k] = [s.decode('ascii', 'replace') for s in props[k].split(b'\0') if s]
    for k in ('qcom,msm-id', 'qcom,board-id', 'qcom,pmic-id'):
        if k in props:
            v = props[k]
            out[k] = [hex(x) for x in struct.unpack('>%dI' % (len(v) // 4), v[:len(v) // 4 * 4])]
    return out


def ikconfig(image):
    s = image.find(b'IKCFG_ST')
    e = image.find(b'IKCFG_ED', s)
    if s < 0 or e < 0:
        return None
    return gzip.decompress(image[s + 8:e]).decode('utf-8', 'replace')


def evaluate(cfg):
    vals = {}
    for line in cfg.splitlines():
        m = re.match(r'^(CONFIG_\w+)=(.*)$', line)
        if m:
            vals[m.group(1)] = m.group(2)
        m = re.match(r'^# (CONFIG_\w+) is not set$', line)
        if m:
            vals[m.group(1)] = 'n'
    return [(k, vals.get(k, 'absent'), why) for k, why in CHECKS]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('boot')
    ap.add_argument('--out')
    ap.add_argument('--config')
    a = ap.parse_args()

    h, kernel = parse_boot(read_input(a.boot))
    image, dtbs = split_kernel(kernel)
    m = re.search(rb'Linux version [^\n\0]+', image)
    facts = {'header': h, 'linux_version': m.group(0).decode('ascii', 'replace') if m else None,
             'kernel_gzip': kernel[:2] == b'\x1f\x8b', 'dtbs': [fdt_root_props(d) for d in dtbs]}

    cfg = open(a.config).read() if a.config else ikconfig(image)
    facts['config_source'] = a.config or ('embedded IKCONFIG' if cfg else None)
    facts['checks'] = [dict(option=k, value=v, why=w) for k, v, w in evaluate(cfg)] if cfg else []

    print('kernel     %s' % (facts['linux_version'] or 'version string not found'))
    print('boot hdr   v%d, page %d, kernel %s at %s, ramdisk %d bytes, os_version %s' % (
        h['header_version'], h['page_size'], 'Image.gz' if facts['kernel_gzip'] else 'Image',
        h['kernel_addr'], h['ramdisk_size'], h['os_version']))
    print('cmdline    %s' % h['cmdline'])
    print('dtbs       %d appended' % len(dtbs))
    for i, d in enumerate(facts['dtbs']):
        print('  [%d] %s  msm-id %s  board-id %s' % (
            i, '; '.join(d.get('model', ['?'])), ' '.join(d.get('qcom,msm-id', [])),
            ' '.join(d.get('qcom,board-id', []))))
    if cfg:
        print('config     %s' % facts['config_source'])
        for c in facts['checks']:
            print('  %-26s %-7s %s' % (c['option'], c['value'], c['why']))
    else:
        print('config     not embedded (no IKCONFIG). On a running phone try:\n'
              '           adb shell zcat /proc/config.gz > xp8.config; then rerun with --config xp8.config')

    if a.out:
        os.makedirs(a.out, exist_ok=True)
        open(os.path.join(a.out, 'Image'), 'wb').write(image)
        for i, d in enumerate(dtbs):
            open(os.path.join(a.out, 'dtb-%02d.dtb' % i), 'wb').write(d)
        if cfg and not a.config:
            open(os.path.join(a.out, 'config'), 'w').write(cfg)
        with open(os.path.join(a.out, 'facts.json'), 'w') as f:
            json.dump(facts, f, indent=1)
        print('wrote      %s' % a.out)


if __name__ == '__main__':
    main()
