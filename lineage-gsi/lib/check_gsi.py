#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
"""Check that a GSI system image can work on the Sonim XP8 (XP8800).

usage: check_gsi.py IMAGE [--json OUT.json]

Fatal (exit 1), because the phone cannot boot such an image:
  - not ext4 (EROFS needs a 5.4+ kernel; the XP8 runs 4.4.205)
  - Android sparse image (convert with simg2img first)
  - larger than system_a (4 GiB)
  - no VNDK 29 (the stock vendor is Android 10, VNDK 29)
  - no SELinux 29.0 mapping (system policy cannot merge the v29 vendor policy)

Reported for the build script (not fatal): build tags, Messaging and its
oat files, the tethering APEX form.

Reads the image with debugfs; needs no root and no loop mount.
"""
import argparse
import json
import os
import re
import struct
import subprocess
import sys

SYSTEM_A_BYTES = 4 * 1024 ** 3
VNDK_APEX_DIRS = ('/system/system_ext/apex', '/system/apex')
VNDK_LIB_DIRS = ('/system/system_ext/lib64', '/system/lib64', '/system/system_ext/lib', '/system/lib')
MAPPING = ('/system/system_ext/etc/selinux/mapping/29.0.cil', '/system/etc/selinux/mapping/29.0.cil')
MESSAGING = '/system/product/app/messaging'


def fs_type(path):
    with open(path, 'rb') as f:
        head = f.read(4096)
    if len(head) < 2048:
        return 'too-small'
    if struct.unpack_from('<I', head, 0)[0] == 0xED26FF3A:
        return 'sparse'
    if struct.unpack_from('<I', head, 1024)[0] == 0xE0F5E1E2:
        return 'erofs'
    if struct.unpack_from('<H', head, 1024 + 56)[0] == 0xEF53:
        return 'ext4'
    return 'unknown'


def debugfs(img, cmd):
    r = subprocess.run(['debugfs', '-R', cmd, img], capture_output=True, text=True)
    return r.stdout


def ls(img, d):
    """Names in directory d, or None when it does not exist."""
    out = debugfs(img, 'ls -p ' + d)
    names = []
    for line in out.splitlines():
        p = line.split('/')
        if len(p) >= 7 and p[5] not in ('.', '..'):
            names.append(p[5])
    if not names and not exists(img, d):
        return None
    return names


def exists(img, p):
    r = subprocess.run(['debugfs', '-R', 'stat ' + p, img], capture_output=True, text=True)
    return 'File not found' not in (r.stdout + r.stderr) and 'Inode:' in r.stdout


def cat(img, p):
    r = subprocess.run(['debugfs', '-R', 'cat ' + p, img], capture_output=True)
    return r.stdout.decode('utf-8', 'replace')


def props(text):
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            out[k] = v
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--json')
    a = ap.parse_args()

    r = {'image': a.image, 'errors': [], 'warnings': []}
    r['bytes'] = os.path.getsize(a.image)
    r['fs'] = fs_type(a.image)
    err, warnv = r['errors'].append, r['warnings'].append

    if r['fs'] == 'erofs':
        err('EROFS image: the XP8 kernel (4.4.205) has no EROFS driver, and the EROFS '
            'LineageOS targets carry no VNDK 29. Use the EXT4 build.')
    elif r['fs'] == 'sparse':
        err('Android sparse image: convert it first (simg2img in.img out.img)')
    elif r['fs'] != 'ext4':
        err('not an ext4 image (%s)' % r['fs'])
    if r['bytes'] > SYSTEM_A_BYTES:
        err('image is %d bytes, system_a holds %d' % (r['bytes'], SYSTEM_A_BYTES))

    if r['fs'] == 'ext4':
        vndk = set()
        for d in VNDK_APEX_DIRS:
            for n in ls(a.image, d) or []:
                m = re.match(r'com\.android\.vndk\.v(\d+)\.c?apex$', n)
                if m:
                    vndk.add(int(m.group(1)))
        for d in VNDK_LIB_DIRS:
            for n in ls(a.image, d) or []:
                m = re.match(r'vndk(?:-sp)?-(\d+)$', n)
                if m:
                    vndk.add(int(m.group(1)))
        r['vndk'] = sorted(vndk)
        if 29 not in vndk:
            err('no VNDK 29 in the image (found %s): the XP8 vendor is VNDK 29. '
                'Only the EXT4 LineageOS targets include it.' % (r['vndk'] or 'none'))

        r['mapping_29'] = any(exists(a.image, p) for p in MAPPING)
        if not r['mapping_29']:
            err('no SELinux mapping/29.0.cil: the system policy cannot load a v29 vendor policy')

        p = props(cat(a.image, '/system/build.prop'))
        r['props'] = {k: p.get(k, '') for k in (
            'ro.system.build.version.release', 'ro.system.build.version.sdk', 'ro.system.build.tags',
            'ro.system.build.type', 'ro.lineage.version', 'ro.lineage.display.version',
            'ro.system.build.fingerprint')}
        if not p:
            warnv('no /system/build.prop: is this a system-as-root GSI image?')
        elif not p.get('ro.lineage.version'):
            warnv('ro.lineage.version is not set: this does not look like a LineageOS image')
        if p and p.get('ro.system.build.tags') != 'test-keys':
            warnv('build tags are %r, not test-keys: apps re-signed with the AOSP platform '
                  'test key (IMS, Messaging) will not match this build' % p.get('ro.system.build.tags'))

        r['messaging_apk'] = exists(a.image, MESSAGING + '/messaging.apk')
        r['messaging_oat'] = all(exists(a.image, MESSAGING + '/oat/arm64/messaging.' + e)
                                 for e in ('odex', 'vdex'))
        apex = ls(a.image, '/system/apex') or []
        r['tethering'] = next((n for n in apex if n.startswith('com.android.tethering.')), None)
        ims = [d for d in (ls(a.image, '/system/system_ext/priv-app') or []) if 'ims' in d.lower()]
        r['bundled_ims'] = ims
        if ims:
            warnv('image already ships IMS app(s) %s; ImsCafXp8 would be a second copy' % ims)

    for w in r['warnings']:
        print('check_gsi: warning: ' + w, file=sys.stderr)
    for e in r['errors']:
        print('check_gsi: error: ' + e, file=sys.stderr)
    summary = '%s, %.2f GiB, VNDK %s, Android %s, LineageOS %s' % (
        r['fs'], r['bytes'] / 1024 ** 3, r.get('vndk', '?'),
        r.get('props', {}).get('ro.system.build.version.release', '?'),
        r.get('props', {}).get('ro.lineage.display.version') or r.get('props', {}).get('ro.lineage.version') or '?')
    print('check_gsi: ' + summary)
    if a.json:
        with open(a.json, 'w') as f:
            json.dump(r, f, indent=1, sort_keys=True)
    return 1 if r['errors'] else 0


if __name__ == '__main__':
    sys.exit(main())
