"""Verify one real universal device archive; do not sign or upload."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

from completion_active_pack import inspect

IDENTIFIER = "com.kriswu.shiftreminder"
VERSION = "1.2"
RELEASE = "527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3"
ACTIVE_DIGEST = "68518f4887200da348b97535a76b6f3b88e3ef7943a1022993a4b6f20c1618fb"
FORBIDDEN = {"DuelPadPracticeTrace.swift", "rift-pad-practice-stages.log", "Validation_D13_Bottle_Source_Oracle.json", "Liu_Legion_Hammers.glb"}

def require(ok, code):
    if not ok:
        raise ValueError(code)

def load_plist(p):
    return plistlib.loads(p.read_bytes())

def verify(root, archive, build, team):
    require(re.fullmatch(r"[1-9][0-9]{0,8}", build), "build-number")
    require(re.fullmatch(r"[A-Z0-9]{10}", team), "signing-team")
    relative = Path("Applications/ShiftReminder.app")
    app = archive / "Products" / relative
    info = load_plist(app / "Info.plist")
    archive_info = load_plist(archive / "Info.plist")["ApplicationProperties"]
    require(archive_info.get("ApplicationPath") == str(relative), "archive-product")
    require(info.get("CFBundleIdentifier") == IDENTIFIER, "bundle-id")
    require(info.get("CFBundleVersion") == build and info.get("CFBundleShortVersionString") == VERSION, "version")
    require(set(info.get("UIDeviceFamily", [])) == {1, 2}, "universal-device-families")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "archive-platform")
    require(info.get("FighterAssetReleaseSHA256") == RELEASE and not info.get("FighterXuXiaoProfileSHA256"), "release-profile")
    app_pack = inspect(root, app=app)
    require(app_pack["requiredFiles"] == 539 and app_pack["requiredBytes"] == 299625928 and app_pack["compiledContentSHA256"] == ACTIVE_DIGEST, "pack-identity")
    scanned = 0
    for _, dirs, files in os.walk(app, followlinks=False):
        for name in dirs + files:
            scanned += 1
            require(scanned < 25000 and name not in FORBIDDEN and not name.lower().endswith((".xctest", ".xctestrun", ".p8", ".p12", ".pem")), "archive-unapproved-entry")
    require(subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], capture_output=True).returncode == 0, "archive-signature")
    p = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True)
    require(p.returncode == 0, "entitlements-read")
    e = plistlib.loads(p.stdout)
    require(e.get("com.apple.developer.team-identifier") == team and e.get("application-identifier") == team + "." + IDENTIFIER and e.get("com.apple.developer.game-center") is True, "archive-entitlements")
    executable = info.get("CFBundleExecutable")
    require(executable == "ShiftReminder", "executable-name")
    require((app / "FighterNetworkRules.json").is_file(), "game-network-rules")
    with (app / executable).open("rb") as f:
        binary = hashlib.file_digest(f, "sha256").hexdigest()
    return {"signedDeviceArchive": True,"build": build,"version": VERSION,"deviceFamilies": [1,2],
            "verifiedResourceFiles": 539,"resourceContentSHA256": ACTIVE_DIGEST,
            "executableSHA256": binary,"uploadPerformed": False}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("root", type=Path)
    p.add_argument("archive", type=Path)
    p.add_argument("build")
    a = p.parse_args()
    try:
        print(json.dumps(verify(a.root, a.archive, a.build, os.environ["APPLE_TEAM_ID"])))
    except Exception as error:
        safe = str(error) if type(error) is ValueError and re.fullmatch(r"[a-z-]{1,50}", str(error)) else type(error).__name__
        print(json.dumps({"signedDeviceArchive": False, "reason": safe, "uploadPerformed": False}))
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
