#!/usr/bin/env python3
"""Compile the current app once and test only the new native D13 audio path.

Reuse the verified simulator/build lifecycle. Previously successful display and
network suites are deliberately not selected again. No private files or signing.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

import fighter_display_network_native as native

EXPECTED_MESSAGE = "Bind serpent match audio and recovered character sources 20261116"
native.WORK = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "fighter-character-audio-20261116"


def selectors():
    source = native.ROOT / "Tests/SiteTests/DuelSerpentAudioPlaybackTests.swift"
    methods = re.findall(r"^    func (test\w+)\(", source.read_text(), re.M)
    if len(methods) != 6 or len(set(methods)) != 6:
        raise RuntimeError("Expected all six new audio lifecycle methods")
    return ["SiteTests/DuelSerpentAudioPlaybackTests/" + name for name in methods]


native.selectors = selectors


def prepare():
    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        raise RuntimeError("Only the reviewed source push can start this run")
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    if event.get("head_commit", {}).get("message") != EXPECTED_MESSAGE:
        raise RuntimeError("Unexpected commit message")
    native.prepare()


def export():
    result = native.WORK / "result.xcresult"
    if not result.exists():
        raise RuntimeError("No native results; build/preparation cannot count as passing tests")
    raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(result), "--format", "json"], text=True)
    (native.WORK / "test-summary.json").write_text(raw)
    summary = json.loads(raw)
    if summary.get("totalTestCount") != 6 or summary.get("passedTests") != 6 or \
            summary.get("failedTests") != 0 or summary.get("skippedTests") != 0:
        raise RuntimeError("All six new native tests must pass without skips: " + raw)
    print("6 native audio lifecycle tests passed. Synthetic players; no private media or physical-device acceptance.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("prepare", "build", "simulator", "test", "export", "cleanup"))
    phase = parser.parse_args().phase
    if phase in ("prepare", "export"):
        globals()[phase]()
    else:
        getattr(native, phase)()
