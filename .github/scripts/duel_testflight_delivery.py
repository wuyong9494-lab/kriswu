#!/usr/bin/env python3
"""Safe, deterministic TestFlight delivery helper for Duel Original Minimal builds.

Dynamically selects the next monotonically increasing CFBundleVersion from
App Store Connect, verifies source CI, stamps ArenaCommitSHA, validates all
13 bundled 3D DuelCharacters assets inside the signed .xcarchive, guards
against duplicate uploads, waits for Apple VALID processing, writes Chinese
What's New notes, and attaches to existing active external TestFlight groups.
"""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

API_BASE = "https://api.appstoreconnect.apple.com/v1"
EXPECTED_BUNDLE_ID = "com.kriswu.shiftreminder"
REQUIRED_CHARACTER_FILES = [
    "DuelChar_wuYong.glb",
    "DuelChar_wuYong.json",
    "DuelWeapon_wuYong.glb",
    "DuelChar_liuQuanwei.glb",
    "DuelChar_liuQuanwei.json",
    "DuelWeapon_liuQuanwei.glb",
    "DuelChar_sunDeng.glb",
    "DuelChar_sunDeng.json",
    "DuelWeapon_sunDeng.glb",
    "DuelWeaponL_sunDeng.glb",
    "DuelChar_xuXiao.glb",
    "DuelChar_xuXiao.json",
    "DuelWeapon_xuXiao.glb",
]


class DeliveryError(RuntimeError):
    pass


def asc_token() -> str:
    import jwt  # pyjwt

    key = Path(os.environ["ASC_KEY_PATH"]).read_text(encoding="utf-8")
    now = int(time.time())
    payload = {
        "iss": os.environ["ASC_ISSUER_ID"],
        "iat": now,
        "exp": now + 600,
        "aud": "appstoreconnect-v1",
    }
    encoded = jwt.encode(
        payload,
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )
    return encoded if isinstance(encoded, str) else encoded.decode("utf-8")


def asc_call(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = Request(
        API_BASE + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + asc_token(),
            "Content-Type": "application/json",
        },
    )
    with urlopen(req, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else {}


def asc_get_retry(path: str) -> dict:
    for attempt in range(4):
        try:
            return asc_call("GET", path)
        except HTTPError as exc:
            if exc.code not in (408, 429, 500, 502, 503, 504) or attempt == 3:
                raise
        except (URLError, TimeoutError, ConnectionError):
            if attempt == 3:
                raise
        time.sleep(2 ** (attempt + 1))
    raise DeliveryError("Unreachable retry fallthrough")


def asc_list(path: str, max_pages: int = 25) -> list[dict]:
    rows: list[dict] = []
    seen: set[str] = set()
    cur: str | None = path
    for _ in range(max_pages):
        if not cur:
            return rows
        if cur in seen:
            raise DeliveryError("App Store Connect pagination loop detected")
        seen.add(cur)
        resp = asc_get_retry(cur)
        rows.extend(resp.get("data", []))
        nxt = (resp.get("links") or {}).get("next")
        if not nxt:
            return rows
        parsed = urlsplit(nxt)
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com" or not parsed.path.startswith("/v1/"):
            raise DeliveryError(f"Unexpected pagination link: {nxt}")
        cur = parsed.path[len("/v1"):] + (f"?{parsed.query}" if parsed.query else "")
    raise DeliveryError("Exceeded maximum pagination depth")


def gh_get(path: str) -> dict:
    repo = os.environ["GITHUB_REPOSITORY"]
    req = Request(
        f"https://api.github.com/repos/{repo}{path}",
        headers={
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
            "Accept": "application/vnd.github+json",
        },
    )
    with urlopen(req, timeout=30) as resp:
        return json.load(resp)


def load_manifest(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("bundle_id") != EXPECTED_BUNDLE_ID:
        raise DeliveryError(f"Unexpected bundle_id: {data.get('bundle_id')}")
    if not re.fullmatch(r"[0-9a-f]{40}", str(data.get("source_sha", ""))):
        raise DeliveryError("Full 40-char source_sha required")
    if not isinstance(data.get("source_run_id"), int) or data["source_run_id"] <= 0:
        raise DeliveryError("Positive integer source_run_id required")
    if not str(data.get("version", "")).strip():
        raise DeliveryError("Marketing version required")
    if not str(data.get("notes", "")).strip():
        raise DeliveryError("Testing notes required")
    return data


def lookup_app(bundle_id: str) -> str:
    query = "/apps?" + urlencode({"filter[bundleId]": bundle_id, "fields[apps]": "bundleId"})
    apps = asc_get_retry(query).get("data", [])
    if len(apps) != 1 or apps[0]["attributes"]["bundleId"] != bundle_id:
        raise DeliveryError(f"Could not uniquely resolve App Store Connect app for {bundle_id}")
    return str(apps[0]["id"])


def next_build_number(app_id: str, min_floor: int) -> str:
    query = "/builds?" + urlencode({"filter[app]": app_id, "fields[builds]": "version", "limit": 200})
    highest = min_floor
    for build in asc_list(query):
        ver = str(build["attributes"]["version"])
        m = re.fullmatch(r"([0-9]+)(?:[.][0-9]+){0,2}", ver)
        if m:
            highest = max(highest, int(m.group(1)))
    if highest >= 9999:
        raise DeliveryError(f"Next build number exceeds 4 digits ({highest + 1})")
    return str(highest + 1)


def find_exact_build(app_id: str, build_number: str, marketing_version: str) -> dict | None:
    query = "/builds?" + urlencode({
        "filter[app]": app_id,
        "filter[version]": build_number,
        "include": "preReleaseVersion",
        "limit": 50,
    })
    resp = asc_get_retry(query)
    builds = resp.get("data", [])
    if not builds:
        return None
    if len(builds) > 1:
        raise DeliveryError(f"Multiple builds found matching build number {build_number}")
    build = builds[0]
    rel = (build.get("relationships", {}).get("preReleaseVersion", {}) or {}).get("data") or {}
    if rel.get("id"):
        versions = [
            v for v in resp.get("included", [])
            if v.get("type") == "preReleaseVersions" and v.get("id") == rel["id"]
        ]
        if versions and versions[0]["attributes"].get("version") != marketing_version:
            raise DeliveryError(
                f"Build {build_number} belongs to version {versions[0]['attributes'].get('version')}, expected {marketing_version}"
            )
    return build


def write_github_output(**pairs: str) -> None:
    out_path = os.environ.get("GITHUB_OUTPUT")
    if out_path:
        with open(out_path, "a", encoding="utf-8") as fh:
            for k, v in pairs.items():
                fh.write(f"{k}={v}\n")


def cmd_preflight(manifest_path: Path, state_path: Path) -> None:
    manifest = load_manifest(manifest_path)
    run_id = manifest["source_run_id"]
    run = gh_get(f"/actions/runs/{run_id}")
    if run.get("head_sha") != manifest["source_sha"]:
        raise DeliveryError(
            f"CI run {run_id} checked {run.get('head_sha')}, expected {manifest['source_sha']}"
        )
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        raise DeliveryError(
            f"CI run {run_id} did not pass (status={run.get('status')}, conclusion={run.get('conclusion')})"
        )
    jobs = gh_get(f"/actions/runs/{run_id}/jobs?per_page=100").get("jobs", [])
    passed_jobs = [j["name"] for j in jobs if j.get("conclusion") == "success"]
    for required in ("iPhone Duel Minimal Regression", "iPad Duel Minimal Regression"):
        if required not in passed_jobs:
            raise DeliveryError(f"Required dual-platform CI job missing/unsuccessful: {required}")

    app_id = lookup_app(manifest["bundle_id"])
    min_floor = int(manifest.get("min_build_floor", 707))
    build_number = next_build_number(app_id, min_floor)
    state = {
        "app_id": app_id,
        "bundle_id": manifest["bundle_id"],
        "version": manifest["version"],
        "build_number": build_number,
        "source_sha": manifest["source_sha"],
        "source_run_id": run_id,
        "github_run_id": os.environ.get("GITHUB_RUN_ID", "local"),
    }
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_github_output(
        build_number=build_number,
        source_sha=manifest["source_sha"],
        version=manifest["version"],
    )
    print(json.dumps({"stage": "preflight", **state}, ensure_ascii=False), flush=True)


def cmd_stamp(manifest_path: Path, source_dir: Path) -> None:
    manifest = load_manifest(manifest_path)
    actual_sha = subprocess.check_output(["git", "-C", str(source_dir), "rev-parse", "HEAD"], text=True).strip()
    if actual_sha != manifest["source_sha"]:
        raise DeliveryError(f"Checked out SHA {actual_sha} != manifest {manifest['source_sha']}")
    plist_path = source_dir / "App" / "Info.plist"
    info = plistlib.loads(plist_path.read_bytes())
    info["ArenaCommitSHA"] = actual_sha
    plist_path.write_bytes(plistlib.dumps(info))
    # Verify all 13 character/weapon assets exist in source before archiving
    char_dir = source_dir / "App" / "Resources" / "DuelCharacters"
    for fname in REQUIRED_CHARACTER_FILES:
        f = char_dir / fname
        if not f.is_file() or f.stat().st_size == 0:
            raise DeliveryError(f"Missing or empty source character asset: {f}")
    print(json.dumps({"stage": "stamped", "source_sha": actual_sha, "character_assets": len(REQUIRED_CHARACTER_FILES)}), flush=True)


def cmd_verify_archive(manifest_path: Path, state_path: Path, archive_path: Path) -> None:
    manifest = load_manifest(manifest_path)
    state = json.loads(state_path.read_text(encoding="utf-8"))
    app_dir = archive_path / "Products" / "Applications" / "ShiftReminder.app"
    info = plistlib.loads((app_dir / "Info.plist").read_bytes())

    if info.get("CFBundleIdentifier") != manifest["bundle_id"]:
        raise DeliveryError(f"Archive CFBundleIdentifier mismatch: {info.get('CFBundleIdentifier')}")
    if str(info.get("CFBundleShortVersionString")) != str(manifest["version"]):
        raise DeliveryError(f"Archive version mismatch: {info.get('CFBundleShortVersionString')}")
    if info.get("ArenaCommitSHA") != manifest["source_sha"]:
        raise DeliveryError(f"Archive ArenaCommitSHA mismatch: {info.get('ArenaCommitSHA')}")
    if str(info.get("CFBundleVersion")) != str(state["build_number"]):
        raise DeliveryError(f"Archive app build mismatch: {info.get('CFBundleVersion')} != {state['build_number']}")

    extensions = list(app_dir.glob("PlugIns/*.appex/Info.plist"))
    if not extensions:
        raise DeliveryError("Missing app extensions inside archive")
    extension_ids: dict[str, Path] = {}
    for ext_plist in extensions:
        ext_info = plistlib.loads(ext_plist.read_bytes())
        ext_id = str(ext_info.get("CFBundleIdentifier", ""))
        extension_ids[ext_id] = ext_plist.parent
        if str(ext_info.get("CFBundleVersion")) != str(state["build_number"]):
            raise DeliveryError(
                f"Extension {ext_plist} build mismatch: {ext_info.get('CFBundleVersion')} != {state['build_number']}"
            )
        if str(ext_info.get("CFBundleShortVersionString")) != str(manifest["version"]):
            raise DeliveryError(
                f"Extension {ext_plist} version mismatch: {ext_info.get('CFBundleShortVersionString')} != {manifest['version']}"
            )

    required_ext_ids = (
        f"{EXPECTED_BUNDLE_ID}.widget",
        f"{EXPECTED_BUNDLE_ID}.tendershare",
    )
    for req_id in required_ext_ids:
        if req_id not in extension_ids:
            raise DeliveryError(f"Missing required extension {req_id} inside archive (found: {sorted(extension_ids)})")

    required_group = f"group.{EXPECTED_BUNDLE_ID}"
    entitlement_targets = [("app", app_dir)] + [(ext_id, extension_ids[ext_id]) for ext_id in required_ext_ids]
    entitlements_verified: dict[str, list[str]] = {}
    for label, target_bundle in entitlement_targets:
        raw_ent = subprocess.check_output(
            ["codesign", "-d", "--entitlements", "-", "--xml", str(target_bundle)],
            stderr=subprocess.DEVNULL,
        )
        ent_dict = plistlib.loads(raw_ent)
        groups = list(ent_dict.get("com.apple.security.application-groups") or [])
        if required_group not in groups:
            raise DeliveryError(f"Signed bundle {label} missing App Group {required_group} (found: {groups})")
        entitlements_verified[label] = groups

    found_assets: dict[str, int] = {}
    for fname in REQUIRED_CHARACTER_FILES + ["DuelStage_Sanctuary.glb"]:
        matches = list(app_dir.rglob(fname))
        if not matches or matches[0].stat().st_size == 0:
            raise DeliveryError(f"Missing or empty {fname} inside signed ShiftReminder.app archive")
        found_assets[fname] = matches[0].stat().st_size

    optional_private_assets: dict[str, int] = {}
    for fname in ("DuelChar_liuQuanwei_beast.glb", "DuelProp_LegionChain.glb", "DuelProp_MonkeyPillar.glb"):
        matches = list(app_dir.rglob(fname))
        if matches and matches[0].stat().st_size > 0:
            optional_private_assets[fname] = matches[0].stat().st_size

    rules_file = app_dir / "FighterNetworkRules.json"
    if not rules_file.is_file() or rules_file.stat().st_size == 0:
        raise DeliveryError("Missing FighterNetworkRules.json inside signed ShiftReminder.app archive")

    report = {
        "stage": "archive-verified",
        "bundle_id": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "source_sha": info["ArenaCommitSHA"],
        "extensions_verified": sorted(extension_ids.keys()),
        "app_groups_verified": entitlements_verified,
        "character_assets_verified": len(found_assets),
        "character_assets_total_mb": round(sum(found_assets.values()) / (1024 * 1024), 2),
        "private_pack_extras": sorted(optional_private_assets.keys()),
        "private_pack_extras_mb": round(sum(optional_private_assets.values()) / (1024 * 1024), 2),
        "rules_bytes": rules_file.stat().st_size,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)


def cmd_guard(state_path: Path) -> None:
    state = json.loads(state_path.read_text(encoding="utf-8"))
    existing = find_exact_build(state["app_id"], state["build_number"], state["version"])
    if existing is not None:
        raise DeliveryError(f"Build {state['build_number']} already exists in App Store Connect; aborting duplicate upload")
    print(json.dumps({"stage": "guarded", "build_number": state["build_number"]}), flush=True)


def write_notes(build_id: str, build_number: str, source_sha: str, notes: str) -> bool:
    text = f"Build {build_number} · {source_sha[:7]}\n{notes.strip()}"[:3900]
    path = f"/builds/{build_id}/betaBuildLocalizations"
    existing = asc_get_retry(path).get("data", [])
    zh = [loc for loc in existing if loc["attributes"].get("locale") == "zh-Hans"]
    if zh:
        loc_id = zh[0]["id"]
        asc_call("PATCH", f"/betaBuildLocalizations/{loc_id}", {
            "data": {"type": "betaBuildLocalizations", "id": loc_id, "attributes": {"whatsNew": text}}
        })
    else:
        asc_call("POST", "/betaBuildLocalizations", {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": "zh-Hans", "whatsNew": text},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }
        })
    return True


def attach_external_groups(app_id: str, build: dict, notify_external: bool) -> dict:
    info: dict = {"attempted": True, "groups_linked": 0, "submitted_for_review": False}
    build_id = build["id"]
    if build["attributes"].get("buildAudienceType") != "APP_STORE_ELIGIBLE":
        info["skipped_reason"] = f"buildAudienceType={build['attributes'].get('buildAudienceType')}"
        return info

    groups = []
    for g in asc_list(f"/apps/{app_id}/betaGroups?limit=200"):
        if g["attributes"].get("isInternalGroup") is not False:
            continue
        g_builds = asc_list(f"/betaGroups/{g['id']}/builds?limit=200")
        if any(b["attributes"].get("processingState") == "VALID" and b["attributes"].get("expired") is False for b in g_builds):
            groups.append({"id": g["id"], "name": g["attributes"].get("name", "")})

    info["active_external_groups"] = len(groups)
    if not groups:
        info["skipped_reason"] = "no active external beta groups"
        return info

    detail_path = f"/builds/{build_id}/buildBetaDetail"
    detail = asc_get_retry(detail_path)["data"]
    if notify_external and detail["attributes"].get("autoNotifyEnabled") is not True:
        asc_call("PATCH", f"/buildBetaDetails/{detail['id']}", {
            "data": {"type": "buildBetaDetails", "id": detail["id"], "attributes": {"autoNotifyEnabled": True}}
        })

    missing = []
    for g in groups:
        linked = asc_list(f"/betaGroups/{g['id']}/relationships/builds?limit=200")
        if not any(row["id"] == build_id for row in linked):
            missing.append({"type": "betaGroups", "id": g["id"]})
    if missing:
        asc_call("POST", f"/builds/{build_id}/relationships/betaGroups", {"data": missing})
    info["groups_linked"] = len(groups)

    detail = asc_get_retry(detail_path)["data"]
    ext_state = detail["attributes"].get("externalBuildState")
    if ext_state == "READY_FOR_BETA_SUBMISSION":
        existing_sub = asc_list("/betaAppReviewSubmissions?" + urlencode({"filter[build]": build_id, "limit": 50}))
        if not existing_sub:
            asc_call("POST", "/betaAppReviewSubmissions", {
                "data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
                }
            })
            info["submitted_for_review"] = True
            detail = asc_get_retry(detail_path)["data"]

    info["external_build_state"] = detail["attributes"].get("externalBuildState")
    info["internal_build_state"] = detail["attributes"].get("internalBuildState")
    return info


def cmd_finish(manifest_path: Path, state_path: Path, status_out: Path, timeout_sec: int) -> None:
    manifest = load_manifest(manifest_path)
    state = json.loads(state_path.read_text(encoding="utf-8"))
    app_id = state["app_id"]
    build_number = state["build_number"]
    version = state["version"]

    deadline = time.monotonic() + timeout_sec
    notes_written = False
    last_state = None
    while True:
        try:
            build = find_exact_build(app_id, build_number, version)
        except (HTTPError, URLError, TimeoutError, ConnectionError) as exc:
            print(f"::warning::Temporary ASC polling error: {exc}", flush=True)
            build = None
        proc = build["attributes"].get("processingState") if build else "NOT_VISIBLE"
        if build and not notes_written:
            try:
                notes_written = write_notes(build["id"], build_number, manifest["source_sha"], manifest["notes"])
            except Exception as exc:
                print(f"::warning::Deferred writing TestFlight notes ({exc})", flush=True)
        if proc != last_state:
            print(json.dumps({"stage": "apple-poll", "build_number": build_number, "processing_state": proc, "notes_written": notes_written}), flush=True)
            last_state = proc
        if proc in ("FAILED", "INVALID"):
            raise DeliveryError(f"Apple rejected build {build_number}: processingState={proc}")
        if build and proc == "VALID":
            if not notes_written:
                notes_written = write_notes(build["id"], build_number, manifest["source_sha"], manifest["notes"])
            beta = asc_get_retry(f"/builds/{build['id']}/buildBetaDetail")["data"]["attributes"]
            external_report: dict = {"attempted": False}
            if manifest.get("channel") == "testflight-external":
                try:
                    external_report = attach_external_groups(
                        app_id, build, bool(manifest.get("notify_external_testers", True))
                    )
                except Exception as exc:
                    external_report = {"attempted": True, "warning": str(exc)}
                    print(f"::warning::External group distribution step warning: {exc}", flush=True)
            final = {
                "stage": "complete",
                "bundle_id": state["bundle_id"],
                "version": version,
                "build_number": build_number,
                "source_sha": manifest["source_sha"],
                "build_id": build["id"],
                "processing_state": proc,
                "notes_written": notes_written,
                "internal_build_state": beta.get("internalBuildState"),
                "external_build_state": external_report.get("external_build_state", beta.get("externalBuildState")),
                "external_distribution": external_report,
                "app_store_connect_url": f"https://appstoreconnect.apple.com/apps/{app_id}/testflight/ios/{build['id']}",
            }
            status_out.write_text(json.dumps(final, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(final, ensure_ascii=False, indent=2), flush=True)
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise DeliveryError(f"Timed out waiting for Apple to finish processing build {build_number}")
        time.sleep(min(25, remaining))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    s_pre = sub.add_parser("preflight")
    s_pre.add_argument("--manifest", type=Path, required=True)
    s_pre.add_argument("--state", type=Path, required=True)

    s_stamp = sub.add_parser("stamp")
    s_stamp.add_argument("--manifest", type=Path, required=True)
    s_stamp.add_argument("--source", type=Path, required=True)

    s_ver = sub.add_parser("verify-archive")
    s_ver.add_argument("--manifest", type=Path, required=True)
    s_ver.add_argument("--state", type=Path, required=True)
    s_ver.add_argument("--archive", type=Path, required=True)

    s_guard = sub.add_parser("guard")
    s_guard.add_argument("--state", type=Path, required=True)

    s_fin = sub.add_parser("finish")
    s_fin.add_argument("--manifest", type=Path, required=True)
    s_fin.add_argument("--state", type=Path, required=True)
    s_fin.add_argument("--out", type=Path, required=True)
    s_fin.add_argument("--timeout", type=int, default=1800)

    args = p.parse_args()
    if args.cmd == "preflight":
        cmd_preflight(args.manifest, args.state)
    elif args.cmd == "stamp":
        cmd_stamp(args.manifest, args.source)
    elif args.cmd == "verify-archive":
        cmd_verify_archive(args.manifest, args.state, args.archive)
    elif args.cmd == "guard":
        cmd_guard(args.state)
    elif args.cmd == "finish":
        cmd_finish(args.manifest, args.state, args.out, args.timeout)


if __name__ == "__main__":
    try:
        main()
    except DeliveryError as exc:
        print(f"::error::{exc}", file=sys.stderr)
        sys.exit(1)
