#!/usr/bin/env python3
"""Read-only Android prerequisites; never installs, accepts licenses or boots a device.

Official catalog: https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-1.xml
License algorithm: Android tools/base repository/api/License.java, blob
876bb437b6e155a32e1a6a53a2be7d1b18a49294: SHA1(value.getBytes(UTF_8));
checkAccepted compares each license-file line exactly, without trimming it.
https://android.googlesource.com/platform/tools/base/+/mirror-goog-studio-master-dev/repository/src/main/java/com/android/repository/api/License.java

The approved API 30 r16 package uses android-sdk-license. Do not substitute an
API 34 ARM-DBT license, a historical hash, or a whitespace-normalized hash.
The single catalog GET uses urllib's default proxy and TLS, without redirects.
Only public metadata and existence/readiness booleans reach logs or the summary.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET


REPOSITORY = "wuyong9494-lab/kriswu"
REF = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
MESSAGE = "Verify Android bootstrap prerequisites 20261115"
WORKFLOW = ".github/workflows/fighter-android-bootstrap-preflight.yml"
CATALOG = "https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-1.xml"
CATALOG_LIMIT = 4 * 1024 * 1024
SOURCE_CATALOG_SHA256 = "d48bd8404b8d5ab42d84cc0907dfb9e55c8a50194bb07c8a864c331375dd8b3a"
PACKAGE = "system-images;android-30;google_apis;x86_64"
LICENSE_ID = "android-sdk-license"
LICENSE_HASH = "efa68a6b3c661d18699d5c026771d5911cdc2f83"
ARCHIVE_BYTES = 1438186618
ARCHIVE_SHA1 = "6ae21030eaadc041078444d3798e4b399f3e787d"
ARCHIVE_NAME = "x86_64-30_r16.zip"
SDK_ROOT = Path("/usr/local/lib/android/sdk")


class Blocked(Exception):
    """A fixed, non-sensitive reason safe to publish."""


def bounded_read(path: Path, limit: int = 65536) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise Blocked("local_metadata_size_limit")
    return data


def admit() -> dict:
    env = os.environ
    required = {"GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": REPOSITORY,
                "GITHUB_REF": REF, "GITHUB_EVENT_NAME": "push", "GITHUB_RUN_ATTEMPT": "1"}
    if any(env.get(key) != value for key, value in required.items()):
        raise Blocked("repository_branch_event_or_attempt_mismatch")
    sha, run = env.get("GITHUB_SHA", ""), env.get("GITHUB_RUN_ID", "")
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or not re.fullmatch(r"[0-9]+", run):
        raise Blocked("invalid_run_identity")
    event = json.loads(bounded_read(Path(env["GITHUB_EVENT_PATH"]), 1024 * 1024))
    if (event.get("after") != sha or event.get("ref") != REF
            or event.get("repository", {}).get("full_name") != REPOSITORY
            or event.get("head_commit", {}).get("message") != MESSAGE):
        raise Blocked("exact_push_identity_mismatch")
    helper_hash = hashlib.sha256(bounded_read(Path(__file__))).hexdigest()
    if helper_hash != env.get("EXPECTED_PREFLIGHT_HELPER_SHA256"):
        raise Blocked("helper_source_pin_mismatch")
    return {"sha": sha, "runId": run, "attempt": 1,
            "helperSHA256": helper_hash,
            "workflowSHA256": hashlib.sha256(bounded_read(Path(WORKFLOW))).hexdigest()}


def tag(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def child(element: ET.Element, name: str) -> ET.Element:
    matches = [item for item in element if tag(item) == name]
    if len(matches) != 1:
        raise Blocked("catalog_shape_mismatch")
    return matches[0]


def value(element: ET.Element, *names: str) -> str:
    for name in names:
        element = child(element, name)
    return element.text or ""


def xml(data: bytes) -> ET.Element:
    if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise Blocked("xml_declarations_not_allowed")
    return ET.fromstring(data)


def selected_package(data: bytes) -> dict:
    root = xml(data)
    matches = [item for item in root if tag(item) == "remotePackage" and item.get("path") == PACKAGE]
    if len(matches) != 1:
        raise Blocked("target_package_not_unique")
    package = matches[0]
    details = child(package, "type-details")
    license_id = child(package, "uses-license").get("ref")
    licenses = [item for item in root if tag(item) == "license" and item.get("id") == license_id]
    if len(licenses) != 1 or len(licenses[0]):
        raise Blocked("target_license_not_unique_plain_text")
    # XML line endings are normalized by the parser, as in JAXB. No strip/collapse.
    license_hash = hashlib.sha1((licenses[0].text or "").encode("utf-8")).hexdigest()
    archive = child(child(package, "archives"), "archive")
    complete = child(archive, "complete")
    dependency = child(child(package, "dependencies"), "dependency")
    observed = (value(details, "api-level"), value(details, "abi"), value(details, "tag", "id"),
                value(package, "revision", "major"), license_id, license_hash,
                value(complete, "url"), value(complete, "size"), value(complete, "checksum"),
                dependency.get("path"), value(dependency, "min-revision", "major"),
                value(dependency, "min-revision", "minor"), value(dependency, "min-revision", "micro"),
                child(package, "channelRef").get("ref"))
    expected = ("30", "x86_64", "google_apis", "16", LICENSE_ID, LICENSE_HASH,
                ARCHIVE_NAME, str(ARCHIVE_BYTES), ARCHIVE_SHA1, "emulator", "30", "8", "0", "channel-0")
    if (observed != expected
            or [tag(item) for item in child(package, "revision")] != ["major"]
            or [tag(item) for item in archive] != ["complete"]
            or child(complete, "checksum").get("type", "sha1") != "sha1"):
        raise Blocked("approved_package_or_license_changed")
    return {"path": PACKAGE, "revision": 16, "minimumEmulator": "30.8.0",
            "licenseId": license_id, "licenseSHA1": license_hash,
            "archiveName": ARCHIVE_NAME, "archiveBytes": ARCHIVE_BYTES, "archiveSHA1": ARCHIVE_SHA1,
            "catalogSHA256": hashlib.sha256(data).hexdigest(), "catalogBytes": len(data),
            "sameCatalogAsReviewed": hashlib.sha256(data).hexdigest() == SOURCE_CATALOG_SHA256}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def timeout_handler(signum, frame):
    raise Blocked("catalog_20_second_deadline")


def fetch_catalog_once() -> bytes:
    previous = signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(20)
    try:
        request = urllib.request.Request(CATALOG, headers={
            "Accept": "application/xml", "Accept-Encoding": "identity",
            "User-Agent": "Android-bootstrap-readonly-preflight/1.0"})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
            if response.status != 200 or response.geturl() != CATALOG:
                raise Blocked("catalog_response_mismatch")
            if response.headers.get("Content-Encoding", "identity").lower() != "identity":
                raise Blocked("catalog_encoding_not_identity")
            length = response.headers.get("Content-Length")
            if length and (not length.isdecimal() or int(length) > CATALOG_LIMIT):
                raise Blocked("catalog_size_limit")
            data = response.read(CATALOG_LIMIT + 1)
            if len(data) > CATALOG_LIMIT:
                raise Blocked("catalog_size_limit")
            return data
    except urllib.error.HTTPError as error:
        code = error.code
        error.close()
        raise Blocked("catalog_http_" + str(code)) from None
    except urllib.error.URLError:
        raise Blocked("catalog_transport_failed") from None
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)


def properties(path: Path) -> dict:
    if not path.is_file():
        return {}
    return dict(line.split("=", 1) for line in bounded_read(path).decode("utf-8").splitlines()
                if "=" in line and not line.lstrip().startswith("#"))


def revision(value_: str) -> tuple:
    return tuple(map(int, value_.split("."))) if re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value_) else ()


def inventory() -> dict:
    for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(name) not in (None, str(SDK_ROOT)):
            raise Blocked("unexpected_sdk_root")
    tools = SDK_ROOT / "cmdline-tools/latest"
    emulator = SDK_ROOT / "emulator"
    image = SDK_ROOT / "system-images/android-30/google_apis/x86_64"
    tools_revision = revision(properties(tools / "source.properties").get("Pkg.Revision", ""))
    emulator_revision = revision(properties(emulator / "source.properties").get("Pkg.Revision", ""))
    image_properties = properties(image / "source.properties")
    image_match = all(image_properties.get(key) == expected for key, expected in {
        "Pkg.Revision": "16", "AndroidVersion.ApiLevel": "30",
        "SystemImage.Abi": "x86_64", "SystemImage.TagId": "google_apis"}.items())
    image_files = all((image / name).is_file() for name in ("system.img", "vendor.img", "ramdisk.img", "kernel-ranchu"))
    license_file = SDK_ROOT / "licenses" / LICENSE_ID
    accepted = False
    if license_file.is_file():
        # CharStreams.readLines removes CR/LF delimiters, not spaces or other text.
        lines = bounded_read(license_file).decode("ascii").replace("\r\n", "\n").replace("\r", "\n").split("\n")
        accepted = LICENSE_HASH in lines
    kvm = Path("/dev/kvm")
    kvm_character = kvm.exists() and stat.S_ISCHR(kvm.stat().st_mode)
    return {
        "sdkmanagerPresentAndExecutable": (tools / "bin/sdkmanager").is_file() and os.access(tools / "bin/sdkmanager", os.X_OK),
        "sdkmanagerMetadataVersion": ".".join(map(str, tools_revision)) or None,
        "emulatorPresentAndExecutable": (emulator / "emulator").is_file() and os.access(emulator / "emulator", os.X_OK),
        "emulatorMetadataVersion": ".".join(map(str, emulator_revision)) or None,
        "emulatorMetadataMeetsMinimum": bool(emulator_revision and (emulator_revision + (0, 0))[:3] >= (30, 8, 0)),
        "targetImageMetadataMatches": image_match, "targetImageRequiredFilesPresent": image_files,
        "licenseFilePresent": license_file.is_file(), "exactImageLicenseAlreadyAccepted": accepted,
        "kvmCharacterDevice": kvm_character, "kvmReadableAndWritable": bool(kvm_character and os.access(kvm, os.R_OK | os.W_OK)),
    }


def main() -> int:
    result = {"schema": 1, "readiness": "blocked", "catalogRequests": 0, "missing": [],
              "scope": "Read-only prerequisites; no SDK install, license acceptance, emulator/APK execution or D19 recovery."}
    try:
        result["source"] = admit()
        result["catalogRequests"] = 1
        result["package"] = selected_package(fetch_catalog_once())
        result["installed"] = inventory()
        required = ("sdkmanagerPresentAndExecutable", "emulatorPresentAndExecutable", "emulatorMetadataMeetsMinimum",
                    "targetImageMetadataMatches", "targetImageRequiredFilesPresent", "exactImageLicenseAlreadyAccepted",
                    "kvmCharacterDevice", "kvmReadableAndWritable")
        result["missing"] = [key for key in required if not result["installed"][key]]
        if not result["missing"]:
            result["readiness"] = "preinstalled_prerequisites_observed_not_boot_verified"
    except Blocked as error:
        result["missing"].append(str(error))
    except (OSError, ValueError, KeyError, ET.ParseError, TimeoutError):
        result["missing"].append("read_or_parse_failed")
    output = json.dumps(result, ensure_ascii=True, indent=2)
    print(output)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write("## Android bootstrap prerequisites\n\n```json\n" + output + "\n```\n\n")
            stream.write("Blocked is an observed prerequisite gap. Completed diagnostics do not establish APK execution or D19 recovery.\n")
    return 1 if result["readiness"] == "blocked" else 0


if __name__ == "__main__":
    sys.exit(main())
