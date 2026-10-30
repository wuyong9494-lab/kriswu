#!/usr/bin/env python3
"""Record six simulated seconds of the fixed Twin Gates fixture, then verify identity.
This is simulator visual evidence, not device FPS or audio-sync acceptance.
Usage: record_arena_sample.py DEVICE OUTPUT
"""
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
from capture_arena_sample import APP_ID, simctl, stop_app


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    device, output = sys.argv[1], pathlib.Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    stop_app(device)
    data = pathlib.Path(simctl('get_app_container', device, APP_ID, 'data'))
    marker = data / 'Documents/arena-capture-ready.json'
    marker.unlink(missing_ok=True)
    path = output / 'harbor-opening.mp4'
    recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo',
                                 '--codec=h264', str(path)], stdout=subprocess.DEVNULL)
    evidence = None
    try:
        time.sleep(1)
        if recorder.poll() is not None:
            raise RuntimeError('Video recorder exited before launch')
        simctl('launch', device, APP_ID, '-demo', '-screen', 'arenaHarborBenchmark',
               '-arena.purpleSample', 'NO', '-arena.snapshotTime', '6', '-arena.legacyRanger', 'NO')
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if recorder.poll() is not None:
                raise RuntimeError('Video recorder exited during capture')
            if marker.exists():
                evidence = json.loads(marker.read_text())
                if 6 <= evidence.get('simulationTime', -1) < 6.04:
                    break
            time.sleep(0.5)
        else:
            raise RuntimeError('No verified end frame for recorded fixture')
        assert evidence.get('map') == 'twin_gates_sample_v1', evidence
        assert evidence.get('rangerAsset') == 'Ranger_FaceSample.glb', evidence
        assert evidence.get('qualitySample') is True, evidence
        time.sleep(1)
    finally:
        if recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
            try:
                recorder.wait(timeout=30)
            except subprocess.TimeoutExpired:
                recorder.kill()
                recorder.wait(timeout=10)
                raise RuntimeError('Video finalization timed out')
    if recorder.returncode or not path.exists() or path.stat().st_size < 1024:
        raise RuntimeError('Video output missing or recorder failed')
    evidence.update(sourceCommit=os.environ.get('GITHUB_SHA'),
                    capture='simulator-opening-six-seconds',
                    limitations=['Includes launch and final frozen frame',
                                 'Not wall/box/grass route coverage',
                                 'No physical-device FPS, thermal or audio-sync validation'])
    (output / 'harbor-opening.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print('Verified continuous capture:', path, flush=True)


if __name__ == '__main__':
    main()
