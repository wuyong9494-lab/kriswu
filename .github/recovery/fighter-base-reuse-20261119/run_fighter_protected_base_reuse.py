#!/usr/bin/env python3
"""Recover pinned old resource bytes in a protected runner and print only a receipt."""
import argparse
import base64
import importlib
import json
import os
from pathlib import Path
import platform
import stat
import sys
import tempfile

from verify_fighter_protected_base_reuse import (
    HISTORICAL_HELPER, HISTORICAL_HELPER_SHA, historical_inventory, run as report_reuse,
)
from completion_native_preflight import snapshot

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "GITHUB_ACTIONS": "true",
    "GITHUB_REPOSITORY": "wuyong9494-lab/kriswu",
    "GITHUB_REF": "refs/heads/codex/fighter-visual-acceptance-20261113-1200",
    "GITHUB_EVENT_NAME": "push",
    "GITHUB_RUN_ATTEMPT": "1",
}
SECRET = "FIGHTER_H17_D19_KEY"


def inputs():
    historical_inventory(ROOT)
    snapshot(ROOT / HISTORICAL_HELPER, maximum=128_000, sha256=HISTORICAL_HELPER_SHA)
    sys.path.insert(0, str(ROOT / ".github/scripts"))
    legacy_recovery = importlib.import_module("fighter_base_recovery")
    if Path(legacy_recovery.__file__).resolve() != ROOT / HISTORICAL_HELPER:
        raise ValueError("historical-helper-path")
    for relative, sha in {**legacy_recovery.MANIFESTS, **legacy_recovery.SOURCE_FILES}.items():
        snapshot(ROOT / relative, maximum=2_100_000, sha256=sha)
    sys.path.insert(0, str(ROOT / "scripts"))
    legacy = importlib.import_module("fighter_h17_d19_native")
    shared = importlib.import_module("fighter_shared_root_native")
    for name, module in (("fighter_h17_d19_native", legacy), ("fighter_shared_root_native", shared)):
        if Path(module.__file__).resolve() != ROOT / ".github/scripts" / (name + ".py"):
            raise ValueError("historical-source-path")
    a = ROOT / ".github/private/fighter-h17-d19"
    b = ROOT / ".github/private/fighter-h17-shared-root"
    baseline = legacy.validate_release_manifest(json.loads((a/"manifest.json").read_bytes()))
    overlay = json.loads((b/"manifest.json").read_bytes())
    if len(baseline["files"]) != 295 or len(overlay["targetFiles"]) != 13:
        raise ValueError("historical-count")
    return legacy_recovery, legacy, shared, a, b, baseline, overlay


def recover():
    if platform.system() != "Darwin" or any(os.environ.get(k) != v for k, v in EXPECTED.items()):
        raise ValueError("requires-dedicated-protected-macos-runner")
    key = os.environ.pop(SECRET, "")
    if len(key) != 44 or len(base64.b64decode(key, validate=True)) != 32 or base64.b64encode(base64.b64decode(key, validate=True)).decode() != key:
        raise ValueError("protected-resource-key-missing-or-malformed")
    legacy_recovery, legacy, shared, a, b, baseline, overlay = inputs()
    runner_temp = Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="fighter-read-private-", dir=runner_temp) as scratch:
        root = Path(scratch)
        if stat.S_IMODE(root.stat().st_mode) != 0o700:
            raise ValueError("private-scratch-mode")
        cipher, clear, delta_clear, swift = (root / n for n in ("base.enc","base.zip","delta.zip","decrypt.swift"))
        legacy.assemble_cipher(baseline, a, cipher)
        row = overlay["cipher"]
        delta = b / row["name"]
        snapshot(delta, maximum=8_389_000, size=row["bytes"], sha256=row["sha256"])
        legacy_recovery.write_new(swift, shared.GCM_SWIFT.encode())
        legacy_recovery.run(["swift", str(swift), str(cipher), str(clear), str(delta), str(delta_clear)],
                            extra_env={SECRET:key})
        key = ""
        restored = root / "restored"
        legacy.overlay_zip(legacy_recovery.raw_file(clear, 128*1024**2), baseline, restored)
        manifest, payloads = shared.decode_delta(legacy_recovery.raw_file(delta_clear, 8*1024**2), overlay)
        shared.reconstruct_delta(manifest, payloads, restored, baseline)
        return report_reuse(ROOT, restored)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--preflight", action="store_true")
    args = p.parse_args()
    try:
        if args.preflight:
            inputs()
            print(json.dumps({"historicalInputsPinned": True, "decryptionPerformed": False}))
        else:
            print(json.dumps(recover(), indent=2))
    except Exception as exc:
        # Do not surface underlying subprocess output, environment or filenames.
        if isinstance(exc, ValueError) and str(exc) in {
            "requires-dedicated-protected-macos-runner", "protected-resource-key-missing-or-malformed"
        }:
            print(str(exc), file=sys.stderr)
        else:
            print("Pinned base recovery or verification failed (" + type(exc).__name__ + ").", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
