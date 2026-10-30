#!/usr/bin/env python3
"""Capture an already installed simulator build. No build, credentials or publishing.
Usage: python3 .github/scripts/capture_arena_sample.py DEVICE_UUID OUTPUT_DIR
Requires a booted iOS simulator and an installed Debug build containing arenaSampleBenchmark.
"""
import json
import pathlib
import subprocess
import sys
import time

APP_ID = 'com.kriswu.shiftreminder'

def simctl(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check,
                          capture_output=True, text=True, timeout=150).stdout.strip()

def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    device, output = sys.argv[1], pathlib.Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    data = pathlib.Path(simctl('get_app_container', device, APP_ID, 'data'))
    marker = data / 'Documents/arena-capture-ready.json'
    for label, target in [('sample-early', 0.25), ('sample-combat', 1.2)]:
        simctl('terminate', device, APP_ID, check=False)
        marker.unlink(missing_ok=True)
        simctl('launch', device, APP_ID, '-demo', '-screen', 'arenaSampleBenchmark',
               '-arena.purpleSample', 'YES', '-arena.snapshotTime', str(target), '-arena.legacyRanger', 'NO')
        deadline = time.monotonic() + 120
        evidence = None
        while time.monotonic() < deadline:
            if marker.exists():
                evidence = json.loads(marker.read_text())
                if target <= evidence.get('simulationTime', -1) < target + 0.04:
                    break
            time.sleep(0.5)
        else:
            raise SystemExit('No frozen sample frame; refusing an unverified capture')
        assert evidence.get('rangerAsset') == 'Ranger_FaceSample.glb', evidence
        assert evidence.get('qualitySample') is True, evidence
        assert evidence.get('map') == 'canyon', evidence
        time.sleep(2)
        simctl('io', device, 'screenshot', str(output / (label + '.png')))
        (output / (label + '.json')).write_text(json.dumps(evidence, indent=2) + '\n')
        print(label, evidence['simulationTime'], evidence['rangerAsset'])

if __name__ == '__main__':
    main()
