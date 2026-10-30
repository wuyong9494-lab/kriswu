#!/usr/bin/env python3
"""Record six simulated seconds of the fixed Twin Gates fixture, then verify identity.
This is simulator visual evidence, not device FPS or audio-sync acceptance.
Usage: record_arena_sample.py DEVICE OUTPUT [traversal]
"""
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
from capture_arena_sample import APP_ID, simctl, stop_app


def validate_traversal(evidence):
    trace = evidence.get('routeTrace', [])
    if evidence.get('captureTraversal') is not True or evidence.get('routeComplete') is not True:
        raise RuntimeError('Traversal did not complete')
    if len(trace) < 60 or not any(2 <= p['x'] < 4 and 9 <= p['y'] < 12 for p in trace):
        raise RuntimeError('Missing grass traversal evidence')
    if not any(4.42 < p['x'] < 7.58 and 9.40 <= p['y'] < 9.55 for p in trace):
        raise RuntimeError('Missing wall-edge traversal evidence')
    if not all(b['time'] > a['time'] for a, b in zip(trace, trace[1:])):
        raise RuntimeError('Invalid traversal timestamps')


def prepare_recording_device(device, traversal):
    if os.environ.get('ARENA_FRESH_RECORDING_DEVICE') == device:
        # This UUID was just created and installed by prepare_arena_device.py.
        # Terminating a never-launched app can stall FrontBoard and trigger a
        # destructive restart of this otherwise healthy fresh simulator.
        return
    stop_app(device)


def main():
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] != "traversal"):
        raise SystemExit(__doc__)
    device, output = sys.argv[1], pathlib.Path(sys.argv[2])
    traversal = len(sys.argv) == 4
    duration = 16 if traversal else 6
    stem = 'harbor-traversal' if traversal else 'harbor-opening'
    output.mkdir(parents=True, exist_ok=True)
    prepare_recording_device(device, traversal)
    data = pathlib.Path(simctl('get_app_container', device, APP_ID, 'data'))
    marker = data / 'Documents/arena-capture-ready.json'
    marker.unlink(missing_ok=True)
    path = output / (stem + '.mp4')
    (output / (stem + '.json')).unlink(missing_ok=True)
    path.unlink(missing_ok=True)
    diagnostic = dict(sourceCommit=os.environ.get('GITHUB_SHA'), device=device,
                      phase='starting', mediaFinalized=False, sceneEvidence=None)
    diagnostic_path = output / (stem + '.recording.json')
    def save_diagnostic():
        diagnostic_path.write_text(json.dumps(diagnostic, indent=2) + '\n')
    save_diagnostic()
    ready = data / 'Documents/arena-recording-ready'
    start = data / 'Documents/arena-recording-start'
    ready.unlink(missing_ok=True)
    start.unlink(missing_ok=True)
    try:
        diagnostic['phase'] = 'launching-before-recorder'
        save_diagnostic()
        simctl('launch', device, APP_ID, '-demo', '-screen', 'arenaHarborBenchmark',
               '-arena.purpleSample', 'NO', '-arena.snapshotTime', str(duration), '-arena.legacyRanger', 'NO',
               '-arena.recordingGate', 'YES', '-arena.captureTraversal', 'YES' if traversal else 'NO')
        deadline = time.monotonic() + 120
        while not ready.exists():
            if time.monotonic() >= deadline:
                raise RuntimeError('Scene did not become ready before recording')
            time.sleep(0.5)
        diagnostic['phase'] = 'scene-ready-at-time-zero'
        save_diagnostic()
    except Exception as error:
        diagnostic.update(phase='launch-failed', error=str(error))
        save_diagnostic()
        try:
            simctl('io', device, 'screenshot', str(output / (stem + '-launch-failure.png')), timeout=20)
        except Exception:
            pass
        raise
    with (output / (stem + '.recorder.log')).open('w') as recorder_log:
        recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo',
                                     '--codec=h264', str(path)], stdout=recorder_log,
                                     stderr=subprocess.STDOUT, start_new_session=True)
    evidence = None
    try:
        time.sleep(1)
        if recorder.poll() is not None:
            raise RuntimeError('Video recorder exited before simulation start')
        start.write_text('start')
        deadline = time.monotonic() + (240 if traversal else 120)
        while time.monotonic() < deadline:
            if recorder.poll() is not None:
                raise RuntimeError('Video recorder exited during capture')
            if marker.exists():
                evidence = json.loads(marker.read_text())
                if duration <= evidence.get('simulationTime', -1) < duration + 0.04:
                    break
            time.sleep(0.5)
        else:
            raise RuntimeError('No verified end frame for recorded fixture')
        assert evidence.get('map') == 'twin_gates_sample_v1', evidence
        assert evidence.get('rangerAsset') == 'Ranger_FaceSample.glb', evidence
        assert evidence.get('qualitySample') is True, evidence
        if traversal:
            validate_traversal(evidence)
        diagnostic.update(phase='scene-verified', sceneEvidence=evidence)
        save_diagnostic()
        time.sleep(1)
    finally:
        if recorder.poll() is None:
            # Signal only our isolated recording process group, including xcrun children.
            diagnostic.update(phase='finalizing', stopMonotonicSeconds=time.monotonic())
            save_diagnostic()
            os.killpg(recorder.pid, signal.SIGINT)
            try:
                recorder.wait(timeout=90)
            except subprocess.TimeoutExpired:
                os.killpg(recorder.pid, signal.SIGKILL)
                recorder.wait(timeout=10)
                diagnostic.update(phase='finalization-timeout', recorderReturncode=recorder.returncode)
                save_diagnostic()
                raise RuntimeError('Video finalization timed out')
    if recorder.returncode or not path.exists() or path.stat().st_size < 1024:
        diagnostic.update(phase='recorder-failed', recorderReturncode=recorder.returncode)
        save_diagnostic()
        raise RuntimeError('Video output missing or recorder failed')
    diagnostic.update(phase='finalized', mediaFinalized=True, recorderReturncode=recorder.returncode)
    save_diagnostic()
    evidence.update(sourceCommit=os.environ.get('GITHUB_SHA'),
                    capture='simulator-wall-grass-route' if traversal else 'simulator-opening-six-seconds',
                    limitations=['Includes launch and final frozen frame',
                                 'No box route coverage' if traversal else 'Not wall/box/grass route coverage',
                                 'No physical-device FPS, thermal or audio-sync validation'])
    (output / (stem + '.json')).write_text(json.dumps(evidence, indent=2) + '\n')
    print('Verified continuous capture:', path, flush=True)


if __name__ == '__main__':
    main()

