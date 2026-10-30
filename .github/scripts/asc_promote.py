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

SAMPLE_RELEASE_468 = {
    "build_number": "468",
    "source_sha": "64edcdb84fa1590324c7e441e742dfd88b0730ed",
    "source_run_id": 41040595403,
    "source_sample_run_id": 41040595535,
}


def is_sample_release(request):
    if request.get("build_number") != "468" and "source_sample_run_id" not in request:
        return False
    for key, value in SAMPLE_RELEASE_468.items():
        assert request.get(key) == value, f"Sample promotion identity mismatch: {key}"
    assert not request.get("skip_visual_capture"), "468 requires full sample validation"
    return True

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
    is_sample_release(request)
    return request


def github(path):
    req = urllib.request.Request(
        "https://api.github.com/repos/" + os.environ["GITHUB_REPOSITORY"] + path,
        headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                 "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def validate_source(request, run, jobs):
    is_sample_release(request)
    assert run["head_sha"] == request["source_sha"], "CI checked a different commit"
    assert str(run["run_number"]) == request["build_number"], "CI build number mismatch"
    assert run["path"] == ".github/workflows/ios.yml", "Unexpected source workflow"
    if request.get("skip_visual_capture") is True:
        # Explicit owner-authorized capture exceptions, pinned to immutable CI.
        # Compilation, core tests and actual simulator regressions are mandatory.
        capture_exceptions = {
            ("416", 40876218792, "8ec504fb44330d43377f4f7cd2a7e62a58733257"),
            ("425", 40908539488, "5b298adf9e4a4adb3e2755daf2491f87b14ff93a"),
        }
        assert (request["build_number"], request["source_run_id"], request["source_sha"]) in capture_exceptions, "Capture exception not authorized for this exact source"
        assert run["status"] in ("in_progress", "completed"), "Source run not active or complete"
        assert run.get("conclusion") in (None, "success", "failure"), "Source run cancelled or timed out"
        for name in ("build", "core-tests-linux"):
            matched = [job for job in jobs if job["name"] == name]
            assert len(matched) == 1 and matched[0]["conclusion"] == "success", f"Required check failed: {name}"
        visual = [job for job in jobs if job["name"] == "arena-look"]
        assert len(visual) == 1, "Missing or ambiguous simulator job"
        steps = visual[0].get("steps") or []
        for name in ("Set up job", "Run actions/checkout@v5", "选用最新的 Xcode（26 或更新）",
                     "生成 Xcode 工程", "编译模拟器版本", "角色动画回归测试"):
            matched = [step for step in steps if step["name"] == name]
            assert len(matched) == 1 and matched[0]["conclusion"] == "success", f"Required simulator step failed: {name}"
        for job in jobs:
            if job["name"] not in ("arena-look", "screenshots", "testflight", "whats-new"):
                assert job["conclusion"] in ("success", "skipped"), f"Nonvisual job not passed: {job['name']}"
        return
    assert run["status"] == "completed" and run["conclusion"] == "success", "Source CI did not pass"
    for name in ("build", "core-tests-linux", "arena-look"):
        matched = [job for job in jobs if job["name"] == name]
        assert len(matched) == 1 and matched[0]["conclusion"] == "success", f"Required check failed: {name}"


def validate_sample(request, run, jobs):
    assert is_sample_release(request), "Unexpected sample promotion"
    assert run["id"] == request["source_sample_run_id"], "Wrong sample run"
    assert run["head_sha"] == request["source_sha"], "Sample checked a different commit"
    assert run["head_branch"] == "codex/arena-quality-sample", "Unexpected sample branch"
    assert run["path"] == ".github/workflows/arena-sample-validation.yml", "Unexpected sample workflow"
    assert run["status"] == "completed" and run["conclusion"] == "success", "Sample CI did not pass"
    for name in ("sample-capture", "hero-flow (1, testRangerLoop)",
                 "hero-flow (2, testBarbarianLoop)", "hero-flow (3, testMageLoop)"):
        matched = [job for job in jobs if job["name"] == name]
        assert len(matched) == 1 and matched[0]["conclusion"] == "success", f"Required sample check failed: {name}"
        if name != "sample-capture":
            steps = matched[0].get("steps") or []
            for step_name in ("Record and exercise real hero flow",
                              "Validate natural result and continuous original recording"):
                found = [step for step in steps if step["name"] == step_name]
                assert len(found) == 1 and found[0]["conclusion"] == "success", f"Missing passed evidence step: {name}/{step_name}"


def sample_sources_ready(request):
    assert is_sample_release(request), "Unexpected sample promotion"
    head = github("/git/ref/heads/codex/arena-quality-sample")
    assert head["object"]["sha"] == request["source_sha"], "Source superseded; refusing stale release"
    ready = True
    failed = {"failure", "cancelled", "timed_out", "action_required", "stale", "startup_failure"}
    for key, validator in (("source_run_id", validate_source), ("source_sample_run_id", validate_sample)):
        run_id = request[key]
        run = github(f"/actions/runs/{run_id}")
        assert run["id"] == run_id and run["head_sha"] == request["source_sha"], "Unexpected source run"
        assert run.get("conclusion") not in failed, f"Required validation failed: {run_id}"
        jobs = github(f"/actions/runs/{run_id}/jobs?per_page=100")["jobs"]
        for job in jobs:
            assert job.get("conclusion") not in failed, f"Required validation failed: {job['name']}"
        if run["status"] == "completed":
            validator(request, run, jobs)
        else:
            ready = False
    return ready


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
    if "source_sample_run_id" in request:
        report["source_sample_run_id"] = request["source_sample_run_id"]
    report.update(values)
    Path(path).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False), flush=True)


def wait_for_source(request):
    if not request.get("wait_for_source"):
        return
    if is_sample_release(request):
        deadline = time.monotonic() + 5400
        while time.monotonic() < deadline:
            if sample_sources_ready(request):
                return
            print("Waiting for exact 468 iOS and all three hero/sample checks", flush=True)
            time.sleep(30)
        raise TimeoutError("468 validation did not finish within 90 minutes; nothing uploaded")
    sources = {
        ("417", 40895530917, "4de40f69e7d0eb2cb9ff03c5b0b8f4a6aee3b3b0"): "codex/arena-audio-performance",
        ("425", 40908539488, "5b298adf9e4a4adb3e2755daf2491f87b14ff93a"): "codex/arena-reference-fidelity",
    }
    identity = (request["build_number"], request["source_run_id"], request["source_sha"])
    assert identity in sources, "Wait not authorized for this exact source"
    deadline = time.monotonic() + 5400
    while time.monotonic() < deadline:
        head = github("/git/ref/heads/" + sources[identity])
        assert head["object"]["sha"] == request["source_sha"], "Source superseded; refusing stale release"
        run = github(f"/actions/runs/{request['source_run_id']}")
        assert run["head_sha"] == request["source_sha"], "Unexpected source"
        if request.get("skip_visual_capture") is True:
            jobs = github(f"/actions/runs/{request['source_run_id']}/jobs?per_page=100")["jobs"]
            try:
                validate_source(request, run, jobs)
            except AssertionError:
                if run["status"] == "completed":
                    raise
                failed = {"failure", "cancelled", "timed_out", "action_required"}
                for job in jobs:
                    if job["name"] in ("build", "core-tests-linux"):
                        assert job.get("conclusion") not in failed, "Required source job failed"
                    if job["name"] == "arena-look":
                        required = {"Set up job", "Run actions/checkout@v5", "选用最新的 Xcode（26 或更新）", "生成 Xcode 工程", "编译模拟器版本", "角色动画回归测试"}
                        for step in job.get("steps") or []:
                            if step["name"] in required:
                                assert step.get("conclusion") not in failed, "Required simulator step failed"
            else:
                return
        elif run["status"] == "completed":
            validate_source(request, run, github(f"/actions/runs/{request['source_run_id']}/jobs?per_page=100")["jobs"])
            return
        print("Waiting for exact " + request["build_number"] + " device and simulator checks: " + run["status"], flush=True)
        time.sleep(30)
    raise TimeoutError("Source CI did not finish within 90 minutes")


def preflight(request):
    wait_for_source(request)
    run_id = request["source_run_id"]
    validate_source(request, github(f"/actions/runs/{run_id}"),
                    github(f"/actions/runs/{run_id}/jobs?per_page=100")["jobs"])
    if is_sample_release(request):
        assert sample_sources_ready(request), "468 validation is incomplete"
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
        if is_sample_release(request):
            assert sample_sources_ready(request), "468 validation changed before upload"
        assert find_build(request) is None, "Build already exists; stop before uploading it again"
    else:
        finish(request, args.uploaded)


if __name__ == "__main__":
    main()
