#!/usr/bin/env python3
"""Build a public-source-only fighter identity from the current checkout, not Git HEAD.

No network, assets, arbitrary environment values, absolute paths, timestamps or
Git metadata are put in the manifest. Run on every main-app build, before code signing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
from pathlib import Path

SCHEMA_VERSION = 1
RECIPE = "fighter-network-rules-v1"
PATTERNS = ("Sources/ShiftCore/**/*.swift", "App/**/*.swift", "Shared/**/*.swift")
HELPERS = (
    "project.yml",
    "App/Info.plist",
    "Shared/CaptureIntents.swift", "Shared/DutyActivity.swift", "Shared/WidgetShared.swift",
    "Sources/ShiftCore/BoneSampler.swift",
    "App/Services/GLTFModel.swift",
    "App/Services/ArenaOpaquePNG.swift",
    "App/Services/GameRoom.swift",
    "App/Services/GameRoomDirectIdentity.swift",
)
# Fail a partial/wrong checkout rather than emitting a plausible empty identity.
REQUIRED = HELPERS + (
    "Sources/ShiftCore/DuelGame.swift",
    "Sources/ShiftCore/DuelWeaponMotion.swift",
    "Sources/ShiftCore/DuelWeaponFight.swift",
    "Sources/ShiftCore/DuelWeaponThrow.swift",
    "Sources/ShiftCore/DuelFighterAssetRelease.swift",
    "Sources/ShiftCore/DuelCombatRules.swift",
    "Sources/ShiftCore/DuelImpactMotion.swift",
    "Sources/ShiftCore/DuelPanguRules.swift",
    "Sources/ShiftCore/DuelPanguState.swift",
    "Sources/ShiftCore/DuelPanguSpatialState.swift",
    "Sources/ShiftCore/DuelPanguPresentation.swift",
    "Sources/ShiftCore/DuelWeaponInput.swift",
    "Sources/ShiftCore/DuelMultiplayerSelection.swift",
    "Sources/ShiftCore/DuelMultiplayerReplica.swift",
    "Sources/ShiftCore/DuelNetworkStartBarrier.swift",
    "Sources/ShiftCore/DuelNetworkInputs.swift",
    "Sources/ShiftCore/DuelNetworkCombatProtocol.swift",
    "Sources/ShiftCore/DuelNetworkCombatState.swift",
    "Sources/ShiftCore/DuelNetworkCombatWire.swift",
    "Sources/ShiftCore/DuelNetworkHostSimulation.swift",
    "Sources/ShiftCore/DuelNetworkReplay.swift",
    "Sources/ShiftCore/DuelReplayState.swift",
    "App/Services/DuelNetworkCompatibilityIdentity.swift",
    "App/Services/DuelNetworkLobby.swift",
    "App/Services/DuelNetworkMessageRouter.swift",
    "App/Services/DuelWeaponAssets.swift",
    "App/Services/DuelFighterAssetReleaseLoader.swift",
    "App/Services/DuelSourceEffects.swift",
    "App/Services/DuelWeaponEffects.swift",
    "App/Services/DuelPanguDiagnostics.swift",
    "App/Services/DuelSourceWeaponTrails.swift",
    "App/Services/DuelStage.swift",
    "App/Views/DuelSourceControls.swift",
    "App/Views/DuelNetworkSelectionModel.swift",
    "App/Views/DuelNetworkRoomView.swift",
    "App/Views/DuelView.swift",
    "App/Views/DuelPanguHUD.swift",
    "App/Views/DuelWorld.swift",
)
MAX_SOURCE_BYTES = 8_000_000
MAX_FILES = 1024
BUILD_ENVIRONMENT = (
    "TARGET_NAME", "CONFIGURATION", "PLATFORM_NAME", "SDK_VERSION", "SWIFT_VERSION",
    "XCODE_VERSION_ACTUAL", "IPHONEOS_DEPLOYMENT_TARGET", "SWIFT_OPTIMIZATION_LEVEL",
    "SWIFT_COMPILATION_MODE", "ENABLE_TESTABILITY", "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
    "FIGHTER_ASSET_RELEASE_SHA256",
)
REQUIRED_BUILD_ENVIRONMENT = BUILD_ENVIRONMENT[:7]


def xcode_build_context(environment: dict) -> dict:
    context = {"mode": "xcode"}
    for key in BUILD_ENVIRONMENT:
        value = environment.get(key, "")
        if key == "FIGHTER_ASSET_RELEASE_SHA256" and value and re.fullmatch(r"[0-9a-f]{64}", value) is None:
            raise ValueError("Invalid fighter asset release pin")
        if len(value) > 256 or re.fullmatch(r"[A-Za-z0-9_.+ =()$-]*", value) is None:
            raise ValueError("Unsafe or unsupported build setting: " + key)
        if key in REQUIRED_BUILD_ENVIRONMENT and not value:
            raise ValueError("Missing Xcode build setting: " + key)
        context[key] = value
    if context["TARGET_NAME"] != "ShiftReminder":
        raise ValueError("Rules manifest hook must run only for the main app")
    return context


def framed(value: str) -> bytes:
    data = value.encode("utf-8")
    return str(len(data)).encode("ascii") + b":" + data


def fingerprint(files: list[dict], build: dict | None = None) -> str:
    """Shared with the Swift reader; ordering is part of the validated format."""
    canonical = bytearray((RECIPE + "\n").encode("ascii"))
    build = build or {}
    canonical.extend(framed(str(len(build))))
    for key in sorted(build):
        canonical.extend(framed(key))
        canonical.extend(framed(build[key]))
    canonical.extend(framed(str(len(files))))
    for item in files:
        for field in (item["path"], str(item["bytes"]), item["sha256"]):
            canonical.extend(framed(field))
    return hashlib.sha256(canonical).hexdigest()


def build_manifest(root: Path, build: dict | None = None) -> dict:
    root = root.resolve(strict=True)
    build = build if build is not None else {"mode": "source-only"}
    paths = set(HELPERS)
    # Recursive globs do not follow directory symlinks consistently across Python
    # versions. Reject them rather than silently omitting possible Swift sources.
    for directory in ("App", "Sources/ShiftCore", "Shared"):
        for base, folders, _ in os.walk(root / directory, followlinks=False):
            for folder in folders:
                candidate = Path(base) / folder
                if candidate.is_symlink():
                    raise ValueError("Symlinked source directory: " + candidate.relative_to(root).as_posix())
    for pattern in PATTERNS:
        paths.update(path.relative_to(root).as_posix() for path in root.glob(pattern))
    missing = sorted(set(REQUIRED) - paths)
    if missing:
        raise ValueError("Missing required fighter sources: " + ", ".join(missing))
    if not 1 <= len(paths) <= MAX_FILES:
        raise ValueError("Invalid fighter source count")
    files = []
    for relative in sorted(paths):
        path = root / relative
        # Refuse symlinked files AND directories, including a path escaping root.
        if re.fullmatch(r"[A-Za-z0-9_./+-]+", relative) is None or ".." in relative:
            raise ValueError("Unsupported source path: " + relative)
        if path.resolve(strict=True) != path or not path.is_file():
            raise ValueError("Expected regular, non-symlink source: " + relative)
        size = path.stat().st_size
        if not 1 <= size <= MAX_SOURCE_BYTES:
            raise ValueError("Invalid fighter source size: " + relative)
        data = path.read_bytes()
        if len(data) != size:
            raise ValueError("Source changed while reading: " + relative)
        files.append({"path": relative, "bytes": size, "sha256": hashlib.sha256(data).hexdigest()})
    return {"schemaVersion": SCHEMA_VERSION, "recipe": RECIPE, "build": build,
            "files": files, "fingerprint": fingerprint(files, build)}


def write_manifest(root: Path, output: Path, build: dict | None = None) -> dict:
    manifest = build_manifest(root, build)
    encoded = (json.dumps(manifest, ensure_ascii=True, sort_keys=True, indent=2) + "\n").encode("ascii")
    if len(encoded) > 262_144:
        raise ValueError("Rules manifest exceeds runtime size limit")
    if not output.parent.is_dir():
        output.parent.mkdir(parents=True, exist_ok=True)
    # A fixed, declared sibling avoids undeclared random writes under Xcode's
    # user-script sandbox. Each product's build phase is serialized by Xcode.
    # Refuse symlinks/non-files; a leftover regular scratch file from an interrupted
    # build is safe to replace. A sibling keeps os.replace on the same filesystem.
    temporary = output.with_name("." + output.name + ".tmp")
    if temporary.is_symlink() or (temporary.exists() and not temporary.is_file()):
        raise ValueError("Atomic scratch path must be a regular file")
    # Atomic replacement prevents partial output. Retain mtime only when identical,
    # but do not leave an interrupted scratch resource inside the signed bundle.
    if (output.is_file() and not output.is_symlink()
            and stat.S_IMODE(output.stat().st_mode) == 0o644 and output.read_bytes() == encoded):
        if temporary.exists():
            temporary.unlink()
        return manifest
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            os.fchmod(handle.fileno(), 0o644)
            handle.write(encoded)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xcode-build", action="store_true", help="Require and bind allowlisted Xcode settings")
    args = parser.parse_args()
    try:
        manifest = write_manifest(args.source_root, args.output, xcode_build_context(os.environ) if args.xcode_build else None)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Fighter rules manifest failed: {error}\n")
    print(f"Fighter rules: {len(manifest['files'])} public source files, {manifest['fingerprint']}")


if __name__ == "__main__":
    main()
