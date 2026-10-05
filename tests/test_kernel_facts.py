#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 The LineageOS-Sonim-XP8-8800 contributors
# SPDX-License-Identifier: Apache-2.0
"""Offline test for tools/kernel-facts.py with a synthetic XP8-style boot image:
header v0, Image.gz with an IKCONFIG blob, two appended device trees."""
import gzip
import json
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, '..', 'tools', 'kernel-facts.py')


def fdt(props):
    """Minimal FDT: a root node with the given properties (name -> bytes)."""
    strings, offs = b'', {}
    for k in props:
        offs[k] = len(strings)
        strings += k.encode() + b'\0'
    st = struct.pack('>I', 1) + b'\0\0\0\0'          # BEGIN_NODE ""
    for k, v in props.items():
        st += struct.pack('>III', 3, len(v), offs[k]) + v + b'\0' * (-len(v) % 4)
    st += struct.pack('>II', 2, 9)                    # END_NODE, END
    rsv = b'\0' * 16
    off_rsv = 40
    off_struct = off_rsv + len(rsv)
    off_strings = off_struct + len(st)
    total = off_strings + len(strings)
    hdr = struct.pack('>10I', 0xd00dfeed, total, off_struct, off_strings, off_rsv, 17, 16, 0,
                      len(strings), len(st))
    return hdr + rsv + st + strings


CONFIG = """CONFIG_MODULES=y
# CONFIG_BPF_SYSCALL is not set
CONFIG_EXT4_ENCRYPTION=y
CONFIG_DM_VERITY=y
CONFIG_SECURITY_SELINUX=y
CONFIG_IKCONFIG_PROC=y
"""


def boot_image(with_config=True):
    image = b'\0' * 64 + b'Linux version 4.4.205-perf+ (builder@sonim) #1 SMP PREEMPT\n' + b'\0' * 64
    if with_config:
        image += b'IKCFG_ST' + gzip.compress(CONFIG.encode()) + b'IKCFG_ED'
    image += b'\0' * 100
    d1 = fdt({'model': b'Qualcomm Technologies, Inc. SDM 630 PM660 + PM660L MTP\0',
              'compatible': b'qcom,sdm630-mtp\0qcom,sdm630\0',
              'qcom,msm-id': struct.pack('>II', 318, 0x10000),
              'qcom,board-id': struct.pack('>II', 8, 0)})
    d2 = fdt({'model': b'XP8 rev2\0', 'qcom,msm-id': struct.pack('>II', 318, 0x10001)})
    kernel = gzip.compress(image) + d1 + d2
    page = 4096
    cmd = b'console=ttyMSM0,115200,n8 androidboot.hardware=qcom'
    hdr = b'ANDROID!' + struct.pack('<10I', len(kernel), 0x8000, 0, 0x1000000, 0, 0xf00000, 0x100,
                                    page, 0, 0x14000163)
    hdr += b'\0' * 16 + cmd + b'\0' * (512 - len(cmd)) + b'\0' * 32 + b'\0' * 1024
    pad = lambda b: b + b'\0' * (-len(b) % page)
    return pad(hdr) + pad(kernel)


def run(args):
    return subprocess.run([sys.executable, TOOL] + args, capture_output=True, text=True, check=True).stdout


def main():
    with tempfile.TemporaryDirectory() as t:
        b = os.path.join(t, 'boot_a.bin')
        open(b, 'wb').write(boot_image())
        out = run([b, '--out', os.path.join(t, 'o')])
        assert '4.4.205-perf+' in out, out
        assert 'androidboot.hardware=qcom' in out, out
        assert '2 appended' in out and 'SDM 630' in out and 'XP8 rev2' in out, out
        assert '0x13e 0x10000' in out, out  # msm-id 318 = SDM630
        f = json.load(open(os.path.join(t, 'o', 'facts.json')))
        checks = {c['option']: c['value'] for c in f['checks']}
        assert checks['CONFIG_BPF_SYSCALL'] == 'n', checks
        assert checks['CONFIG_EXT4_ENCRYPTION'] == 'y', checks
        assert checks['CONFIG_EROFS_FS'] == 'absent', checks
        assert open(os.path.join(t, 'o', 'config')).read() == CONFIG
        assert len([n for n in os.listdir(os.path.join(t, 'o')) if n.endswith('.dtb')]) == 2
        print('ok   kernel-facts reads header v0, Image.gz, IKCONFIG and 2 appended DTBs')

        open(b, 'wb').write(boot_image(with_config=False))
        out = run([b])
        assert 'not embedded' in out, out
        cfg = os.path.join(t, 'cfg')
        open(cfg, 'w').write('CONFIG_BPF_SYSCALL=y\n')
        out = run([b, '--config', cfg])
        assert 'CONFIG_BPF_SYSCALL' in out and ' y ' in out, out
        print('ok   kernel-facts falls back to --config when IKCONFIG is absent')

        if subprocess.run(['which', 'zstd'], capture_output=True).returncode == 0:
            subprocess.run(['zstd', '-q', b, '-o', b + '.zst'], check=True)
            assert '4.4.205' in run([b + '.zst'])
            print('ok   kernel-facts reads a .zst backup')


if __name__ == '__main__':
    main()
