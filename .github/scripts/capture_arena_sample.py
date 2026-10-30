#!/usr/bin/env python3
"""Capture an already installed simulator build. No build, credentials or publishing.
Usage: python3 .github/scripts/capture_arena_sample.py DEVICE_UUID OUTPUT_DIR [canyon|harbor|menus]
Requires a booted iOS simulator and an installed Debug build containing arenaSampleBenchmark.
"""
import json
import pathlib
import subprocess
import sys
import time

APP_ID = 'com.kriswu.shiftreminder'

def simctl(*args, check=True, timeout=150):
    return subprocess.run(['xcrun', 'simctl', *args], check=check,
                          capture_output=True, text=True, timeout=timeout).stdout.strip()

def stop_app(device):
    # A timed-out terminate can leave a late stop request racing the next launch.
    # Recover only the requested simulator; never kill unrelated host processes.
    try:
        simctl('terminate', device, APP_ID, check=False, timeout=20)
    except subprocess.TimeoutExpired:
        print('Simulator terminate timed out; restarting this capture device', flush=True)
        simctl('shutdown', device, check=False, timeout=30)
        simctl('boot', device, timeout=90)
        simctl('bootstatus', device, '-b', timeout=120)

def capture_menus(device, output, data):
    marker = data / 'Documents/arena-sample-menu-ready.json'
    model_marker = data / 'Documents/arena-capture-ready.json'
    for page, screen in [(0, 'arenaSampleReview'), (1, 'arenaSampleMapReview')]:
        print('Capturing menu:', screen, flush=True)
        stop_app(device)
        marker.unlink(missing_ok=True)
        model_marker.unlink(missing_ok=True)
        simctl('launch', device, APP_ID, '-demo', '-screen', screen,
               '-arena.previewRanger', 'YES', '-arena.rangerStill', 'YES', '-arena.legacyRanger', 'NO', '-arena.captureTraversal', 'NO')
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            evidence = json.loads(marker.read_text()) if marker.exists() else {}
            if (evidence.get('scene') == 'sampleReview' and evidence.get('page') == page
                    and evidence.get('map') == 'twin_gates_sample_v1'
                    and evidence.get('width', 0) > 0 and evidence.get('height', 0) > 0):
                if page == 1:
                    break
                model = json.loads(model_marker.read_text()) if model_marker.exists() else {}
                if model.get('asset') == 'Ranger_FaceSample.glb' and model.get('qualitySample') is True:
                    evidence['model'] = model
                    break
            time.sleep(0.5)
        else:
            diagnostic = {'page': page, 'menu': json.loads(marker.read_text()) if marker.exists() else None,
                          'model': json.loads(model_marker.read_text()) if model_marker.exists() else None}
            (output / ('failed-page-' + str(page) + '.json')).write_text(json.dumps(diagnostic, indent=2) + '\n')
            simctl('io', device, 'screenshot', str(output / ('failed-page-' + str(page) + '.png')), check=False)
            print('Menu readiness failure:', json.dumps(diagnostic), flush=True)
            raise SystemExit('Sample menu or model did not report readiness')
        time.sleep(2)
        # Rotation may finish after the first nonzero layout marker. Save the
        # current layout, not the earlier portrait dimensions.
        current = json.loads(marker.read_text())
        assert current.get('scene') == 'sampleReview' and current.get('page') == page, current
        assert current.get('map') == 'twin_gates_sample_v1', current
        assert current.get('width', 0) > 0 and current.get('height', 0) > 0, current
        if page == 0:
            model = json.loads(model_marker.read_text())
            assert model.get('asset') == 'Ranger_FaceSample.glb' and model.get('qualitySample') is True, model
            current['model'] = model
        evidence = current
        label = 'sample-hero' if page == 0 else 'sample-map'
        simctl('io', device, 'screenshot', str(output / (label + '.png')))
        (output / (label + '.json')).write_text(json.dumps(evidence, indent=2) + '\n')


def main():
    if len(sys.argv) not in (3, 4):
        raise SystemExit(__doc__)
    device, output = sys.argv[1], pathlib.Path(sys.argv[2])
    scene = sys.argv[3] if len(sys.argv) == 4 else 'canyon'
    if scene not in ('canyon', 'harbor', 'menus'):
        raise SystemExit('Scene must be canyon, harbor or menus')
    screen = 'arenaHarborBenchmark' if scene == 'harbor' else 'arenaSampleBenchmark'
    expected_map = 'twin_gates_sample_v1' if scene == 'harbor' else 'canyon'
    output.mkdir(parents=True, exist_ok=True)
    data = pathlib.Path(simctl('get_app_container', device, APP_ID, 'data'))
    if scene == 'menus':
        capture_menus(device, output, data)
        return
    marker = data / 'Documents/arena-capture-ready.json'
    for label, target in [('sample-early', 0.25), ('sample-combat', 1.2)]:
        label = scene + '-' + label
        stop_app(device)
        marker.unlink(missing_ok=True)
        simctl('launch', device, APP_ID, '-demo', '-screen', screen,
               '-arena.purpleSample', 'NO' if scene == 'harbor' else 'YES', '-arena.snapshotTime', str(target), '-arena.legacyRanger', 'NO', '-arena.captureTraversal', 'NO')
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
        assert evidence.get('map') == expected_map, evidence
        time.sleep(2)
        simctl('io', device, 'screenshot', str(output / (label + '.png')))
        (output / (label + '.json')).write_text(json.dumps(evidence, indent=2) + '\n')
        print(label, evidence['simulationTime'], evidence['rangerAsset'], flush=True)

if __name__ == '__main__':
    main()
