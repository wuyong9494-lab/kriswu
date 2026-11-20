"""Verify the device archive of the qualified Xu replacement-practice build."""
import argparse
import hashlib
import json
import mmap
import os
from pathlib import Path
import plistlib
import re
import subprocess

import build_fighter_network_rules as rules
from completion_active_pack import inspect
import verify_candidate_archive as archive_checks
from verify_xuxiao_qualified_ui import (
    BUNDLE, FROZEN_BASE, RELEASE_SHA256, XU_SHIPPING_PATCH_SHA256,
    unique_pairs, verify_xu_source,
)

QUALIFIED_SHA = "0e99b81aad2822aaf903b07fc82f073873bb43d8"
QUALIFIED_RUN = 44710202035
APP_GROUP = "group.com.kriswu.shiftreminder"
ENTRY_IDENTIFIERS = (
    b"games.xuxiao.practice.enter",
    b"xuxiao.practice.right",
    b"xuxiao.practice.title",
)


def require(ok, stage):
    if not ok:
        raise ValueError(stage)


def signed_entitlements(bundle, identifier, team):
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(bundle)],
                   capture_output=True, check=True)
    result = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)],
                            capture_output=True, check=True)
    entitlements = plistlib.loads(result.stdout)
    require(entitlements.get("com.apple.developer.team-identifier") == team and
            entitlements.get("application-identifier") == f"{team}.{identifier}" and
            APP_GROUP in entitlements.get("com.apple.security.application-groups", []),
            "signed-app-group-identity")
    return entitlements


def verify_widget(app, version, build, team):
    expected_id = BUNDLE + ".widget"
    widgets = list((app / "PlugIns").glob("*.appex"))
    require(len(widgets) == 1 and widgets[0].name == "ShiftWidget.appex" and
            not widgets[0].is_symlink(), "embedded-widget")
    widget = widgets[0]
    info = plistlib.loads((widget / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == expected_id and
            info.get("CFBundleShortVersionString") == version and info.get("CFBundleVersion") == build and
            info.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension" and
            info.get("CFBundleExecutable") == "ShiftWidget" and (widget / "ShiftWidget").is_file(),
            "widget-bundle-identity")
    signed_entitlements(widget, expected_id, team)
    return expected_id


def verify_compiled_context(root, app):
    path = app / "FighterNetworkRules.json"
    require(not path.is_symlink() and 0 < path.stat().st_size <= 262144, "network-rules-file")
    data = path.read_bytes()
    manifest = json.loads(data, object_pairs_hook=unique_pairs)
    context = manifest["build"]
    require(context.get("PLATFORM_NAME") == "iphoneos" and
            context.get("CONFIGURATION") == "Release" and
            context.get("FIGHTER_ASSET_RELEASE_SHA256") == RELEASE_SHA256 and
            context.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split() == ["L12_INTERNAL_PREVIEW"],
            "device-preview-compile-settings")
    require(context == rules.xcode_build_context(context) and
            manifest == rules.build_manifest(root, context), "compiled-source-identity")
    return hashlib.sha256(data).hexdigest()


def verify(root, archive, build, team):
    root = root.resolve(strict=True)
    base = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    require(base == FROZEN_BASE, "source-base")
    # The ordinary Today -> Quick Actions -> Games route comes from this
    # frozen base. GamesHomeView's exact digest covers its Xu entry.
    subprocess.run(["git", "-C", str(root), "diff", "--quiet", "HEAD", "--",
                    "App/Views/TodayView.swift", "App/ShiftApp.swift"], check=True)
    source_hashes = verify_xu_source(root)
    staged = inspect(root, staged=root / "App/Resources/FighterPrivate")
    receipt = archive_checks.verify(root, archive, build, team)
    require(staged["requiredFiles"] == receipt["verifiedResourceFiles"] and
            staged["compiledContentSHA256"] == receipt["resourceContentSHA256"], "staged-resource-identity")
    app = archive / "Products/Applications/ShiftReminder.app"
    signed_entitlements(app, BUNDLE, team)
    widget_id = verify_widget(app, receipt["version"], build, team)
    network_sha = verify_compiled_context(root, app)
    # These identifiers exceed Swift's inline-string size. Require bytes from
    # the executable itself, separately from the source-hash manifest.
    with (app / "ShiftReminder").open("rb") as binary:
        with mmap.mmap(binary.fileno(), 0, access=mmap.ACCESS_READ) as contents:
            require(all(contents.find(marker) >= 0 for marker in ENTRY_IDENTIFIERS), "xu-entry-in-executable")
    return {
        **receipt, "bundleID": BUNDLE, "widgetBundleID": widget_id, "frozenBaseSHA": base,
        "qualificationSHA": QUALIFIED_SHA, "qualificationRunID": QUALIFIED_RUN,
        "xuShippingPatchSHA256": XU_SHIPPING_PATCH_SHA256, "xuRuntimeSourceSHA256": source_hashes,
        "assetReleaseSHA256": RELEASE_SHA256, "deviceNetworkRulesSHA256": network_sha,
        "deviceCompileCondition": "L12_INTERNAL_PREVIEW", "verifiedEntryMarkers": len(ENTRY_IDENTIFIERS),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("archive", type=Path)
    parser.add_argument("build")
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.root, args.archive, args.build, os.environ["APPLE_TEAM_ID"]), sort_keys=True))
    except Exception as exc:
        stage = str(exc) if type(exc) is ValueError and re.fullmatch(r"[a-z0-9-]{1,80}", str(exc)) else type(exc).__name__
        print(json.dumps({"signedDeviceArchive": False, "reason": stage, "uploadPerformed": False}))
        raise SystemExit(1)
