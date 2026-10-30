#!/usr/bin/env python3
"""One real UI test and one continuous simulator recording, without retiming."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

def actual_test_duration(log, test):
    matches = re.findall(r"Test Case '-\[ArenaFlowTests\.ArenaFlowTests " + re.escape(test)
                         + r"\]' (?:passed|failed) \(([0-9.]+) seconds\)\.", log)
    if len(matches) != 1 or float(matches[0]) <= 0:
        raise ValueError('Missing unambiguous actual XCTest duration')
    return float(matches[0])


def main():
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
        ready_deadline = time.monotonic() + 45
        while 'Recording started' not in (out / 'recorder.log').read_text(errors='replace'):
            if recorder.poll() is not None:
                raise RuntimeError('Recorder exited before UI test')
            if time.monotonic() >= ready_deadline:
                raise RuntimeError('Recorder did not report readiness')
            time.sleep(0.2)
        meta['recordingReadyBeforeTestCommand'] = True
        started = time.monotonic()
        with open('sample-flow.log', 'w') as log:
            result = subprocess.run(['xcodebuild', 'test-without-building', '-project', 'ShiftReminder.xcodeproj',
                '-scheme', 'ArenaFlow', '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={device}',
                '-derivedDataPath', 'sample-build', '-resultBundlePath', 'sample-flow.xcresult',
                '-parallel-testing-enabled', 'NO', f'-only-testing:ArenaFlowTests/ArenaFlowTests/{test}',
                'CODE_SIGNING_ALLOWED=NO'], stdout=log, stderr=subprocess.STDOUT, timeout=720)
        meta.update(xcodeCommandSeconds=time.monotonic()-started, testExit=result.returncode)
        # The command also includes test-runner installation and post-test xcresult
        # processing. Require coverage of the actual XCTest, not those inactive periods.
        meta['testSeconds'] = actual_test_duration(Path('sample-flow.log').read_text(errors='replace'), test)
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
    return status


if __name__ == "__main__":
    raise SystemExit(main())
