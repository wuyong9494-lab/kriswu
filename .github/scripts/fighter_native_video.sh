#!/usr/bin/env bash
# Keep the recorder isolated from xcodebuild and retain the test's exit status.
# Video, recorder diagnostics and provenance stay inside the encrypted evidence tree.
set -euo pipefail
exec python3 - "$@" <<'PY'
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

if len(sys.argv) < 4 or sys.argv[2] != "--":
    sys.exit("Usage: fighter_native_video.sh DEVICE -- xcodebuild [arguments...]")

device, command = sys.argv[1], sys.argv[3:]
os.umask(0o077)
output = Path("fighter-evidence/native-motion")
output.mkdir(parents=True, exist_ok=True)
video = output / "arena-flow.mp4"
log_path = output / "recorder.log"
metadata_path = output / "provenance.json"
if video.exists() or metadata_path.exists():
    sys.exit("Refusing to reuse existing native-motion evidence")

# Apple's Simulator documentation uses recordVideo and Control-C to finalize it:
# https://developer.apple.com/videos/play/wwdc2020/10647/ (H.264 example)
record_command = ["xcrun", "simctl", "io", device, "recordVideo", "--codec", "h264", str(video)]
metadata = {
    "sourceCommit": os.environ.get("GITHUB_SHA"),
    "githubRunID": os.environ.get("GITHUB_RUN_ID"),
    "githubRunAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    "deviceUDID": device,
    "recordCommand": record_command,
    "testCommand": command,
    "testScope": "Existing ArenaFlowTests/DuelFlowTests (two UI tests, unchanged selectors)",
    "geometrySource": "Original MP4 stream, including Simulator orientation changes; no rotation or crop applied",
    "timeSource": "Host UTC clock for wall times; original MP4 for media timestamps",
    "recordingComplete": False,
    "testExitCode": None,
    "recorderReturncode": None,
    "videoFile": video.name,
    "videoBytes": 0,
    "videoSHA256": None,
    "errors": [],
    "limitations": "Raw Simulator screen capture; no retiming, source-action FPS or physical-device FPS claim. Media inspection is still required.",
}
recorder = runner = None
interrupted = None
ready = False
premature_exit = False


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def checkpoint():
    try:
        temporary = metadata_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(metadata, indent=2) + "\n")
        temporary.replace(metadata_path)
    except OSError as error:
        # A full disk must not prevent recorder cleanup or override test failure.
        message = "Could not save provenance: " + str(error)
        if message not in metadata["errors"]:
            metadata["errors"].append(message)
            print("::error::Native simulator recording: " + message, flush=True)
        metadata["recordingComplete"] = False


def fail_recording(message):
    metadata["errors"].append(message)
    print("::error::Native simulator recording: " + message, flush=True)
    checkpoint()


def receive_signal(signum, _frame):
    global interrupted
    if interrupted is None:
        interrupted = signum


def signal_group(process, signum):
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass


def stop(process, label, flush_seconds):
    if process is None or process.poll() is not None:
        return
    # SIGINT is recordVideo's normal stop. TERM/KILL are bounded failure cleanup,
    # addressed only to the process group created by this invocation.
    signal_group(process, signal.SIGINT)
    for seconds, escalation in ((flush_seconds, signal.SIGTERM), (5, signal.SIGKILL)):
        try:
            process.wait(timeout=seconds)
            return
        except subprocess.TimeoutExpired:
            fail_recording(label + " did not stop in time; escalating cleanup")
            signal_group(process, escalation)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        fail_recording(label + " could not be reaped after SIGKILL")


def shell_status(returncode):
    return returncode if returncode >= 0 else 128 - returncode


signal.signal(signal.SIGINT, receive_signal)
signal.signal(signal.SIGTERM, receive_signal)
metadata["startedAtUTC"] = timestamp()
checkpoint()  # A killed runner must leave incomplete, never stale-success, metadata.
try:
    try:
        with log_path.open("w") as log:
            recorder = subprocess.Popen(record_command, stdout=log, stderr=subprocess.STDOUT,
                                        start_new_session=True)
        deadline = time.monotonic() + 20
        while not interrupted:
            if recorder.poll() is not None:
                fail_recording("Recorder exited before reporting readiness")
                break
            if "Recording started" in log_path.read_text(errors="replace"):
                ready = True
                metadata["recordingReadyAtUTC"] = timestamp()
                checkpoint()
                break
            if time.monotonic() >= deadline:
                fail_recording("Recorder did not report readiness within 20 seconds")
                break
            time.sleep(0.2)
    except OSError as error:
        fail_recording("Could not start recorder: " + str(error))

    # A recording failure must not hide or skip the existing UI test result.
    if not interrupted:
        metadata["testStartedAtUTC"] = timestamp()
        checkpoint()
        try:
            runner = subprocess.Popen(command, start_new_session=True)
            while runner.poll() is None and not interrupted:
                if ready and recorder.poll() is not None and not premature_exit:
                    premature_exit = True
                    fail_recording("Recorder exited while the UI tests were still running")
                time.sleep(0.2)
            if runner.returncode is not None:
                metadata["testExitCode"] = shell_status(runner.returncode)
        except OSError as error:
            metadata["testExitCode"] = 127
            fail_recording("Could not start UI tests: " + str(error))
        checkpoint()
finally:
    if interrupted:
        metadata["interruptedBySignal"] = interrupted
        fail_recording("Capture interrupted by signal " + str(interrupted))
    # On cancellation, stop the test process group too; no orphan xcodebuild.
    stop(runner, "UI test process", 5)
    if runner is not None:
        metadata["testFinishedAtUTC"] = timestamp()
        if runner.returncode is not None:
            metadata["testExitCode"] = shell_status(runner.returncode)
    if ready and recorder.poll() is not None and not premature_exit:
        fail_recording("Recorder exited before the requested stop")
    metadata["stopRequestedAtUTC"] = timestamp()
    checkpoint()
    stop(recorder, "Recorder finalization", 30)
    metadata["finishedAtUTC"] = timestamp()
    if recorder is not None:
        metadata["recorderReturncode"] = recorder.returncode
        if recorder.returncode != 0:
            fail_recording("Recorder did not finalize successfully")
    try:
        if video.is_file():
            metadata["videoBytes"] = video.stat().st_size
            digest = hashlib.sha256()
            with video.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            metadata["videoSHA256"] = digest.hexdigest()
    except OSError as error:
        fail_recording("Could not inspect recorded file: " + str(error))
    if metadata["videoBytes"] == 0:
        fail_recording("Recorder produced no nonempty video file")
    if interrupted and "interruptedBySignal" not in metadata:
        metadata["interruptedBySignal"] = interrupted
        fail_recording("Capture interrupted by signal " + str(interrupted))
    metadata["recordingComplete"] = ready and not metadata["errors"]
    checkpoint()

# Preserve xcodebuild's failure even if the recorder also failed. A successful
# XCTest run cannot make a missing, interrupted or unflushed recording pass.
status = metadata["testExitCode"]
if not status:
    status = (128 + interrupted) if interrupted else (0 if metadata["recordingComplete"] else 1)
print("Native motion capture complete=" + str(metadata["recordingComplete"])
      + "; UI test exit=" + str(metadata["testExitCode"]), flush=True)
sys.exit(status)
PY
