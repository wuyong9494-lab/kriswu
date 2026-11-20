#!/usr/bin/env python3
"""Read App Store Connect build inventory and processing status for the Xu preview."""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit

BUNDLE = "com.kriswu.shiftreminder"
VERSION = "1.2"
LAST_KNOWN = 706


class DeliveryError(Exception):
    pass


def get(path):
    from asc_whats_new import call

    for attempt in range(4):
        try:
            return call("GET", path)
        except HTTPError as exc:
            if exc.code not in (408, 429, 500, 502, 503, 504) or attempt == 3:
                raise
        except (URLError, TimeoutError, ConnectionError):
            if attempt == 3:
                raise
        time.sleep(2 ** (attempt + 1))


def query(resource, **params):
    return "/" + resource + "?" + urlencode(params)


def lookup_app():
    result = get(query("apps", **{"filter[bundleId]": BUNDLE, "fields[apps]": "bundleId"}))
    apps = result["data"]
    if len(apps) != 1 or apps[0]["attributes"]["bundleId"] != BUNDLE:
        raise DeliveryError("Apple app identity could not be verified")
    app_id = apps[0]["id"]
    if not re.fullmatch(r"[0-9]+", app_id):
        raise DeliveryError("Unexpected Apple app identifier")
    return app_id


def next_number(app_id):
    path = query("builds", **{"filter[app]": app_id, "fields[builds]": "version", "limit": 200})
    highest = LAST_KNOWN
    seen = set()
    while path:
        if path in seen:
            raise DeliveryError("Apple build inventory pagination did not advance")
        seen.add(path)
        response = get(path)
        for build in response["data"]:
            version = build["attributes"]["version"]
            # Advance the first integer above any existing dotted build too.
            match = re.fullmatch(r"([0-9]+)(?:[.][0-9]+){0,2}", version)
            if not match:
                raise DeliveryError("Apple build inventory contains an unsupported version")
            highest = max(highest, int(match.group(1)))
        cursor = response.get("links", {}).get("next")
        path = None
        if cursor:
            link = urlsplit(cursor)
            if (link.scheme, link.netloc, link.path) != ("https", "api.appstoreconnect.apple.com", "/v1/builds") or not link.query:
                raise DeliveryError("Unexpected Apple build inventory pagination link")
            path = "/builds?" + link.query
    if highest >= 9999:
        raise DeliveryError("Next integer would exceed the four-digit CFBundleVersion component")
    return str(highest + 1)


def receipt(**data):
    print(json.dumps(data, sort_keys=True), flush=True)


def run_identity():
    run = os.environ["GITHUB_RUN_ID"]
    attempt = os.environ["GITHUB_RUN_ATTEMPT"]
    if not run.isdigit() or attempt != "1":
        raise DeliveryError("An original workflow run is required")
    return run


def preflight(path):
    run = run_identity()
    if path.exists():
        raise DeliveryError("Build selection already exists for this run")
    app = lookup_app()
    number = next_number(app)
    state = {"app_id": app, "build_number": number, "bundle_id": BUNDLE,
             "version": VERSION, "run_id": run}
    with path.open("x", encoding="utf-8") as handle:
        json.dump(state, handle)
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            print(f"build_number={number}", file=handle)
    receipt(stage="selected", **state)


def read_state(path):
    state = json.loads(path.read_text(encoding="utf-8"))
    if (state["bundle_id"] != BUNDLE or state["version"] != VERSION
            or state["run_id"] != run_identity() or not re.fullmatch(r"[0-9]+", state["app_id"])
            or not re.fullmatch(r"[1-9][0-9]{0,3}", state["build_number"])
            or int(state["build_number"]) <= LAST_KNOWN):
        raise DeliveryError("Build selection does not match this workflow")
    return state


def guard(path):
    state = read_state(path)
    if state["app_id"] != lookup_app() or state["build_number"] != next_number(state["app_id"]):
        raise DeliveryError("Apple build inventory changed before export")
    # Claim before export. A lost export response must never trigger a second attempt.
    guard_file(path).touch(exist_ok=False)
    receipt(stage="guarded", **state)


def guard_file(path):
    return path.with_name(path.name + ".export-claimed")


def inspect_build(state):
    result = get(query("builds", **{"filter[app]": state["app_id"],
                                    "filter[version]": state["build_number"],
                                    "include": "preReleaseVersion", "limit": 200}))
    builds = result["data"]
    if not builds:
        return {"processing_state": "NOT_VISIBLE"}
    if len(builds) != 1 or result.get("links", {}).get("next"):
        raise DeliveryError("Multiple builds match the selected number")
    build = builds[0]
    attr = build["attributes"]
    if attr["version"] != state["build_number"] or not re.fullmatch(r"[A-Za-z0-9-]+", build["id"]):
        raise DeliveryError("Apple build identity mismatch")
    rel = build.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
    version = [v for v in result.get("included", [])
               if v["type"] == "preReleaseVersions" and v["id"] == rel.get("id")]
    if not version:
        return {"processing_state": "AWAITING_VERSION_IDENTITY"}
    if len(version) != 1 or (version[0]["attributes"]["version"], version[0]["attributes"]["platform"]) != (VERSION, "IOS"):
        raise DeliveryError("Apple build belongs to a different marketing version or platform")
    if not isinstance(attr.get("expired"), bool):
        raise DeliveryError("Apple build expiration status unavailable")
    details = {"build_id": build["id"], "processing_state": attr["processingState"],
               "expired": attr["expired"],
               "app_store_connect": f"https://appstoreconnect.apple.com/apps/{state['app_id']}/testflight/ios/{build['id']}"}
    if details["processing_state"] == "VALID" and not details["expired"]:
        try:
            beta = get(f"/builds/{build['id']}/buildBetaDetail")["data"]["attributes"]
        except HTTPError as exc:
            if exc.code not in (403, 404):
                raise
            beta = {}
        details.update(internal_build_state=beta.get("internalBuildState"),
                       external_build_state=beta.get("externalBuildState"))
    return details


def status(path, timeout):
    state = read_state(path)
    if not guard_file(path).is_file():
        raise DeliveryError("Missing export guard receipt")
    deadline = time.monotonic() + timeout
    previous = None
    while True:
        try:
            obs = inspect_build(state)
        except HTTPError as exc:
            if exc.code not in (408, 429, 500, 502, 503, 504):
                raise
            obs = {"processing_state": "READ_TEMPORARILY_UNAVAILABLE"}
        except (URLError, TimeoutError, ConnectionError):
            obs = {"processing_state": "READ_TEMPORARILY_UNAVAILABLE"}
        if obs != previous:
            receipt(stage="apple-status", **state, **obs)
            previous = obs
        if obs.get("expired") or obs["processing_state"] in ("FAILED", "INVALID"):
            raise DeliveryError("Apple reported an unusable build")
        if obs["processing_state"] == "VALID":
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise DeliveryError("Apple processing unconfirmed before timeout; inspect this build without re-uploading")
        time.sleep(min(30, remaining))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("preflight", "guard", "status"))
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=1800, help="status polling window, in seconds")
    args = parser.parse_args()
    if args.action == "preflight":
        preflight(args.state)
    elif args.action == "guard":
        guard(args.state)
    else:
        status(args.state, args.timeout)


if __name__ == "__main__":
    try:
        main()
    except DeliveryError as error:
        sys.exit(str(error))
    except HTTPError as error:
        sys.exit(f"Apple read failed (HTTP {error.code})")
    except (OSError, ValueError, KeyError, TypeError, ImportError) as error:
        sys.exit(f"Apple delivery read could not be verified ({type(error).__name__})")
