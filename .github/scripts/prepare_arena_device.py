#!/usr/bin/env python3
"""Create an isolated capture device; do not reuse an encoder's simulator session."""
import json
import os
import subprocess
import sys
from capture_arena_sample import simctl

previous = os.environ.get('SAMPLE_DEVICE')
if previous:
    try:
        simctl('shutdown', previous, check=False, timeout=30)
    except subprocess.TimeoutExpired:
        print('Previous device shutdown timed out; retaining it for diagnostics', flush=True)
entries = json.loads(simctl('list', 'devices', 'available', '-j'))['devices']
phones = [(runtime, d) for runtime, devices in sorted(entries.items(), reverse=True)
          if 'iOS' in runtime for d in devices if d['name'].startswith('iPhone')]
runtime, phone = next((p for p in phones if p[1]['name'] == 'iPhone 17 Pro Max'), phones[0])
device = simctl('create', 'Arena ' + sys.argv[1], phone['deviceTypeIdentifier'], runtime, timeout=60)
with open(os.environ['GITHUB_ENV'], 'a') as env:
    env.write('SAMPLE_DEVICE=' + device + '\n')
    env.write('ARENA_DEVICES=' + ' '.join(filter(None, [os.environ.get('ARENA_DEVICES'), device])) + '\n')
simctl('boot', device, timeout=90)
simctl('bootstatus', device, '-b', timeout=180)
simctl('install', device, 'sample-build/Build/Products/Debug-iphonesimulator/ShiftReminder.app', timeout=120)
print('Ready:', device, runtime, flush=True)
