#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
"""Add the SMS-app permissions Android 16 requires to an apktool-decoded Messaging.

usage: messaging_manifest.py DECODED_DIR

Android 16 refuses Messaging as the default SMS app without RECEIVE_WAP_PUSH
and READ_CELL_BROADCASTS (finding from ndoo/sonim-xp8-gsi, which patches the
TrebleDroid copy with a fixed diff). LineageOS ships its own Messaging fork,
so this edits the manifest by content rather than by line context, and does
nothing for permissions that are already declared.

apktool rewrites targetSdkVersion to the framework's SDK when it rebuilds
from apktool.yml's sdkInfo. The original min/target values are moved from
apktool.yml into an explicit <uses-sdk> element so they survive unchanged.
"""
import re
import sys

PERMS = ('android.permission.RECEIVE_WAP_PUSH', 'android.permission.READ_CELL_BROADCASTS')


def main(d):
    yml_path = d + '/apktool.yml'
    man_path = d + '/AndroidManifest.xml'
    yml = open(yml_path, encoding='utf-8').read()
    man = open(man_path, encoding='utf-8').read()

    sdk = {}
    m = re.search(r'^sdkInfo:\n((?:[ \t]+\S.*\n)+)', yml, re.M)
    if m:
        for k, v in re.findall(r"^\s+(\w+):\s*'?(\d+)'?\s*$", m.group(1), re.M):
            sdk[k] = v
        yml = yml[:m.start()] + yml[m.end():]

    added = []
    head = re.search(r'<manifest\b[^>]*>', man)
    if not head:
        sys.exit('messaging_manifest: no <manifest> element in ' + man_path)
    ins = ''
    if '<uses-sdk' not in man and sdk.get('minSdkVersion') and sdk.get('targetSdkVersion'):
        ins += '\n    <uses-sdk android:minSdkVersion="%s" android:targetSdkVersion="%s"/>' % (
            sdk['minSdkVersion'], sdk['targetSdkVersion'])
        added.append('uses-sdk %s/%s' % (sdk['minSdkVersion'], sdk['targetSdkVersion']))
    for p in PERMS:
        if not re.search(r'<uses-permission[^>]*android:name="%s"' % re.escape(p), man):
            ins += '\n    <uses-permission android:name="%s"/>' % p
            added.append(p.rsplit('.', 1)[1])
    man = man[:head.end()] + ins + man[head.end():]

    open(yml_path, 'w', encoding='utf-8').write(yml)
    open(man_path, 'w', encoding='utf-8').write(man)
    print('messaging_manifest: ' + (', '.join(added) if added else 'nothing to add'))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__.split('\n\n')[1])
    main(sys.argv[1])
