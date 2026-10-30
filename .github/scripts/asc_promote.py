#!/usr/bin/env python3
"""Promote an exact, already tested iOS build; never substitute the workflow run number."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import time
import urllib.parse
import urllib.request
import zlib

SAMPLE_RELEASE_471 = {
    "build_number": "471",
    "source_sha": "719cb8369e2c248a7aa6c86bc3d5022edd63f77c",
    "source_run_id": 41062131601,
    "source_sample_run_id": 41062131557,
}
CONTENT_RESTORATION_472 = {
    "build_number": "472",
    "source_sha": "e2244192d499315e8b4715f2198a72e4672879f6",
    "source_run_id": 41074815710,
    "source_sample_run_id": 41074815721,
    "defer_sample_validation": True,
    "verify_vendor_runtime": True,
    "vendor_manifest_sha256": "f99b3b0153f12f5b28904dbfaaf6838afcb5529b27ad0b5462655344c6473e1d",
}
MATERIAL_CONFIGURATION_475 = {
    "build_number": "475",
    "source_sha": "2336a8748aaccb0cb1f5e3b6d761e31348cf9cac",
    "source_run_id": 41089300780,
    "defer_sample_validation": True,
    "verify_vendor_runtime": True,
    "vendor_manifest_sha256": "9e24d8a893cf4432880859992d827059210dbd2753b404a6fc8aee108c29594c",
    "vendor_runtime_file_count": 104,
    "asset_configuration_sha256": "91ccd5c6a4c022dd8b01783f2f7e4cf18bbf64e727a4fba3665225baaf84ce9e",
    "canonical_ranger_file": "Ranger_FaceSample.glb",
    "canonical_ranger_sha256": "4ec9d2cb4eed289be37d8832f57e2c6af45f4d8746452772a247eef9514bdcf0",
    "ranger_sha256": "62ff2a348565b390f3d2b23cabf95286a59ac634a48e27ad1bb129d8e478504d",
}
# Add another owner-authorized release only after its immutable source/run
# identity is known. A manifest cannot grant itself a validation exception.
PINNED_RELEASES = {"471": SAMPLE_RELEASE_471, "472": CONTENT_RESTORATION_472,
                   "475": MATERIAL_CONFIGURATION_475}
CONFIGURED_ASSET_IDENTITY_FIELDS = (
    "vendor_runtime_file_count", "canonical_ranger_file",
    "canonical_ranger_sha256", "asset_configuration_sha256",
)


def is_sample_release(request):
    assert request.get("build_number") != "468", "Build 468 was cancelled by the owner"
    assert request.get("build_number") != "469", "Build 469 failed validation"
    assert request.get("build_number") != "470", "Build 470 failed validation"
    assert request.get("build_number") != "473", "Build 473 failed validation"
    assert request.get("build_number") != "474", "Build 474 has no successful compilation: runner allocation failed"
    identity = PINNED_RELEASES.get(request.get("build_number"))
    if identity is None and "source_sample_run_id" not in request:
        assert not request.get("defer_sample_validation"), "Validation deferral requires an explicitly pinned release"
        assert not request.get("verify_vendor_runtime"), "Vendor release verification requires an explicitly pinned release"
        assert not any(key in request for key in CONFIGURED_ASSET_IDENTITY_FIELDS), "Configured asset verification requires an explicitly pinned release"
        return False
    assert identity is not None, "Unapproved source release identity"
    for key, value in identity.items():
        assert request.get(key) == value, f"Sample promotion identity mismatch: {key}"
    if "source_sample_run_id" in request:
        assert "source_sample_run_id" in identity, "Unpinned sample workflow run"
    # A release request cannot choose its own resource count or asset identities.
    # The two existing releases retain their original, immutable requirements.
    for key in CONFIGURED_ASSET_IDENTITY_FIELDS:
        if key in request:
            assert key in identity, f"Unpinned configured asset field: {key}"
    if identity["build_number"] not in ("471", "472"):
        assert identity.get("verify_vendor_runtime") is True, "Configured release must pin vendor verification"
        for key in CONFIGURED_ASSET_IDENTITY_FIELDS:
            assert key in identity and key in request, f"Configured release requires pinned {key}"
    if "vendor_runtime_file_count" in request:
        assert type(request["vendor_runtime_file_count"]) is int and request["vendor_runtime_file_count"] > 0, "Invalid pinned runtime resource count"
    if "canonical_ranger_file" in request:
        assert request["canonical_ranger_file"] == "Ranger_FaceSample.glb", "Unexpected canonical ranger file"
    for key in ("canonical_ranger_sha256", "asset_configuration_sha256"):
        if key in request:
            assert isinstance(request[key], str) and re.fullmatch(r"[0-9a-f]{64}", request[key]), f"Invalid pinned asset hash: {key}"
    assert not request.get("skip_visual_capture"), "Pinned releases use explicit sample validation or owner deferral"
    if request.get("verify_vendor_runtime"):
        assert identity.get("verify_vendor_runtime") is True, "Vendor verification is not pinned for this release"
        assert request["verify_vendor_runtime"] is True, "Vendor verification must be explicitly enabled"
    if request.get("defer_sample_validation"):
        assert request["defer_sample_validation"] is True, "Deferral must be explicitly enabled"
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
    sample_release = is_sample_release(request)
    assert run["head_sha"] == request["source_sha"], "CI checked a different commit"
    assert str(run["run_number"]) == request["build_number"], "CI build number mismatch"
    assert run["path"] == ".github/workflows/ios.yml", "Unexpected source workflow"
    if request.get("defer_sample_validation"):
        # The owner explicitly requested this pinned release uploaded now and the remaining
        # simulator/hero/media checks deferred. This exception cannot authorize
        # another source, build or run, nor bypass compilation or core tests.
        assert sample_release, "Unexpected deferred release"
        assert run["id"] == request["source_run_id"], "Wrong source run"
        assert run["head_branch"] == "codex/arena-quality-sample", "Unexpected source branch"
        assert run["status"] in ("in_progress", "completed"), "Source checks have not run"
        for name in ("build", "core-tests-linux"):
            matched = [job for job in jobs if job["name"] == name]
            assert len(matched) == 1 and matched[0]["conclusion"] == "success", f"Required check failed: {name}"
        return
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
    if request.get("defer_sample_validation"):
        run_id = request["source_run_id"]
        validate_source(request, github(f"/actions/runs/{run_id}"),
                        github(f"/actions/runs/{run_id}/jobs?per_page=100")["jobs"])
        return True
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
    if request.get("defer_sample_validation"):
        report["owner_requested_validation_deferral"] = True
        report["deferred_checks"] = ["arena-look", "sample-capture", "three-hero-flow-and-recordings"]
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
            print("Waiting for exact " + request["build_number"] + " iOS and requested sample checks", flush=True)
            time.sleep(30)
        raise TimeoutError("Pinned release validation did not finish within 90 minutes; nothing uploaded")
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
        assert sample_sources_ready(request), "Pinned source validation is incomplete"
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


def png_dimensions(data):
    """Read a valid PNG header, including Xcode's CgBI-optimized PNG files."""
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), "Invalid PNG signature"
    offset = 8
    dimensions = None
    saw_pixels = False
    while offset < len(data):
        assert offset + 12 <= len(data), "Truncated PNG chunk"
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        assert end <= len(data), "Truncated PNG payload"
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        checksum = struct.unpack(">I", data[offset + 8 + length:end])[0]
        assert zlib.crc32(kind + payload) & 0xffffffff == checksum, "Invalid PNG chunk checksum"
        if kind == b"IHDR":
            assert dimensions is None and length == 13, "Invalid PNG header"
            dimensions = struct.unpack(">II", payload[:8])
            assert all(value > 0 for value in dimensions), "Empty PNG dimensions"
        elif kind == b"IDAT":
            assert dimensions is not None, "PNG pixels before header"
            saw_pixels = True
        elif kind == b"IEND":
            assert dimensions is not None and saw_pixels and length == 0, "Incomplete PNG"
            assert end == len(data), "Unexpected trailing PNG data"
            return dimensions
        offset = end
    raise AssertionError("Missing PNG end marker")


def verify_vendor_archive(request, app, source):
    assert source is not None, "Verified source checkout is required for vendor resources"
    source_dir = source / "App/ArenaVendor"
    manifest_name = "arena-vendor-runtime.json"
    source_bytes = (source_dir / manifest_name).read_bytes()
    assert hashlib.sha256(source_bytes).hexdigest() == request["vendor_manifest_sha256"], "Source vendor manifest differs from pinned release"
    bundled = list(app.rglob(manifest_name))
    assert len(bundled) == 1, "Missing or ambiguous bundled vendor manifest"
    assert bundled[0].read_bytes() == source_bytes, "Bundled vendor manifest differs from source"
    manifest = json.loads(source_bytes)
    files = manifest["files"]
    expected_count = request.get("vendor_runtime_file_count", 28)
    assert type(expected_count) is int and expected_count > 0, "Invalid pinned runtime resource count"
    assert len(files) == expected_count, f"Expected exactly {expected_count} vendor runtime resources"
    assert manifest["packCount"] == 11 and len({item["pack"] for item in files}) == 11, "Expected all 11 vendor packs"
    names = [item["file"] for item in files]
    assert len(set(names)) == len(names), "Duplicate vendor resource name"
    png_count = 0
    for item in files:
        name = item["file"]
        assert name == Path(name).name and name not in ("", ".", ".."), "Unsafe vendor resource path"
        original = (source_dir / name).read_bytes()
        assert hashlib.sha256(original).hexdigest() == item["sha256"], f"Source resource hash mismatch: {name}"
        matches = list(app.rglob(name))
        assert len(matches) == 1, f"Missing or ambiguous bundled resource: {name}"
        actual = matches[0].read_bytes()
        if name.lower().endswith(".png"):
            assert png_dimensions(actual) == png_dimensions(original), f"PNG dimensions changed: {name}"
            png_count += 1
        else:
            assert hashlib.sha256(actual).hexdigest() == item["sha256"], f"Bundled resource hash mismatch: {name}"
    report = {"vendor_runtime_verified": True, "vendor_runtime_file_count": len(files),
              "vendor_pack_count": 11, "vendor_png_count": png_count,
              "vendor_manifest_sha256": request["vendor_manifest_sha256"]}
    if "asset_configuration_sha256" in request:
        config_name = "arena-asset-configuration.json"
        config_path = source_dir / config_name
        assert config_path.is_file(), "Missing source asset configuration"
        config_bytes = config_path.read_bytes()
        assert hashlib.sha256(config_bytes).hexdigest() == request["asset_configuration_sha256"], "Source asset configuration differs from pinned release"
        assert isinstance(json.loads(config_bytes), dict), "Invalid asset configuration document"
        configs = list(app.rglob(config_name))
        assert len(configs) == 1, "Missing or ambiguous bundled asset configuration"
        assert configs[0].read_bytes() == config_bytes, "Bundled asset configuration differs from source"
        report.update(asset_configuration_verified=True,
                      asset_configuration_sha256=request["asset_configuration_sha256"])
    return report


def verify_canonical_ranger(request, app, source):
    assert source is not None, "Verified source checkout is required for canonical ranger"
    name = request["canonical_ranger_file"]
    assert name == "Ranger_FaceSample.glb", "Unexpected canonical ranger file"
    expected = request["canonical_ranger_sha256"]
    path = source / "App/Arena3D" / name
    assert path.is_file(), "Missing source canonical ranger"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, "Source canonical ranger differs from pinned release"
    models = list(app.rglob(name))
    assert len(models) == 1, "Missing or ambiguous bundled canonical ranger"
    assert hashlib.sha256(models[0].read_bytes()).hexdigest() == expected, "Bundled canonical ranger differs from pinned release"
    return {"canonical_ranger_verified": True, "canonical_ranger_file": name,
            "canonical_ranger_sha256": expected}


def verify_archive(request, archive, source=None):
    sample_release = is_sample_release(request)
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
    vendor_report = {}
    if request.get("verify_vendor_runtime"):
        assert sample_release, "Unexpected vendor-verified release"
        vendor_report = verify_vendor_archive(request, app, source)
    canonical_report = {}
    if "canonical_ranger_file" in request:
        assert sample_release and request.get("verify_vendor_runtime") is True, "Unexpected canonical-verified release"
        canonical_report = verify_canonical_ranger(request, app, source)
    save_report("promotion-archive.json", request, ranger_sha256=digest,
                app_and_extension_build_verified=True, **vendor_report, **canonical_report)


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
    parser.add_argument("--source", type=Path)
    parser.add_argument("--uploaded", action="store_true")
    args = parser.parse_args()
    request = load_request(args.manifest)
    if args.command == "preflight":
        preflight(request)
    elif args.command == "stamp":
        stamp(request, args.path)
    elif args.command == "archive":
        verify_archive(request, args.path, args.source)
    elif args.command == "guard":
        if is_sample_release(request):
            assert sample_sources_ready(request), "Pinned source validation changed before upload"
        assert find_build(request) is None, "Build already exists; stop before uploading it again"
    else:
        finish(request, args.uploaded)


if __name__ == "__main__":
    main()
