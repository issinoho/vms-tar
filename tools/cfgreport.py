#!/usr/bin/env python3
"""List every cached configure answer and where it came from.

Usage: cfgreport.py <config.cache> <probed.site> <vms-manual.site>

Output lines:  <var>=<value>  <source>
where source is 'vms' (answered on VMS), 'manual' (vms-manual.site) or 'host'
(nobody answered for VMS, so the Linux host's result was used).  The 'host'
lines are the review list: each one is either harmless or needs a VMS answer
in vms-manual.site.
"""
import re
import sys


def site_vars(path):
    names = set()
    for line in open(path):
        m = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)=', line)
        if m:
            names.add(m.group(1))
    return names


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    probed = site_vars(sys.argv[2])
    manual = site_vars(sys.argv[3])
    for line in open(sys.argv[1]):
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)=\$\{\1=(.*)\}\s*$', line.rstrip('\n'))
        if not m:
            continue
        var, val = m.groups()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in '\'"':
            val = val[1:-1]
        src = 'manual' if var in manual else 'vms' if var in probed else 'host'
        print('%s=%s  %s' % (var, val, src))


if __name__ == '__main__':
    main()
