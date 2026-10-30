#!/usr/bin/env python3
"""One real UI test and one continuous simulator recording, without retiming."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

hero, test = sys.argv[1:]
device = os.environ['SAMPLE_DEVICE']
out = Path('sample-shots/flow'); out.mkdir(parents=True, exist_ok=True)
video = out / f'hero-{hero}-continuous.mp4'
meta = dict(hero=int(hero), sourceCommit=os.environ.get('GITHUB_SHA'), complete=False)
status = 1
with (out / 'recorder.log').open('w') as log:
    recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(video)],
                                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
try:
    time.sleep(1)
    if recorder.poll() is not None:
        raise RuntimeError('Recorder exited before UI test')
    started = time.monotonic()
    with open('sample-flow.log', 'w') as log:
        result = subprocess.run(['xcodebuild', 'test-without-building', '-project', 'ShiftReminder.xcodeproj',
            '-scheme', 'ArenaFlow', '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={device}',
            '-derivedDataPath', 'sample-build', '-resultBundlePath', 'sample-flow.xcresult',
            '-parallel-testing-enabled', 'NO', f'-only-testing:ArenaFlowTests/ArenaFlowTests/{test}',
            'CODE_SIGNING_ALLOWED=NO'], stdout=log, stderr=subprocess.STDOUT, timeout=720)
    meta.update(testSeconds=time.monotonic()-started, testExit=result.returncode)
    status = result.returncode
    if recorder.poll() is not None:
        raise RuntimeError('Continuous recorder stopped before UI test ended')
    meta['complete'] = result.returncode == 0
except Exception as error:
    meta['error'] = str(error)
    status = 1
finally:
    if recorder.poll() is None:
        os.killpg(recorder.pid, signal.SIGINT)
        try:
            recorder.wait(timeout=90)
        except subprocess.TimeoutExpired:
            os.killpg(recorder.pid, signal.SIGKILL); recorder.wait(timeout=10)
            meta['error'] = 'Recorder finalization timed out'; status = 1
    meta['recorderExit'] = recorder.returncode
    if recorder.returncode: status = 1
    (out / 'recording-session.json').write_text(json.dumps(meta, indent=2)+'\n')
print(json.dumps(meta))
log = Path('sample-flow.log')
if log.exists():
    for line in log.read_text(errors='replace').splitlines():
        if 'error:' in line or ('Test Case' in line and ('passed' in line or 'failed' in line)): print(line)
raise SystemExit(status)
