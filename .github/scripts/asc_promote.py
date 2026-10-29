#!/usr/bin/env python3
"""Promote an exact, already tested iOS build; never substitute the workflow run number."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import time
import urllib.parse
import urllib.request

def call(method, path, body=None):
    # Keep offline validation independent of signing/network dependencies.
    from asc_whats_new import call as asc_call
    return asc_call(method, path, body)


def load_request(path):
    request = json.loads(Path(path).read_text())
    assert re.fullmatch(r"[0-9a-f]{40}", request["source_sha"]), "Full source SHA required"
    assert re.fullmatch(r"[1-9][0-9]*", request["build_number"]), "Invalid build number"
    assert re.fullmatch(r"[0-9a-f]{64}", request["ranger_sha256"]), "Asset hash required"
    assert request["bundle_id"] == "com.kriswu.shiftreminder", "Unexpected app"
    assert isinstance(request["source_run_id"], int), "Source CI run required"
    assert isinstance(request["version"], str) and request["version"], "Marketing version required"
    assert request["notes"], "Testing notes required"
    return request


def github(path):
    req = urllib.request.Request(
        "https://api.github.com/repos/" + os.environ["GITHUB_REPOSITORY"] + path,
        headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                 "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def validate_source(request, run, jobs):
    assert run["head_sha"] == request["source_sha"], "CI checked a different commit"
    assert str(run["run_number"]) == request["build_number"], "CI build number mismatch"
    assert run["path"] == ".github/workflows/ios.yml", "Unexpected source workflow"
    assert run["status"] == "completed" and run["conclusion"] == "success", "Source CI did not pass"
    for name in ("build", "core-tests-linux", "arena-look"):
        matched = [job for job in jobs if job["name"] == name]
        assert len(matched) == 1 and matched[0]["conclusion"] == "success", f"Required check failed: {name}"


def find_build(request):
    query = urllib.parse.urlencode({"filter[bundleId]": request["bundle_id"]})
    apps = call("GET", "/apps?" + query)["data"]
    assert len(apps) == 1, "Expected exactly one App Store Connect app"
    query = urllib.parse.urlencode({"filter[app]": apps[0]["id"],
                                   "filter[version]": request["build_number"],
                                   "include": "preReleaseVersion", "limit": 200})
    result = call("GET", "/builds?" + query)
    builds = result.get("data", [])
    assert len(builds) <= 1, "Ambiguous existing build; refusing another upload"
    if not builds:
        return None
    build = builds[0]
    version_id = build["relationships"]["preReleaseVersion"]["data"]["id"]
    versions = [v for v in result.get("included", [])
                if v["type"] == "preReleaseVersions" and v["id"] == version_id]
    assert len(versions) == 1, "Cannot verify existing marketing version"
    assert versions[0]["attributes"]["version"] == request["version"], "Existing build belongs to a different version"
    return build


def output(name, value):
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.write(f"{name}={value}\n")


def save_report(path, request, **values):
    report = {key: request[key] for key in ("build_number", "version", "source_sha", "source_run_id")}
    report.update(values)
    Path(path).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False), flush=True)


def preflight(request):
    run_id = request["source_run_id"]
    validate_source(request, github(f"/actions/runs/{run_id}"),
                    github(f"/actions/runs/{run_id}/jobs?per_page=100")["jobs"])
    build = find_build(request)
    output("upload_required", "false" if build else "true")
    output("source_sha", request["source_sha"])
    output("build_number", request["build_number"])
    save_report("promotion-preflight.json", request, upload_required=build is None,
                existing_build_id=build["id"] if build else None,
                processing_state=build["attributes"].get("processingState") if build else None)


def stamp(request, source):
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    assert actual == request["source_sha"], "Checkout is not the verified source"
    path = source / "App/Info.plist"
    info = plistlib.loads(path.read_bytes())
    info["ArenaCommitSHA"] = actual
    path.write_bytes(plistlib.dumps(info))


def verify_archive(request, archive):
    app = archive / "Products/Applications/ShiftReminder.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == request["bundle_id"], "Wrong app in archive"
    assert info["CFBundleShortVersionString"] == request["version"], "Wrong marketing version"
    assert info["ArenaCommitSHA"] == request["source_sha"], "Wrong source identity"
    extensions = list(app.glob("PlugIns/*.appex/Info.plist"))
    assert extensions, "Missing widget extension"
    for path in [app / "Info.plist", *extensions]:
        assert str(plistlib.loads(path.read_bytes())["CFBundleVersion"]) == request["build_number"], f"Wrong build: {path}"
    models = list(app.rglob("Ranger_Original.glb"))
    assert len(models) == 1, "Missing or ambiguous original ranger"
    digest = hashlib.sha256(models[0].read_bytes()).hexdigest()
    assert digest == request["ranger_sha256"], "Ranger differs from tested build"
    save_report("promotion-archive.json", request, ranger_sha256=digest,
                app_and_extension_build_verified=True)


def write_notes(request, build):
    text = f"Build {request['build_number']} · {request['source_sha'][:7]}\n" + request["notes"].strip()
    assert len(text) <= 3900, "Testing notes too long"
    path = f"/builds/{build['id']}/betaBuildLocalizations"
    localizations = call("GET", path).get("data", [])
    chinese = [loc for loc in localizations if loc["attributes"]["locale"] == "zh-Hans"]
    if chinese:
        loc_id = chinese[0]["id"]
        call("PATCH", f"/betaBuildLocalizations/{loc_id}",
             {"data": {"type": "betaBuildLocalizations", "id": loc_id, "attributes": {"whatsNew": text}}})
    else:
        call("POST", "/betaBuildLocalizations",
             {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "zh-Hans", "whatsNew": text},
                       "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    actual = call("GET", path).get("data", [])
    assert any(loc["attributes"].get("locale") == "zh-Hans" and loc["attributes"].get("whatsNew") == text
               for loc in actual), "Testing notes were not saved"


def finish(request, uploaded):
    deadline = time.monotonic() + 1800
    notes_written = False
    while time.monotonic() < deadline:
        build = find_build(request)
        state = build["attributes"].get("processingState") if build else "NOT_VISIBLE"
        if build and uploaded and not notes_written:
            write_notes(request, build)
            notes_written = True
        save_report("promotion-status.json", request, build_id=build["id"] if build else None,
                    processing_state=state, uploaded_this_run=uploaded, notes_written=notes_written,
                    source_identity_verified_this_run=uploaded)
        if state in ("FAILED", "INVALID"):
            raise RuntimeError(f"Apple processing failed: {state}")
        if state == "VALID":
            beta = call("GET", f"/builds/{build['id']}/buildBetaDetail")["data"]["attributes"]
            save_report("promotion-status.json", request, build_id=build["id"], processing_state=state,
                        uploaded_this_run=uploaded, notes_written=notes_written,
                        source_identity_verified_this_run=uploaded,
                        internal_build_state=beta.get("internalBuildState"),
                        external_build_state=beta.get("externalBuildState"))
            return
        time.sleep(30)
    raise TimeoutError("Upload status recorded, but Apple has not finished processing in 30 minutes; do not re-upload")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "stamp", "archive", "guard", "finish"))
    parser.add_argument("manifest")
    parser.add_argument("--path", type=Path)
    parser.add_argument("--uploaded", action="store_true")
    args = parser.parse_args()
    request = load_request(args.manifest)
    if args.command == "preflight":
        preflight(request)
    elif args.command == "stamp":
        stamp(request, args.path)
    elif args.command == "archive":
        verify_archive(request, args.path)
    elif args.command == "guard":
        assert find_build(request) is None, "Build already exists; stop before uploading it again"
    else:
        finish(request, args.uploaded)


if __name__ == "__main__":
    main()
