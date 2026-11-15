#!/usr/bin/env python3
"""Install only the two explicitly approved Android SDK archives in an owned root.

The caller owns CI admission, APK identity, KVM, emulator lifetime and cleanup.
Importing this module has no side effects. It never runs sdkmanager --install,
--update, yes-all, adb, an emulator or a game, and never writes an acceptance
hash itself. The official interactive --licenses command is the sole writer.

Package-path installs cannot pin these revisions. Two fixed official catalogs
therefore authenticate the selected stable archive URL, size, SHA1 and exact
license text before any archive GET. The official tool may separately retrieve
repository metadata to display its licenses; those requests are not falsely
counted as this helper's two direct catalog GETs.

Official source, tools/base e0179e7b7c4768dd2ebab8d5c8e596180691fd09:
  sdklib/.../tool/sdkmanager/LicensesAction.java and SdkManagerCli.java:
    review y enters the list; each license n declines only that item.
  repository/.../util/InstallerUtil.java:266-285:
    writePackageXml copies an authenticated RemotePackage to a LocalPackage.
  repository/.../impl/meta/SchemaModuleUtil.java:188-197:
    unmarshal uses the SDK's actual registered schema modules.
  sdklib/.../tool/AvdManagerCli.java:283-301:
    canonical toolsdir determines SDK root, so the existing CLI is copied,
    never symlinked back to the system SDK.
Source base: https://android.googlesource.com/platform/tools/base/+/
            e0179e7b7c4768dd2ebab8d5c8e596180691fd09/

The license authorization is limited to android-sdk-license, exact UTF-8
SHA1 efa68a6b3c661d18699d5c026771d5911cdc2f83. Other displayed licenses receive n.
No SDK install or license acceptance is performed by importing this file.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import time
from datetime import datetime, timezone
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile


MIB = 1024**2
GIB = 1024**3
CATALOG_LIMIT = 4 * MIB
MAX_EXPANDED_BYTES = 12 * GIB
MAX_FILES = 100_000
TOTAL_INSTALL_SECONDS = 840
LICENSE_ID = "android-sdk-license"
LICENSE_SHA1 = "efa68a6b3c661d18699d5c026771d5911cdc2f83"
LICENSE_SHA256 = "1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16"
LICENSE_BYTES = 16962
OFFICIAL_SOURCE_COMMIT = "e0179e7b7c4768dd2ebab8d5c8e596180691fd09"
PACKAGES = {
    "emulator": {
        "path": "emulator", "revision": (37, 2, 13), "revisionString": "37.2.13",
        "catalog": "https://dl.google.com/android/repository/repository2-1.xml",
        "url": "https://dl.google.com/android/repository/emulator-linux_x64-16740729.zip",
        "archive": "emulator-linux_x64-16740729.zip", "bytes": 349658551,
        "sha1": "f41f9e31eb5ca64926603c03265c50bbc0ff4172",
        "prefix": "emulator", "relativeRoot": "emulator",
        "requiredFiles": ("emulator", "source.properties"),
    },
    "image": {
        "path": "system-images;android-30;google_apis;x86_64",
        "revision": (16, 0, 0), "revisionString": "16",
        "catalog": "https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-1.xml",
        "url": "https://dl.google.com/android/repository/sys-img/google_apis/x86_64-30_r16.zip",
        "archive": "x86_64-30_r16.zip", "bytes": 1438186618,
        "sha1": "6ae21030eaadc041078444d3798e4b399f3e787d",
        "prefix": "x86_64", "relativeRoot": "system-images/android-30/google_apis/x86_64",
        "requiredFiles": ("system.img", "vendor.img", "ramdisk.img", "kernel-ranchu", "source.properties"),
    },
}


class Blocked(RuntimeError):
    """A fixed reason code, with raw tool details confined to private logs."""


def need(condition, reason):
    if not condition:
        raise Blocked(reason)


def now():
    return datetime.now(timezone.utc).isoformat()


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def bounded_read(path, limit=MIB):
    path = Path(path)
    need(path.is_file() and not path.is_symlink(), "metadata_not_regular_file")
    with path.open("rb") as handle:
        raw = handle.read(limit + 1)
    need(len(raw) <= limit, "metadata_size_bound")
    return raw


def private_write(path, raw):
    with Path(path).open("xb") as handle:
        os.chmod(path, 0o600)
        handle.write(raw)


def write_json(path, value):
    raw = (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()
    temporary = Path(str(path) + ".tmp")
    private_write(temporary, raw)
    temporary.replace(path)


def local_tag(element):
    return element.tag.rsplit("}", 1)[-1]


def child(element, name, optional=False):
    values = [item for item in element if local_tag(item) == name]
    need(len(values) == 1 or (optional and not values), "xml_child_shape")
    return values[0] if values else None


def text(element, name):
    return child(element, name).text or ""


def xml(raw):
    need(len(raw) <= CATALOG_LIMIT, "xml_size_bound")
    need(b"<!DOCTYPE" not in raw.upper() and b"<!ENTITY" not in raw.upper(), "xml_entities_forbidden")
    try:
        return ET.fromstring(raw)
    except ET.ParseError:
        raise Blocked("xml_parse_failed") from None


def numeric_revision(value):
    need(isinstance(value, str) and re.fullmatch(r"\d+(?:\.\d+){0,2}", value), "revision_shape")
    values = tuple(int(item) for item in value.split("."))
    return (values + (0, 0))[:3]


def xml_revision(element):
    names = [local_tag(item) for item in element]
    need(names in (["major"], ["major", "minor"], ["major", "minor", "micro"]), "revision_is_not_stable")
    values = []
    for item in element:
        need(item.text is not None and item.text.isdecimal(), "revision_component_shape")
        values.append(int(item.text))
    return tuple((values + [0, 0])[:3])


def license_decision(license_id, exact_text):
    """Pure prompt decision; no trimming or whitespace-normalizing legal text."""
    raw = exact_text.encode("utf-8") if isinstance(exact_text, str) else exact_text
    need(isinstance(raw, bytes) and len(raw) <= 512 * 1024, "license_text_size_or_type")
    first, second = hashlib.sha1(raw).hexdigest(), sha256(raw)
    accepted = (license_id == LICENSE_ID and len(raw) == LICENSE_BYTES
                and first == LICENSE_SHA1 and second == LICENSE_SHA256)
    return {"id": license_id, "utf8Bytes": len(raw), "sha1": first,
            "sha256": second, "accepted": accepted, "response": "y" if accepted else "n"}


def validate_package_details(package, kind):
    details = child(package, "type-details")
    typename = details.get("{http://www.w3.org/2001/XMLSchema-instance}type", "")
    if kind == "emulator":
        need(typename.split(":")[-1] == "genericDetailsType" and len(details) == 0,
             "emulator_type_changed")
    else:
        need(typename.split(":")[-1] == "sysImgDetailsType", "image_type_changed")
        need(text(details, "api-level") == "30" and text(details, "abi") == "x86_64"
             and text(child(details, "tag"), "id") == "google_apis"
             and text(child(details, "vendor"), "id") == "google", "image_identity_changed")
    dependencies = child(package, "dependencies", optional=True)
    if kind == "emulator":
        need(dependencies is None or len(dependencies) == 0, "emulator_dependency_changed")
    else:
        need(dependencies is not None and len(dependencies) == 1, "image_dependency_count_changed")
        dependency = child(dependencies, "dependency")
        need(dependency.get("path") == "emulator"
             and xml_revision(child(dependency, "min-revision")) == (30, 8, 0),
             "image_dependency_changed")


def selected_package(raw, kind):
    """Select only the authenticated stable revision, ignoring other channels."""
    need(kind in PACKAGES, "unknown_package_kind")
    expected = PACKAGES[kind]
    root = xml(raw)
    candidates = []
    for item in root:
        if local_tag(item) != "remotePackage" or item.get("path") != expected["path"]:
            continue
        channel = child(item, "channelRef", optional=True)
        if channel is not None and channel.get("ref") == "channel-0":
            candidates.append(item)
    need(len(candidates) == 1, "selected_stable_package_not_unique")
    package = candidates[0]
    need(xml_revision(child(package, "revision")) == expected["revision"], "approved_revision_changed")
    channels = [item for item in root if local_tag(item) == "channel" and item.get("id") == "channel-0"]
    need(len(channels) == 1 and (channels[0].text or "").lower() == "stable", "stable_channel_changed")
    need(child(package, "uses-license").get("ref") == LICENSE_ID, "approved_license_id_changed")
    licenses = [item for item in root if local_tag(item) == "license" and item.get("id") == LICENSE_ID]
    need(len(licenses) == 1 and len(licenses[0]) == 0, "license_definition_not_unique")
    decision = license_decision(LICENSE_ID, licenses[0].text or "")
    need(decision["accepted"], "approved_license_text_changed")
    validate_package_details(package, kind)
    archives = list(child(package, "archives"))
    if kind == "emulator":
        matches = [item for item in archives if local_tag(item) == "archive"
                   and text(item, "host-os") == "linux" and text(item, "host-bits") == "64"]
    else:
        matches = archives
    need(len(matches) == 1 and local_tag(matches[0]) == "archive", "selected_archive_not_unique")
    archive = matches[0]
    need([local_tag(item) for item in archive] ==
         (["complete", "host-os", "host-bits"] if kind == "emulator" else ["complete"]),
         "archive_platform_or_partial_shape_changed")
    complete = child(archive, "complete")
    checksum = child(complete, "checksum")
    need(text(complete, "url") == expected["archive"]
         and text(complete, "size") == str(expected["bytes"])
         and checksum.text == expected["sha1"]
         and checksum.get("type", "sha1") == "sha1", "approved_archive_identity_changed")
    return {
        "packagePath": expected["path"], "revision": expected["revisionString"],
        "channel": "stable", "archiveURL": expected["url"], "archiveBytes": expected["bytes"],
        "archiveSHA1": expected["sha1"], "catalogURL": expected["catalog"],
        "catalogBytes": len(raw), "catalogSHA256": sha256(raw),
        "license": {key: decision[key] for key in ("id", "utf8Bytes", "sha1", "sha256")}
                   | {"matchesApprovedText": True},
        "dependency": None if kind == "emulator" else {"path": "emulator", "minimumRevision": "30.8.0"},
    }


def properties(path):
    result = {}
    for line in bounded_read(path, 64 * 1024).decode("utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith(("#", "!")):
            continue
        need("=" in line, "source_properties_line_shape")
        key, value = (part.strip() for part in line.split("=", 1))
        need(key and key not in result, "source_properties_duplicate")
        result[key] = value
    return result


def source_identity(root, kind):
    expected = PACKAGES[kind]
    info = properties(root / "source.properties")
    need(numeric_revision(info.get("Pkg.Revision", "")) == expected["revision"], "installed_revision_mismatch")
    if kind == "image":
        need(all(info.get(key) == value for key, value in {
            "AndroidVersion.ApiLevel": "30", "SystemImage.Abi": "x86_64",
            "SystemImage.TagId": "google_apis"}.items()), "installed_image_identity_mismatch")
    need(all((root / name).is_file() and not (root / name).is_symlink()
             for name in expected["requiredFiles"]), "installed_required_files_missing")
    if kind == "emulator":
        need(os.access(root / "emulator", os.X_OK), "emulator_not_executable")
    return {"revision": info["Pkg.Revision"], "sourcePropertiesSHA256": sha256(bounded_read(root / "source.properties")),
            "api": info.get("AndroidVersion.ApiLevel"), "abi": info.get("SystemImage.Abi"),
            "tag": info.get("SystemImage.TagId"), "requiredFilesPresent": True}


def registration_identity(path, kind):
    raw = bounded_read(path, CATALOG_LIMIT)
    root = xml(raw)
    packages = [item for item in root if local_tag(item) == "localPackage"]
    need(len(packages) == 1, "local_package_not_unique")
    package = packages[0]
    need(package.get("path") == PACKAGES[kind]["path"]
         and xml_revision(child(package, "revision")) == PACKAGES[kind]["revision"], "local_package_identity_changed")
    need(child(package, "uses-license").get("ref") == LICENSE_ID, "local_package_license_changed")
    licenses = [item for item in root if local_tag(item) == "license" and item.get("id") == LICENSE_ID]
    need(len(licenses) == 1 and not len(licenses[0])
         and license_decision(LICENSE_ID, licenses[0].text or "")["accepted"], "local_package_license_text_changed")
    validate_package_details(package, kind)
    return {"packagePath": package.get("path"), "revision": PACKAGES[kind]["revisionString"],
            "bytes": len(raw), "sha256": sha256(raw), "exactMetadataVerified": True}


def safe_member(name):
    need(isinstance(name, str) and name and "\x00" not in name and "\\" not in name
         and not any(ord(char) < 32 or ord(char) == 127 for char in name), "unsafe_archive_path")
    stripped = name[:-1] if name.endswith("/") else name
    parts = stripped.split("/")
    need(parts and all(part not in ("", ".", "..") for part in parts)
         and not PurePosixPath(stripped).is_absolute() and ":" not in parts[0], "unsafe_archive_path")
    return stripped


def safe_link(name, target, names, links):
    need(target and not target.startswith("/") and "\\" not in target and "\x00" not in target
         and not any(ord(char) < 32 for char in target), "unsafe_archive_symlink")
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
    need(resolved in names and resolved != name, "symlink_target_outside_archive")
    seen = {name}
    while resolved in links:
        need(resolved not in seen, "archive_symlink_cycle")
        seen.add(resolved)
        need(len(seen) <= 64, "archive_symlink_depth")
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(resolved), links[resolved]))
        need(resolved in names, "symlink_target_outside_archive")


def zip_inventory(path, kind):
    """Read-only complete preflight before extraction; CRC is checked on reads."""
    need(kind in PACKAGES, "unknown_package_kind")
    prefix = PACKAGES[kind]["prefix"]
    rows, names, folded, links = [], set(), set(), {}
    expanded = 0
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        need(0 < len(infos) <= MAX_FILES, "archive_file_count_bound")
        for item in infos:
            name = safe_member(item.filename)
            need(name == prefix or name.startswith(prefix + "/"), "archive_top_level_changed")
            need(name not in names and name.casefold() not in folded, "archive_duplicate_path")
            need(not item.flag_bits & 1 and item.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
                 "archive_encryption_or_compression_unsupported")
            names.add(name)
            folded.add(name.casefold())
            mode = item.external_attr >> 16
            category = stat.S_IFMT(mode)
            is_link = category == stat.S_IFLNK
            need(category in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), "archive_special_file_forbidden")
            need(not item.is_dir() or item.file_size == 0, "archive_directory_has_content")
            expanded += item.file_size
            need(expanded <= MAX_EXPANDED_BYTES, "archive_expanded_size_bound")
            if is_link:
                need(not item.is_dir() and item.file_size <= 4096, "archive_symlink_size_bound")
                try:
                    links[name] = archive.read(item).decode("utf-8")
                except (UnicodeError, zipfile.BadZipFile):
                    raise Blocked("archive_symlink_or_crc_invalid") from None
            rows.append({"name": name, "zipName": item.filename, "bytes": item.file_size,
                         "directory": item.is_dir(), "symlink": is_link, "executable": bool(mode & 0o111),
                         "crc32": item.CRC})
    all_names = set(names)
    for name in names:
        parent = posixpath.dirname(name)
        while parent:
            all_names.add(parent)
            parent = posixpath.dirname(parent)
    for name in names:
        parent = posixpath.dirname(name)
        while parent:
            need(parent not in links, "archive_member_beneath_symlink")
            parent = posixpath.dirname(parent)
    for name, target in links.items():
        safe_link(name, target, all_names, links)
    return {"rows": rows, "links": links, "expandedBytes": expanded, "fileCount": len(rows),
            "prefix": prefix}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


JAVA_REGISTRAR = r"""import java.io.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import com.android.repository.api.*;
import com.android.repository.impl.meta.Repository;
import com.android.repository.impl.meta.SchemaModuleUtil;
import com.android.repository.util.InstallerUtil;
import com.android.sdklib.repository.AndroidSdkHandler;

public final class RegisterPinnedPackage {
  private static String hex(byte[] raw) {
    StringBuilder out = new StringBuilder();
    for (byte b : raw) out.append(String.format("%02x", b & 255));
    return out.toString();
  }
  public static void main(String[] args) throws Exception {
    if (args.length != 6) throw new IllegalArgumentException("arguments");
    Path catalog = Paths.get(args[0]), destination = Paths.get(args[3]);
    if (!Files.isDirectory(destination) || Files.exists(destination.resolve("package.xml")))
      throw new IllegalStateException("destination_not_fresh");
    ProgressIndicator progress = new ProgressIndicatorAdapter() {
      @Override public void logWarning(String value, Throwable detail) {
        throw new IllegalStateException("official_metadata_warning", detail);
      }
      @Override public void logError(String value, Throwable detail) {
        throw new IllegalStateException("official_metadata_error", detail);
      }
    };
    Collection<SchemaModule<?>> modules = AndroidSdkHandler.getAllModules();
    Repository repository;
    try (InputStream source = Files.newInputStream(catalog)) {
      repository = (Repository) SchemaModuleUtil.unmarshal(source, modules, true,
          progress, catalog.toString());
    }
    if (repository == null) throw new IllegalStateException("catalog_parse_failed");
    RemotePackage selected = null;
    for (RemotePackage candidate : repository.getRemotePackage()) {
      String revision = candidate.getVersion().getMajor() + "." +
          candidate.getVersion().getMinor() + "." + candidate.getVersion().getMicro();
      if (args[1].equals(candidate.getPath()) && args[2].equals(revision)
          && !candidate.getVersion().isPreview()) {
        if (selected != null) throw new IllegalStateException("package_not_unique");
        selected = candidate;
      }
    }
    if (selected == null || selected.getLicense() == null)
      throw new IllegalStateException("package_or_license_missing");
    byte[] legal = selected.getLicense().getValue().getBytes(StandardCharsets.UTF_8);
    if (!"android-sdk-license".equals(selected.getLicense().getId())
        || legal.length != 16962
        || !args[4].equals(hex(MessageDigest.getInstance("SHA-1").digest(legal)))
        || !args[5].equals(hex(MessageDigest.getInstance("SHA-256").digest(legal))))
      throw new IllegalStateException("license_identity_changed");
    RepoManager manager = RepoManager.create();
    for (SchemaModule<?> module : modules) manager.registerSchemaModule(module);
    InstallerUtil.writePackageXml(selected, destination, manager, progress);
    if (!Files.isRegularFile(destination.resolve("package.xml")))
      throw new IllegalStateException("registration_missing");
    System.out.println("Official RemotePackage registration completed.");
  }
}
"""


class Installer:
    def __init__(self, run_dir, system_sdk):
        self.run_dir = Path(run_dir)
        self.system_sdk = Path(system_sdk)
        need(sys.platform == "linux" and os.uname().machine == "x86_64", "linux_x86_64_required")
        for path in (self.run_dir, self.system_sdk):
            need(path.is_absolute() and path.is_dir() and not path.is_symlink(), "root_not_real_directory")
            need(path.resolve() == path, "root_contains_symlink")
        need(self.system_sdk != self.run_dir and self.system_sdk not in self.run_dir.parents
             and self.run_dir not in self.system_sdk.parents, "system_and_owned_roots_overlap")
        self.sdk = self.run_dir / "sdk"
        self.user = self.run_dir / "android-user"
        self.downloads = self.run_dir / "downloads"
        self.evidence = self.run_dir / "evidence"
        need(self.evidence.is_dir() and not self.evidence.is_symlink(), "owned_evidence_directory_missing")
        self.receipt_path = self.evidence / "sdk-install-receipt.json"
        need(not self.receipt_path.exists() and not self.receipt_path.is_symlink(), "install_already_attempted")
        need(not any(path.exists() or path.is_symlink() for path in (self.sdk, self.user)), "owned_sdk_or_user_already_exists")
        need(not self.downloads.exists() or (self.downloads.is_dir() and not self.downloads.is_symlink()),
             "downloads_directory_not_real")
        self.deadline = time.monotonic() + TOTAL_INSTALL_SECONDS
        self.env = dict(os.environ)
        self.env.update({"ANDROID_HOME": str(self.sdk), "ANDROID_SDK_ROOT": str(self.sdk),
                         "ANDROID_USER_HOME": str(self.user), "LC_ALL": "C.UTF-8"})
        self.state = {
            "schema": "fighter-android-sdk-install-v1", "state": "running", "startedAt": now(),
            "phase": "admission", "phaseFailure": None, "helperSHA256": sha256(Path(__file__).read_bytes()),
            "source": {"sha": os.environ.get("GITHUB_SHA"), "runId": os.environ.get("GITHUB_RUN_ID"),
                       "attempt": os.environ.get("GITHUB_RUN_ATTEMPT")},
            "catalogRequests": {key: 0 for key in PACKAGES},
            "archiveDownloadRequests": {key: 0 for key in PACKAGES},
            "catalogs": {}, "selection": {}, "packages": {}, "commands": [],
            "license": {"approvedId": LICENSE_ID, "approvedTextSHA1": LICENSE_SHA1,
                        "approvedTextSHA256": LICENSE_SHA256, "approvedTextBytes": LICENSE_BYTES,
                        "reviewResponses": 0, "acceptanceResponses": 0, "refusalResponses": 0,
                        "decisions": [], "privateLicenseDirectoryInitiallyEmpty": None,
                        "officialToolMayFetchRepositoryMetadata": True,
                        "manualLicenseWrites": 0, "mutationPolicyPassed": False},
            "licenseAcceptedForExactText": False, "installedExactPackagesVerified": False,
            "runtimeValidated": False, "sdkmanagerInstallCalls": 0, "sdkmanagerUpdateCalls": 0,
            "ownedDirectories": [str(self.sdk), str(self.user), str(self.downloads)],
            "registrationSourceCommit": OFFICIAL_SOURCE_COMMIT,
        }
        self.license_before = None
        self.expanded_total = 0
        self.registration_bridge = None

    def save(self):
        write_json(self.receipt_path, self.state)

    def phase(self, value):
        self.state["phase"] = value
        self.save()
        print("Approved SDK phase: " + value, flush=True)

    def remaining(self, limit):
        result = min(limit, self.deadline - time.monotonic())
        need(result > 0, "sdk_install_total_deadline")
        return result

    def command(self, args, label, timeout=90, maximum=8*MIB):
        need(re.fullmatch(r"[a-z0-9-]+", label), "command_label_invalid")
        path = self.evidence / (label + ".log")
        started = time.monotonic()
        limit = self.remaining(timeout)
        record = {"label": label, "elapsedSeconds": None, "exitCode": None,
                  "timedOut": False, "bytes": None, "sha256": None}
        self.state["commands"].append(record)
        self.save()
        with path.open("xb") as output:
            os.chmod(path, 0o600)
            proc = subprocess.Popen([str(item) for item in args], stdin=subprocess.DEVNULL,
                                    stdout=output, stderr=subprocess.STDOUT, env=self.env, start_new_session=True)
            try:
                while proc.poll() is None:
                    if time.monotonic() - started > limit or path.stat().st_size > maximum:
                        record["timedOut"] = time.monotonic() - started > limit
                        raise Blocked("command_time_or_output_bound_" + label)
                    time.sleep(0.05)
            finally:
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=10)
                record.update({"elapsedSeconds": time.monotonic()-started, "exitCode": proc.returncode})
                if path.stat().st_size <= maximum:
                    raw = bounded_read(path, maximum)
                    record.update({"bytes": len(raw), "sha256": sha256(raw)})
                else:
                    record.update({"bytes": path.stat().st_size, "outputExceededBound": True})
                self.save()
        need(proc.returncode == 0, "command_failed_" + label)
        return bounded_read(path, maximum)

    def fetch(self, url, path, kind, *, catalog=False):
        expected = PACKAGES[kind]
        need(url == expected["catalog" if catalog else "url"], "request_not_approved")
        need(not path.exists() and not path.is_symlink(), "download_destination_already_exists")
        counter = "catalogRequests" if catalog else "archiveDownloadRequests"
        need(self.state[counter][kind] == 0, "request_already_attempted")
        self.state[counter][kind] = 1
        self.save()
        maximum = CATALOG_LIMIT if catalog else expected["bytes"]
        deadline = time.monotonic() + self.remaining(25 if catalog else 600)
        request = urllib.request.Request(url, headers={
            "Accept-Encoding": "identity", "User-Agent": "Approved-fixed-Android-SDK/1.0"})
        hashes = [hashlib.sha1(), hashlib.sha256()]
        count = 0
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=min(25, self.remaining(25))) as response:
                need(response.status == 200 and response.geturl() == url, "official_response_mismatch")
                need(response.headers.get("Content-Encoding", "identity").lower() == "identity", "encoded_response_forbidden")
                length = response.headers.get("Content-Length")
                if length is not None:
                    need(length.isdecimal() and int(length) <= maximum
                         and (catalog or int(length) == maximum), "official_content_length_mismatch")
                with path.open("xb") as output:
                    os.chmod(path, 0o600)
                    while True:
                        need(time.monotonic() < deadline, "download_total_deadline")
                        chunk = response.read(min(MIB, maximum-count+1))
                        if not chunk:
                            break
                        count += len(chunk)
                        need(count <= maximum, "download_size_bound")
                        for hasher in hashes:
                            hasher.update(chunk)
                        output.write(chunk)
            need(count > 0 and (catalog or count == expected["bytes"]), "download_size_mismatch")
            need(catalog or hashes[0].hexdigest() == expected["sha1"], "archive_sha1_mismatch")
            return {"url": url, "bytes": count, "sha1": hashes[0].hexdigest(),
                    "sha256": hashes[1].hexdigest(), "requestCount": 1, "verified": True,
                    "sha256Origin": "computed_from_received_bytes",
                    "archiveSHA1AndSizeMatchedApprovedPin": not catalog}
        except urllib.error.HTTPError as error:
            code = error.code
            error.close()
            raise Blocked("official_http_" + str(code)) from None
        except urllib.error.URLError:
            raise Blocked("official_transport_failed_no_retry") from None

    def copy_tree(self, source, destination, maximum):
        """Copy only the existing owned package/tool tree, preserving safe links."""
        source = source.resolve(strict=True)
        need(source.is_dir() and not destination.exists(), "copy_source_or_destination_invalid")
        rows, names, links = [], set(), {}
        total = 0
        stack = [source]
        while stack:
            directory = stack.pop()
            for item in sorted(directory.iterdir()):
                self.remaining(1)
                name = item.relative_to(source).as_posix()
                safe_member(name)
                info = item.lstat()
                names.add(name)
                need(len(names) <= MAX_FILES, "copied_tree_file_count_bound")
                if stat.S_ISLNK(info.st_mode):
                    links[name] = os.readlink(item)
                elif stat.S_ISDIR(info.st_mode):
                    stack.append(item)
                else:
                    need(stat.S_ISREG(info.st_mode), "copied_tree_special_file")
                    total += info.st_size
                need(total <= maximum, "copied_tree_size_bound")
                rows.append((name, info))
        for name, target in links.items():
            safe_link(name, target, names, links)
        need(shutil.disk_usage(self.run_dir).free >= total + GIB, "copy_disk_budget")
        destination.mkdir(mode=0o700, parents=True)
        digest = hashlib.sha256()
        for name, info in sorted(rows):
            self.remaining(1)
            target = destination / name
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            if stat.S_ISDIR(info.st_mode):
                target.mkdir(mode=0o700, exist_ok=True)
            elif not stat.S_ISLNK(info.st_mode):
                hasher, copied = hashlib.sha256(), 0
                with (source/name).open("rb") as source_file, target.open("xb") as output:
                    os.chmod(target, 0o700 if info.st_mode & 0o111 else 0o600)
                    while chunk := source_file.read(MIB):
                        self.remaining(1)
                        copied += len(chunk)
                        need(copied <= info.st_size, "copy_source_changed")
                        hasher.update(chunk)
                        output.write(chunk)
                after = (source/name).stat()
                need(copied == info.st_size and (after.st_ino, after.st_size, after.st_mtime_ns) ==
                     (info.st_ino, info.st_size, info.st_mtime_ns), "copy_source_changed")
                digest.update(name.encode()+b"\x00"+hasher.digest())
        for name, target in sorted(links.items()):
            (destination/name).symlink_to(target)
            digest.update(name.encode()+b"\x00"+target.encode())
        return {"bytes": total, "entries": len(rows), "treeContentSHA256": digest.hexdigest(),
                "source": str(source), "safeInternalSymlinks": len(links)}

    def license_snapshot(self):
        root = self.sdk / "licenses"
        if not root.exists():
            return {}
        need(root.is_dir() and not root.is_symlink(), "license_directory_not_real")
        result = {}
        for path in root.iterdir():
            need(re.fullmatch(r"[a-zA-Z0-9._-]{1,128}", path.name), "license_filename_invalid")
            raw = bounded_read(path, 128*1024)
            lines = raw.decode("ascii").replace("\r\n", "\n").replace("\r", "\n").split("\n")
            need(all(not line or re.fullmatch(r"[0-9a-f]{40}", line) for line in lines), "license_record_shape")
            result[path.name] = {"sha256": sha256(raw), "bytes": len(raw), "lines": lines}
            need(len(result) <= 64, "license_file_count_bound")
        return result

    def observe_license_mutation(self):
        if self.license_before is None:
            return
        legal = self.state["license"]
        # Preserve this factual acceptance even if a different license record
        # is malformed; the independent mutation gate still blocks installation.
        target = self.sdk / "licenses" / LICENSE_ID
        if target.is_file() and not target.is_symlink():
            target_raw = bounded_read(target, 128*1024)
            present = LICENSE_SHA1.encode() in target_raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n").split(b"\n")
            self.state["licenseAcceptedForExactText"] = bool(
                present and legal["acceptanceResponses"] == 1
                and any(item["accepted"] for item in legal["decisions"]))
        after = self.license_snapshot()
        before = self.license_before
        target_lines = [line for line in after.get(LICENSE_ID, {}).get("lines", []) if line]
        exact_present = LICENSE_SHA1 in target_lines
        legal["after"] = after
        legal["exactLinePresentAfter"] = exact_present
        self.state["licenseAcceptedForExactText"] = bool(
            exact_present and legal["acceptanceResponses"] == 1
            and any(item["accepted"] for item in legal["decisions"]))
        allowed = all(name == LICENSE_ID or before.get(name) == value for name, value in after.items())
        allowed = allowed and all(name in after and (name == LICENSE_ID or after[name] == value)
                                  for name, value in before.items())
        old_lines = [line for line in before.get(LICENSE_ID, {}).get("lines", []) if line]
        allowed = allowed and target_lines == old_lines + [LICENSE_SHA1]
        legal["mutationPolicyPassed"] = bool(allowed)

    def accept_only_approved_license(self, sdkmanager):
        self.license_before = self.license_snapshot()
        self.state["license"]["before"] = self.license_before
        self.state["license"]["privateLicenseDirectoryInitiallyEmpty"] = not self.license_before
        need(not self.license_before, "private_license_directory_not_empty")
        self.save()
        raw_path = self.evidence / "sdk-official-license-dialogue.log"
        started = time.monotonic()
        deadline = started + self.remaining(180)
        dialogue, cursor = b"", 0
        record = {"label": "sdk-official-licenses", "exitCode": None, "elapsedSeconds": None,
                  "sdkmanagerAction": "--licenses", "automaticAcceptAll": False}
        self.state["commands"].append(record)
        matcher = re.compile(
            rb"(?:^|\n)(?:[0-9]+/[0-9]+: )?License ([A-Za-z0-9._-]+):\n"
            rb"-{39}\n(.*?)\n-{39}\nAccept\? \(y/N\): ?", re.DOTALL)
        review = re.compile(rb"Review licenses? that (?:have|has) not been accepted \(y/N\)\? ?")
        with raw_path.open("xb") as log:
            os.chmod(raw_path, 0o600)
            proc = subprocess.Popen([str(sdkmanager), "--sdk_root="+str(self.sdk), "--licenses", "--channel=0"],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    env=self.env, start_new_session=True, bufsize=0)
            selector = selectors.DefaultSelector()
            selector.register(proc.stdout, selectors.EVENT_READ)
            try:
                eof = False
                while not eof:
                    need(time.monotonic() < deadline, "license_dialogue_deadline")
                    events = selector.select(min(0.2, max(0.001, deadline-time.monotonic())))
                    if not events:
                        continue
                    chunk = os.read(proc.stdout.fileno(), 65536)
                    if not chunk:
                        eof = True
                        break
                    log.write(chunk)
                    log.flush()
                    dialogue += chunk
                    need(len(dialogue) <= 4*MIB, "license_dialogue_size_bound")
                    # Linux println adds one LF after the exact license value.
                    # CRLF normalization here is terminal framing, never strip().
                    normalized = dialogue.replace(b"\r\n", b"\n")
                    while True:
                        pending = normalized[cursor:]
                        ask_review = review.search(pending)
                        ask_license = matcher.search(pending)
                        if ask_review is not None and (ask_license is None or ask_review.start() < ask_license.start()):
                            need(self.state["license"]["reviewResponses"] == 0, "license_review_repeated")
                            proc.stdin.write(b"y\n")
                            proc.stdin.flush()
                            self.state["license"]["reviewResponses"] = 1
                            cursor += ask_review.end()
                            self.save()
                        elif ask_license is not None:
                            decision = license_decision(ask_license.group(1).decode("ascii"), ask_license.group(2))
                            if decision["accepted"]:
                                need(self.state["license"]["acceptanceResponses"] == 0, "target_license_repeated")
                            proc.stdin.write(decision["response"].encode("ascii")+b"\n")
                            proc.stdin.flush()
                            key = "acceptanceResponses" if decision["accepted"] else "refusalResponses"
                            self.state["license"][key] += 1
                            self.state["license"]["decisions"].append(decision)
                            cursor += ask_license.end()
                            self.save()
                            if decision["id"] == LICENSE_ID and not decision["accepted"]:
                                raise Blocked("displayed_approved_license_text_mismatch")
                        else:
                            need(b"Accept? (y/N):" not in pending, "unrecognized_license_prompt")
                            break
                proc.wait(timeout=min(10, max(0.1, deadline-time.monotonic())))
            finally:
                selector.close()
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=10)
                proc.stdin.close()
                proc.stdout.close()
                record.update({"exitCode": proc.returncode, "elapsedSeconds": time.monotonic()-started,
                               "bytes": len(dialogue), "sha256": sha256(dialogue)})
                self.observe_license_mutation()
                self.save()
        need(proc.returncode == 0, "official_license_command_failed")
        need(self.state["licenseAcceptedForExactText"]
             and self.state["license"]["mutationPolicyPassed"], "exact_official_license_acceptance_not_verified")

    def extract(self, archive_path, kind):
        inventory = zip_inventory(archive_path, kind)
        self.expanded_total += inventory["expandedBytes"]
        need(self.expanded_total <= MAX_EXPANDED_BYTES, "combined_expanded_size_bound")
        need(shutil.disk_usage(self.run_dir).free >= inventory["expandedBytes"] + GIB, "extraction_disk_budget")
        expected = PACKAGES[kind]
        destination = self.sdk / expected["relativeRoot"]
        need(not destination.exists(), "extraction_destination_exists")
        destination.mkdir(mode=0o700, parents=True)
        prefix = inventory["prefix"]
        with zipfile.ZipFile(archive_path) as archive:
            for row in inventory["rows"]:
                self.remaining(1)
                if row["name"] == prefix:
                    need(row["directory"], "archive_root_not_directory")
                    continue
                relative = row["name"][len(prefix)+1:]
                target = destination / relative
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                if row["directory"]:
                    target.mkdir(mode=0o700, exist_ok=True)
                elif not row["symlink"]:
                    count = 0
                    with archive.open(row["zipName"]) as source, target.open("xb") as output:
                        os.chmod(target, 0o700 if row["executable"] else 0o600)
                        while chunk := source.read(MIB):
                            self.remaining(1)
                            count += len(chunk)
                            need(count <= row["bytes"], "extracted_size_changed")
                            output.write(chunk)
                    need(count == row["bytes"], "extracted_size_changed")
            for name, target in inventory["links"].items():
                (destination / name[len(prefix)+1:]).symlink_to(target)
        return {"expandedBytes": inventory["expandedBytes"], "entries": inventory["fileCount"],
                "safeInternalSymlinks": len(inventory["links"]), "crcVerified": True}

    def prepare_registration_bridge(self, cli):
        """Compile against the real CLI APIs before accepting/downloading anything."""
        need(self.registration_bridge is None, "registration_bridge_already_prepared")
        classpath = cli/"lib/sdkmanager-classpath.jar"
        need(classpath.is_file() and not classpath.is_symlink(), "official_sdk_classpath_missing")
        java, javac = shutil.which("java"), shutil.which("javac")
        need(java and javac, "existing_java_compiler_missing")
        bridge = self.evidence / "sdk-registration-bridge"
        bridge.mkdir(mode=0o700)
        source = bridge / "RegisterPinnedPackage.java"
        private_write(source, JAVA_REGISTRAR.encode())
        self.state["officialRegistrationBridge"] = {
            "sourceSHA256": sha256(JAVA_REGISTRAR.encode()),
            "classpathJarSHA256": sha256(bounded_read(classpath, MIB)),
            "compiled": False, "executed": False, "compileCalls": 1, "packageCalls": 0,
            "compiledBeforeLicenseAndArchiveRequests": False,
            "actualExistingSDKAPIsCompiledAndExecuted": False,
            "downloadsOrLicenseWrites": False,
        }
        self.save()
        self.command([javac, "-classpath", classpath, "-d", bridge, source],
                     "sdk-official-registrar-compile", 90)
        need((bridge/"RegisterPinnedPackage.class").is_file(), "registration_bridge_class_missing")
        need(all(value == 0 for value in self.state["archiveDownloadRequests"].values())
             and self.state["license"]["acceptanceResponses"] == 0,
             "registration_bridge_compiled_too_late")
        self.state["officialRegistrationBridge"].update({
            "compiled": True, "compiledBeforeLicenseAndArchiveRequests": True,
            "mainClassSHA256": sha256(bounded_read(bridge/"RegisterPinnedPackage.class", MIB)),
        })
        self.registration_bridge = {"java": java, "classpath": classpath, "directory": bridge}
        self.save()

    def register_missing_packages(self):
        need(self.registration_bridge is not None
             and self.state["officialRegistrationBridge"]["compiled"], "registration_bridge_not_prepared")
        missing = [kind for kind in PACKAGES if not (self.sdk/PACKAGES[kind]["relativeRoot"]/"package.xml").exists()]
        if missing:
            java = self.registration_bridge["java"]
            classpath = self.registration_bridge["classpath"]
            bridge = self.registration_bridge["directory"]
            for kind in missing:
                expected = PACKAGES[kind]
                self.state["officialRegistrationBridge"]["packageCalls"] += 1
                self.save()
                self.command([java, "-classpath", str(bridge)+os.pathsep+str(classpath),
                              "RegisterPinnedPackage", self.evidence/("sdk-"+kind+"-catalog.xml"),
                              expected["path"], ".".join(map(str, expected["revision"])),
                              self.sdk/expected["relativeRoot"], LICENSE_SHA1, LICENSE_SHA256],
                             "sdk-official-register-"+kind, 60)
                self.state["packages"][kind]["registrationOrigin"] = "official_InstallerUtil_from_verified_RemotePackage"
                self.state["officialRegistrationBridge"].update({
                    "executed": True, "actualExistingSDKAPIsCompiledAndExecuted": True,
                })
                self.save()
        for kind in PACKAGES:
            self.state["packages"][kind].setdefault("registrationOrigin", "authenticated_archive_or_reused_official_package_xml")
            self.state["packages"][kind]["registration"] = registration_identity(
                self.sdk/PACKAGES[kind]["relativeRoot"]/"package.xml", kind)
        self.save()

    def run(self):
        try:
            self.save()
            for directory in (self.sdk, self.user):
                directory.mkdir(mode=0o700)
            self.downloads.mkdir(mode=0o700, exist_ok=True)
            self.phase("verify-fixed-official-catalogs")
            for kind, expected in PACKAGES.items():
                path = self.evidence / ("sdk-"+kind+"-catalog.xml")
                self.state["catalogs"][kind] = self.fetch(expected["catalog"], path, kind, catalog=True)
                self.state["selection"][kind] = selected_package(bounded_read(path, CATALOG_LIMIT), kind)
                self.save()
            self.phase("reuse-existing-cli-12")
            original_cli = self.system_sdk/"cmdline-tools/latest"
            need(numeric_revision(properties(original_cli/"source.properties").get("Pkg.Revision", "")) == (12, 0, 0),
                 "existing_cli_revision_not_12")
            cli = self.sdk/"cmdline-tools/latest"
            self.state["cliCopy"] = self.copy_tree(original_cli, cli, GIB)
            sdkmanager, avdmanager = cli/"bin/sdkmanager", cli/"bin/avdmanager"
            need(all(path.is_file() and os.access(path, os.X_OK) and self.sdk in path.resolve().parents
                     for path in (sdkmanager, avdmanager)), "private_cli_root_or_executable_invalid")
            self.state["cliCopy"].update({
                "sdkmanagerSHA256": sha256(bounded_read(sdkmanager, MIB)),
                "avdmanagerSHA256": sha256(bounded_read(avdmanager, MIB)),
                "copiedGlobalLicenseRecords": False, "canonicalSDKRootVerified": True})
            version = self.command([sdkmanager, "--sdk_root="+str(self.sdk), "--version"], "sdk-private-cli-version", 45)
            need(re.search(rb"(?m)^12\.0(?:\.0)?\r?$", version) is not None, "actual_cli_version_not_12")
            self.phase("compile-official-registration-bridge")
            self.prepare_registration_bridge(cli)
            self.phase("official-exact-license-dialogue")
            self.accept_only_approved_license(sdkmanager)
            self.phase("acquire-exact-two-packages")
            for kind, expected in PACKAGES.items():
                existing = self.system_sdk/expected["relativeRoot"]
                reusable = False
                if existing.is_dir() and not existing.is_symlink():
                    try:
                        source_identity(existing, kind)
                        if (existing/"package.xml").exists():
                            registration_identity(existing/"package.xml", kind)
                        reusable = True
                    except (Blocked, OSError, UnicodeError, ValueError):
                        reusable = False
                self.state["packages"][kind] = {"origin": "reused_existing_exact" if reusable else "fixed_official_archive",
                                               "registrationOrigin": None, "archive": None}
                if reusable:
                    copied = self.copy_tree(existing, self.sdk/expected["relativeRoot"],
                                            MAX_EXPANDED_BYTES-self.expanded_total)
                    self.expanded_total += copied["bytes"]
                    self.state["packages"][kind]["copy"] = copied
                else:
                    archive = self.downloads/expected["archive"]
                    self.state["packages"][kind]["archive"] = self.fetch(expected["url"], archive, kind)
                    self.state["packages"][kind]["extraction"] = self.extract(archive, kind)
                self.state["packages"][kind]["sourceIdentity"] = source_identity(self.sdk/expected["relativeRoot"], kind)
                if (self.sdk/expected["relativeRoot"]/"package.xml").exists():
                    self.state["packages"][kind]["registrationOrigin"] = (
                        "reused_exact_official_package_xml" if reusable else "authenticated_archive_package_xml")
                self.save()
            self.phase("official-local-package-registration")
            self.register_missing_packages()
            listing = self.command([sdkmanager, "--sdk_root="+str(self.sdk), "--list_installed", "--channel=0"],
                                   "sdk-official-list-installed", 90)
            rows = {}
            for line in listing.decode("utf-8", errors="strict").splitlines():
                fields = [item.strip() for item in line.split("|")]
                if len(fields) >= 2 and fields[0] in (item["path"] for item in PACKAGES.values()):
                    need(fields[0] not in rows, "installed_listing_duplicate_package")
                    rows[fields[0]] = numeric_revision(fields[1])
            need(rows == {item["path"]: item["revision"] for item in PACKAGES.values()}, "official_installed_listing_mismatch")
            for kind in PACKAGES:
                source_identity(self.sdk/PACKAGES[kind]["relativeRoot"], kind)
                registration_identity(self.sdk/PACKAGES[kind]["relativeRoot"]/"package.xml", kind)
            self.observe_license_mutation()
            need(self.state["licenseAcceptedForExactText"] and self.state["license"]["mutationPolicyPassed"],
                 "license_records_changed_after_install")
            self.state.update({"state": "installed_exact_metadata_verified_not_booted", "phase": "complete",
                               "installedExactPackagesVerified": True, "expandedPackageBytes": self.expanded_total,
                               "officialInstalledListingSHA256": sha256(listing),
                               "officialInstalledListingVerified": True})
            self.save()
            return {
                "private_sdk_root": str(self.sdk), "emulator_path": str(self.sdk/"emulator/emulator"),
                "image_path": str(self.sdk/PACKAGES["image"]["relativeRoot"]),
                "avdmanager_path": str(avdmanager), "sdkmanager_path": str(sdkmanager),
                "receipt_path": str(self.receipt_path), "receipt": self.state,
                "ownedDirectories": self.state["ownedDirectories"],
            }
        except BaseException as error:
            self.state["state"] = "blocked"
            self.state["phaseFailure"] = str(error) if isinstance(error, Blocked) else type(error).__name__
            raise
        finally:
            # A later download/registration failure must not erase an acceptance
            # the official tool really wrote after the exact approved prompt.
            try:
                self.observe_license_mutation()
            except Exception as error:
                self.state["license"]["finalObservationFailure"] = type(error).__name__
            self.state["endedAt"] = now()
            self.save()


def install(d19_run_dir: Path, system_sdk: Path) -> dict:
    """One fresh attempt. The caller must admit the reviewed CI source first."""
    return Installer(d19_run_dir, system_sdk).run()
