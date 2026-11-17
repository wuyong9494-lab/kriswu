#!/usr/bin/env python3
"""Offline, read-only preparation for the fixed 2026-11-17 native 27+1 plan.

This program does not stage/decrypt assets, generate a project, build, run tests,
boot a simulator, contact GitHub, approve an environment, or upload anything.
Its only subprocesses are fixed read-only Git and Apple inspection commands.
JSON on stdout describes facts checked now, commands for review, and blockers.
A successful preflight is never a successful native test or device acceptance.

Example (missing real resources / Apple tools deliberately returns nonzero):
  python3 -I -B -S scripts/completion_native_preflight.py \
    --expected-source-sha <40-character-reviewed-commit> \
    --derived-data <absolute-new-derived-data-directory> \
    --device-udid <existing-iPhone-17-Pro-Max-simulator-UDID>

After the caller performs the reviewed builds, supply --built-app,
--native-xctestrun and --ui-xctestrun to inspect the actual products. Capture
identity requires a real existing run ID and an already-obtained GitHub GET
run JSON plus its externally supplied checksum. No run is created here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import plistlib
import re
import stat
import struct
import subprocess
import sys
from pathlib import Path


PLAN_PATH = "docs/acceptance/fighter-completion-native-plan-20261117.json"
PLAN_BYTES = 4022
PLAN_SHA256 = "123d520ec791dce2216f97c316041916ccf8a5841cfa5ae9339e265f4daa0193"
INVENTORY_PATH = ".github/private/fighter-completion-20261117/completion-compiled-inventory.json"
INVENTORY_BYTES = 75826
INVENTORY_SHA256 = "4c8984617203134c7bf3328f3a6e41520bb823063f94d37013cae11839bc97a1"
COMPILED_CONTENT_SHA256 = "1349f10da9ec0f44dadbf0b24bf005b30df84e2cc4f94330829fbb0734da0d1d"
RELEASE_SHA256 = "527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3"
PROJECT_SHA256 = "af496f8ccbcef887a41900a24ab9cad8c0d0c6df8fd7c4d01c9e6ea5f7405263"
RULES_SCRIPT_SHA256 = "c7b3196c946fc3ebccb6bb952a5f80924b9fb8ca2aa2a7a8a193494ad4022458"
RESOURCE_COUNT = 541
RESOURCE_BYTES = 311221653
RESOURCE_RELATIVE = "App/Resources/FighterPrivate"
BRANCH = "codex/fighter-completion-20261117"
REPOSITORY = "wuyong9494-lab/kriswu"
XCODE_VERSION = "26.6"
SIMULATOR_VERSION = "26.5"
SIMULATOR_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
MAX_SOURCE_BYTES = 8_000_000
MAX_RESOURCE_BYTES = 128_000_000
MAX_METADATA_BYTES = 2_000_000
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
SHA1_RE = re.compile(r"[0-9a-f]{40}\Z")
NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,191}\Z")
SELECTOR_RE = re.compile(r"(SiteTests|ArenaFlowTests)/([A-Za-z_][A-Za-z0-9_]*)/(test[A-Za-z0-9_]+)\Z")
SWIFT_LITERAL_RE = re.compile(r'(#+)?("""|")')
SOURCE_DIRS = ("App", "Sources/ShiftCore", "Shared", "Tests/SiteTests", "Tests/ArenaFlowTests", "Widget")
SOURCE_EXTRA_FILES = (PLAN_PATH, INVENTORY_PATH, "project.yml", "App/Info.plist",
                      "scripts/build_fighter_network_rules.py", "Widget/Info.plist")
GENERATED_ENTITLEMENTS = ("App/ShiftReminder.entitlements", "Widget/ShiftWidget.entitlements")
RULES_HELPERS = (
    "project.yml", "App/Info.plist", "Shared/CaptureIntents.swift",
    "Shared/DutyActivity.swift", "Shared/WidgetShared.swift",
    "Sources/ShiftCore/BoneSampler.swift", "App/Services/GLTFModel.swift",
    "App/Services/ArenaOpaquePNG.swift", "App/Services/GameRoom.swift",
    "App/Services/GameRoomDirectIdentity.swift",
)
BUILD_KEYS = (
    "TARGET_NAME", "CONFIGURATION", "PLATFORM_NAME", "SDK_VERSION", "SWIFT_VERSION",
    "XCODE_VERSION_ACTUAL", "IPHONEOS_DEPLOYMENT_TARGET", "SWIFT_OPTIMIZATION_LEVEL",
    "SWIFT_COMPILATION_MODE", "ENABLE_TESTABILITY", "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
    "FIGHTER_ASSET_RELEASE_SHA256",
)
BUILD_SETTINGS = {"FIGHTER_ASSET_RELEASE_SHA256": RELEASE_SHA256, "FIGHTER_XUXIAO_PROFILE_SHA256": ""}
RESOURCE_ENV_OVERRIDES = frozenset(("SERPENT_MATCH_PROFILE", "ERLANG_MATCH_PROFILE", "SERPENT_BASE_CATALOG",
                                   "SERPENT_BOTTLE_PRESENTATION_ORACLE", "SERPENT_BOTTLE_SOURCE_DIRECTORY", "SERPENT_MORPH_DIRECTORY"))
OTHER_COMPILE_EXTENSIONS = frozenset((".m", ".mm", ".c", ".cc", ".cpp", ".cxx", ".s", ".metal", ".h", ".hh", ".hpp", ".hxx"))


class CheckError(Exception):
    """A bounded diagnostic; never include file contents or environment values."""

    def __init__(self, code: str, message: str, *, blocked: bool = False):
        super().__init__(message)
        self.code, self.message, self.blocked = code, message, blocked


def require(condition: bool, code: str, message: str, *, blocked: bool = False):
    if not condition:
        raise CheckError(code, message, blocked=blocked)


def absolute(path) -> Path:
    value = Path(os.path.abspath(os.fspath(path)))
    require("\n" not in str(value) and "\r" not in str(value) and "\0" not in str(value),
            "unsafe-path", "Paths must not contain control characters")
    return value


def nonsymlink(path: Path, *, missing: bool = False) -> Path:
    path = absolute(path)
    for item in [*reversed(path.parents), path]:
        try:
            mode = item.lstat().st_mode
        except FileNotFoundError:
            require(missing, "missing-input", "Required path is absent: " + str(path), blocked=True)
            continue
        require(not stat.S_ISLNK(mode), "symlink", "Symlink paths are not accepted: " + str(item))
    return path


def stamp(value):
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def snapshot(path: Path, *, maximum: int, keep: bool = False, size: int | None = None,
             sha256: str | None = None, prefix_bytes: int = 0) -> dict:
    require(0 <= prefix_bytes <= 512, "prefix-bound", "Unsupported binary-header read bound")
    path = nonsymlink(path)
    before_path = path.lstat()
    require(stat.S_ISREG(before_path.st_mode), "not-regular", "Expected a regular file: " + str(path))
    require(0 < before_path.st_size <= maximum, "file-size", "File is empty or exceeds its bound: " + str(path))
    if size is not None:
        require(before_path.st_size == size, "file-size", "Pinned file size differs: " + str(path))
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    fd = os.open(path, flags)
    parts, length, prefix = [], 0, b""
    digest = hashlib.sha256()
    blob = hashlib.sha1(b"blob " + str(before_path.st_size).encode("ascii") + b"\0")
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and stamp(before) == stamp(before_path),
                "file-race", "File changed before reading: " + str(path))
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            length += len(chunk)
            require(length <= maximum and length <= before.st_size,
                    "file-race", "File grew while reading: " + str(path))
            digest.update(chunk)
            blob.update(chunk)
            if len(prefix) < prefix_bytes:
                prefix += chunk[:prefix_bytes - len(prefix)]
            if keep:
                parts.append(chunk)
        after = os.fstat(fd)
    finally:
        os.close(fd)
    nonsymlink(path)
    require(length == before.st_size and stamp(before) == stamp(after) == stamp(path.lstat()),
            "file-race", "File changed while reading: " + str(path))
    actual = digest.hexdigest()
    if sha256 is not None:
        require(actual == sha256, "file-hash", "Pinned file SHA-256 differs: " + str(path))
    result = {"bytes": length, "sha256": actual, "gitBlobSHA1": blob.hexdigest(), "stamp": stamp(after)}
    if keep:
        result["data"] = b"".join(parts)
    if prefix_bytes:
        result["prefix"] = prefix
    return result


def duplicate_free(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate-json-key", "JSON contains a duplicate object key")
        result[key] = value
    return result


def json_bytes(data: bytes):
    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=duplicate_free,
                          parse_constant=lambda _: (_ for _ in ()).throw(CheckError("json-number", "Nonfinite JSON number")))
    except (UnicodeError, json.JSONDecodeError, RecursionError):
        raise CheckError("invalid-json", "Input is not bounded valid UTF-8 JSON") from None


def json_file(path, *, maximum=MAX_METADATA_BYTES, size=None, sha256=None):
    return json_bytes(snapshot(path, maximum=maximum, keep=True, size=size, sha256=sha256)["data"])


def checked_plist(path):
    class UniqueDictionary(dict):
        def __setitem__(self, key, value):
            require(key not in self, "duplicate-plist-key", "Property list contains a duplicate key")
            super().__setitem__(key, value)
    try:
        value = plistlib.loads(snapshot(path, maximum=MAX_METADATA_BYTES, keep=True)["data"], dict_type=UniqueDictionary)
    except (plistlib.InvalidFileException, ValueError, OverflowError):
        raise CheckError("invalid-plist", "Input is not a supported property list") from None
    require(isinstance(value, dict), "plist-shape", "Expected a dictionary property list")
    return value


def checked_rows(rows):
    require(isinstance(rows, list) and 0 < len(rows) <= 1024, "inventory-shape", "Invalid inventory rows")
    names = []
    for row in rows:
        require(isinstance(row, dict) and set(row) == {"name", "bytes", "sha256"},
                "inventory-shape", "Inventory row fields differ")
        name = row["name"]
        require(isinstance(name, str) and NAME_RE.fullmatch(name) is not None and ".." not in name,
                "inventory-name", "Unsafe inventory filename")
        require(type(row["bytes"]) is int and 0 < row["bytes"] <= MAX_RESOURCE_BYTES,
                "inventory-size", "Invalid inventory file size")
        require(isinstance(row["sha256"], str) and SHA256_RE.fullmatch(row["sha256"]) is not None,
                "inventory-hash", "Invalid inventory hash")
        names.append(name)
    require(names == sorted(set(names)), "inventory-order", "Inventory must have unique names in canonical order")
    return rows


def metadata(root):
    plan = json_file(root / PLAN_PATH, size=PLAN_BYTES, sha256=PLAN_SHA256)
    inv = json_file(root / INVENTORY_PATH, size=INVENTORY_BYTES, sha256=INVENTORY_SHA256)
    require(plan["schema"] == "fighter-completion-native-plan-v1" and plan["execution"] == "not-started"
            and plan["candidateBranch"] == BRANCH and plan["requiredOutcome"] == {
                "nativePassed": 27, "uiPassed": 1, "failures": 0, "skipped": 0},
            "plan-contract", "Pinned plan contract differs")
    require(plan["xcode"] == XCODE_VERSION and plan["simulator"] == "iPhone 17 Pro Max / iOS 26.5"
            and plan["signing"] is False and plan["physicalDeviceAccepted"] is False
            and plan["testflightUpload"] is False, "plan-contract", "Plan execution boundaries differ")
    selectors = plan["nativeSelectors"] + plan["uiSelectors"]
    require(len(plan["nativeSelectors"]) == 27 and len(plan["uiSelectors"]) == 1
            and len(set(selectors)) == 28 and all(SELECTOR_RE.fullmatch(s) for s in selectors),
            "plan-selectors", "Plan must have exactly 27 unique native and one UI selector")
    rows = checked_rows(inv["compiledFiles"])
    canonical = (json.dumps({"buildSettings": inv["buildSettings"], "files": rows},
                           ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
    require(inv["schema"] == "fighter-completion-compiled-inventory-v1"
            and inv["baseCompiledFileCount"] == 540 and inv["compiledFileCount"] == RESOURCE_COUNT
            and len(rows) == RESOURCE_COUNT and sum(r["bytes"] for r in rows) == RESOURCE_BYTES
            and inv["buildSettings"] == BUILD_SETTINGS
            and inv["compiledContentSHA256"] == COMPILED_CONTENT_SHA256
            and hashlib.sha256(canonical).hexdigest() == COMPILED_CONTENT_SHA256,
            "inventory-contract", "Pinned 540+1 inventory identity differs")
    return plan, inv


def readonly_command(argv, *, cwd=None, developer_dir=None, maximum=2_000_000):
    allowed = (("/usr/bin/git", "rev-parse", "HEAD"), ("/usr/bin/git", "rev-parse", "--abbrev-ref", "HEAD"),
               ("/usr/bin/git", "ls-tree", "-rz", "--full-tree", "HEAD"),
               ("/usr/bin/xcodebuild", "-version"), ("/usr/bin/xcrun", "simctl", "list", "-j"),
               ("/usr/bin/xcode-select", "-p"))
    require(tuple(argv) in allowed,
            "command-not-allowed", "Only fixed read-only inspection commands are allowed")
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "GIT_OPTIONAL_LOCKS": "0",
                   "HOME": str(Path.home())}
    if developer_dir is not None:
        environment["DEVELOPER_DIR"] = str(nonsymlink(developer_dir))
    try:
        result = subprocess.run(argv, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise CheckError("inspection-unavailable", "Read-only inspection command could not complete", blocked=True) from None
    require(result.returncode == 0, "inspection-failed", "Read-only inspection command failed", blocked=True)
    require(len(result.stdout) <= maximum, "inspection-output", "Inspection output exceeds its bound")
    return result.stdout


def git(root, *arguments):
    return readonly_command(["/usr/bin/git", *arguments], cwd=root)


def swift_files(root, directory):
    start = nonsymlink(root / directory)
    require(start.is_dir(), "source-directory", "Source directory is missing: " + directory, blocked=True)
    result = []
    for base, directories, files in os.walk(start, followlinks=False):
        for name in directories:
            nonsymlink(Path(base) / name)
        for name in files:
            if Path(name).suffix.lower() in OTHER_COMPILE_EXTENSIONS:
                relative = (Path(base) / name).relative_to(root).as_posix()
                # The pinned project explicitly excludes these private .metal
                # resources from compilation and byte-copies them. The separate
                # mandatory 541 inventory gate still authenticates their bytes.
                copied_shader = re.fullmatch(r"App/Resources/FighterPrivate/(?:SF3H17FX_|SF3D15FX_)[A-Za-z0-9_.-]+\.metal", relative)
                require(copied_shader is not None, "unsupported-compile-input",
                        "XcodeGen would discover a non-Swift compile input outside the reviewed source contract: " + relative)
            if name.endswith(".swift"):
                path = nonsymlink(Path(base) / name)
                result.append(path.relative_to(root).as_posix())
        require(len(result) <= 2048, "source-count", "Too many source files")
    return sorted(result)


def source_snapshot(root, expected):
    require(SHA1_RE.fullmatch(expected) is not None, "source-sha", "Expected source SHA must have 40 lowercase hex characters")
    head = git(root, "rev-parse", "HEAD").decode("ascii").strip()
    require(head == expected, "source-head", "HEAD differs from the caller's reviewed source SHA")
    branch = git(root, "rev-parse", "--abbrev-ref", "HEAD").decode("ascii").strip()
    require(branch == BRANCH, "source-branch", "Checkout is not on the fixed candidate branch")
    tree = {}
    for entry in git(root, "ls-tree", "-rz", "--full-tree", "HEAD").split(b"\0"):
        if not entry:
            continue
        fields, raw_path = entry.split(b"\t", 1)
        mode, kind, oid = fields.decode("ascii").split(" ")
        path = raw_path.decode("utf-8")
        if path.endswith(".swift") and any(path.startswith(d + "/") for d in SOURCE_DIRS):
            tree[path] = (mode, kind, oid)
        elif path in SOURCE_EXTRA_FILES:
            tree[path] = (mode, kind, oid)
    require(set(SOURCE_EXTRA_FILES) <= set(tree), "source-build-input", "A reviewed build input is missing from the commit")
    actual = set()
    for directory in SOURCE_DIRS:
        actual.update(swift_files(root, directory))
    tracked_swift = {name for name in tree if name.endswith(".swift")}
    require(actual == tracked_swift, "source-closure", "Swift source closure differs from the commit (missing or untracked input)")
    require(len(actual) <= 2048, "source-count", "Too many tracked source files")
    files, texts, stamps = {}, {}, {}
    for relative in sorted(tree):
        mode, kind, oid = tree[relative]
        require(mode in ("100644", "100755") and kind == "blob", "source-mode", "Nonregular tracked source: " + relative)
        value = snapshot(root / relative, maximum=MAX_SOURCE_BYTES, keep=True)
        require(value["gitBlobSHA1"] == oid, "source-content", "Working file differs from the reviewed commit: " + relative)
        files[relative] = {"path": relative, "bytes": value["bytes"], "sha256": value["sha256"]}
        stamps[relative] = value["stamp"]
        if relative.endswith(".swift") and relative.startswith("Tests/"):
            texts[relative] = value["data"].decode("utf-8")
    require(git(root, "rev-parse", "HEAD").decode("ascii").strip() == head,
            "source-race", "HEAD changed during source inspection")
    return {"sha": head, "branch": branch, "files": files, "tests": texts, "stamps": stamps}


def source_unchanged(root, source):
    require(git(root, "rev-parse", "HEAD").decode("ascii").strip() == source["sha"],
            "source-race", "HEAD changed during preflight")
    actual = set()
    for directory in SOURCE_DIRS:
        actual.update(swift_files(root, directory))
    require(actual == {p for p in source["files"] if p.endswith(".swift")},
            "source-race", "Swift source closure changed during preflight")
    for relative, expected in source["stamps"].items():
        path = nonsymlink(root / relative)
        require(stamp(path.lstat()) == expected, "source-race", "Reviewed source changed during preflight: " + relative)
    return {"headAndSourceFilesUnchanged": True}


def strip_swift_literals(source):
    """Erase strings/comments while preserving positions and braces in real code.

    This is a bounded lexical check, not a claim that the Apple compiler ran.
    Raw/multiline strings and nested Swift block comments are handled explicitly.
    """
    out = list(source)
    i, size = 0, len(source)
    while i < size:
        start = i
        if source.startswith("//", i):
            end = source.find("\n", i + 2)
            i = size if end < 0 else end
        elif source.startswith("/*", i):
            i += 2
            depth = 1
            while i < size and depth:
                if source.startswith("/*", i): depth += 1; i += 2
                elif source.startswith("*/", i): depth -= 1; i += 2
                else: i += 1
            require(depth == 0, "swift-comment", "Unterminated Swift block comment")
        else:
            match = SWIFT_LITERAL_RE.match(source, i)
            if not match:
                i += 1
                continue
            hashes, quote = match.group(1) or "", match.group(2)
            i += len(match.group(0))
            closing = quote + hashes
            while i < size:
                if source.startswith("\\" + hashes, i):
                    i += len(hashes) + 2
                elif source.startswith(closing, i):
                    i += len(closing)
                    break
                else:
                    i += 1
            else:
                raise CheckError("swift-string", "Unterminated Swift string literal")
        for index in range(start, min(i, size)):
            if out[index] != "\n":
                out[index] = " "
    return "".join(out)


def declared_tests(source):
    tokens = re.findall(r"[A-Za-z_][A-Za-z0-9_]*|[{}():]", strip_swift_literals(source))
    result, stack, pending, index = set(), [], None, 0
    while index < len(tokens):
        token = tokens[index]
        if token in ("class", "extension") and index + 1 < len(tokens):
            name = tokens[index + 1]
            until = index + 2
            while until < len(tokens) and tokens[until] not in ("{", "}"):
                until += 1
            header = tokens[index + 2:until]
            if token == "extension" or "XCTestCase" in header:
                pending = name
        elif token == "{":
            stack.append(pending)
            pending = None
        elif token == "}":
            require(bool(stack), "swift-braces", "Unbalanced Swift braces")
            stack.pop()
        elif token == "func" and stack and stack[-1] is not None:
            following = tokens[index + 1:index + 4]
            if len(following) == 3 and following[0].startswith("test") and following[1:] == ["(", ")"]:
                item = (stack[-1], following[0])
                require(item not in result, "duplicate-test", "Duplicate test method declaration")
                result.add(item)
        index += 1
    require(not stack, "swift-braces", "Unbalanced Swift braces")
    return result


def selectors_check(plan, source):
    found = {}
    for path, text in source["tests"].items():
        target = path.split("/")[1]
        for class_name, method in declared_tests(text):
            selector = "/".join((target, class_name, method))
            require(selector not in found, "duplicate-test", "Test selector has multiple declarations: " + selector)
            found[selector] = path
    selected = plan["nativeSelectors"] + plan["uiSelectors"]
    require(all(s in found for s in selected), "missing-selector", "A required 27+1 test declaration is missing")
    return {"nativeCount": 27, "uiCount": 1, "declarations": [{"selector": s, "file": found[s]} for s in selected],
            "scope": "Lexical source declarations only; native discovery/compilation/execution has not occurred"}


def project_check(root):
    snapshot(root / "project.yml", maximum=MAX_SOURCE_BYTES, sha256=PROJECT_SHA256)
    snapshot(root / "scripts/build_fighter_network_rules.py", maximum=MAX_SOURCE_BYTES, sha256=RULES_SCRIPT_SHA256)
    info = checked_plist(root / "App/Info.plist")
    require(info.get("FighterAssetReleaseSHA256") == "$(FIGHTER_ASSET_RELEASE_SHA256)"
            and info.get("FighterXuXiaoProfileSHA256") == "$(FIGHTER_XUXIAO_PROFILE_SHA256)",
            "source-info-pin", "App Info.plist no longer uses the reviewed build pins")
    for relative in GENERATED_ENTITLEMENTS:
        path = nonsymlink(root / relative, missing=True)
        require(not path.exists() or path.is_file(), "generated-build-input",
                "Generated entitlements output is occupied by a non-file")
    return {"projectSHA256": PROJECT_SHA256, "rulesScriptSHA256": RULES_SCRIPT_SHA256,
            "resourceDirectory": str(root / RESOURCE_RELATIVE),
            "nativeScheme": "ShiftReminder", "uiScheme": "ArenaFlow", "sharedDerivedData": True,
            "generatedEntitlements": {"files": list(GENERATED_ENTITLEMENTS),
                                      "source": "Properties inside the pinned project.yml; XcodeGen regenerates these untracked files"},
            "mapping": "Pinned project scans App and explicitly copies source PNG/texture/shader/gzip resources without rewriting"}


def flat_resources(directory, rows):
    checked_rows(rows)
    directory = nonsymlink(directory)
    require(directory.is_dir(), "resources-missing", "Installed clear resource directory is absent", blocked=True)
    before = stamp(directory.stat())
    expected = {r["name"] for r in rows}
    require({p.name for p in directory.iterdir()} == expected, "resource-closure", "Staged directory must contain exactly the pinned flat inventory")
    verified = []
    for row in rows:
        path = directory / row["name"]
        value = snapshot(path, maximum=MAX_RESOURCE_BYTES, size=row["bytes"], sha256=row["sha256"])
        verified.append((path, value["stamp"]))
    require(before == stamp(directory.stat()) and {p.name for p in directory.iterdir()} == expected,
            "resource-race", "Resource directory changed during inspection")
    for path, expected_stamp in verified:
        nonsymlink(path)
        require(stamp(path.lstat()) == expected_stamp, "resource-race", "Resource changed after inspection: " + path.name)
    return {"verifiedFiles": len(rows), "verifiedBytes": sum(r["bytes"] for r in rows),
            "directory": str(directory), "identity": "exact inventory names, sizes and SHA-256; no load claim"}


def installation_check(root, resources):
    require(absolute(resources) == root / RESOURCE_RELATIVE, "installation-pending",
            "Verified resources are outside project.yml's App/Resources/FighterPrivate input; reviewed installation remains pending", blocked=True)
    return {"projectInput": str(root / RESOURCE_RELATIVE), "mappedToProject": True}


def parse_host(version_text, devices, udid):
    match = re.fullmatch(r"Xcode ([0-9.]+)\nBuild version ([A-Za-z0-9]+)\s*", version_text)
    require(match is not None and match.group(1) == XCODE_VERSION,
            "xcode-version", "The fixed plan requires Xcode " + XCODE_VERSION, blocked=True)
    require(isinstance(udid, str) and re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", udid) is not None,
            "simulator-udid", "A caller-selected existing simulator UDID is required", blocked=True)
    runtimes = [r for r in devices.get("runtimes", []) if r.get("version") == SIMULATOR_VERSION
                and r.get("isAvailable") is True and r.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    require(len(runtimes) == 1, "simulator-runtime", "Exactly one available iOS 26.5 runtime is required", blocked=True)
    selected = [d for d in devices.get("devices", {}).get(runtimes[0]["identifier"], []) if d.get("udid") == udid]
    require(len(selected) == 1 and selected[0].get("isAvailable") is True
            and selected[0].get("deviceTypeIdentifier") == SIMULATOR_TYPE,
            "simulator-device", "Selected UDID is not an available iPhone 17 Pro Max on iOS 26.5", blocked=True)
    return {"xcode": match.group(1), "xcodeBuild": match.group(2), "runtime": SIMULATOR_VERSION,
            "runtimeIdentifier": runtimes[0]["identifier"], "deviceTypeIdentifier": SIMULATOR_TYPE,
            "deviceUDID": udid, "deviceState": selected[0].get("state"),
            "physicalDeviceAccepted": False}


def host_check(udid, developer_dir):
    require(platform.system() == "Darwin", "apple-host-unavailable",
            "Apple SDK, SceneKit, Xcode and the requested iOS simulator cannot be validated on this host", blocked=True)
    if developer_dir is None:
        selected = readonly_command(["/usr/bin/xcode-select", "-p"]).decode("utf-8").strip()
        require(Path(selected).is_absolute(), "developer-directory", "xcode-select did not return an absolute Developer directory", blocked=True)
        developer_dir = nonsymlink(Path(selected))
    else:
        developer_dir = nonsymlink(developer_dir)
    require(developer_dir.is_dir() and developer_dir.name == "Developer" and developer_dir.parent.name == "Contents"
            and developer_dir.parent.parent.suffix == ".app", "developer-directory", "Selected Developer directory is not inside an Xcode App", blocked=True)
    version = readonly_command(["/usr/bin/xcodebuild", "-version"], developer_dir=developer_dir).decode("utf-8")
    devices = json_bytes(readonly_command(["/usr/bin/xcrun", "simctl", "list", "-j"], developer_dir=developer_dir))
    value = parse_host(version, devices, udid)
    choices = [p for p in (Path("/opt/homebrew/bin/xcodegen"), Path("/usr/local/bin/xcodegen")) if p.is_file() and os.access(p, os.X_OK)]
    require(bool(choices), "xcodegen-unavailable", "XcodeGen is required at /opt/homebrew/bin or /usr/local/bin for project generation", blocked=True)
    value["xcodegen"] = str(choices[0].resolve(strict=True))
    value["xcodegenSelection"] = "First available executable: /opt/homebrew/bin/xcodegen, then /usr/local/bin/xcodegen"
    value["developerDirectory"] = str(developer_dir)
    return value


def capture_check(run_id, receipt, receipt_sha, expected):
    require(all((run_id, receipt, receipt_sha)), "capture-run-missing",
            "UI evidence is blocked without a real existing GitHub run ID and its previously obtained GET JSON plus external checksum; no new run is requested", blocked=True)
    require(re.fullmatch(r"[1-9][0-9]{0,19}", run_id) is not None and SHA256_RE.fullmatch(receipt_sha) is not None,
            "capture-run-format", "Invalid capture run ID or external JSON checksum")
    data = json_file(receipt, sha256=receipt_sha)
    require(type(data.get("id")) is int and str(data["id"]) == run_id and type(data.get("run_attempt")) is int
            and data["run_attempt"] == 1 and data.get("head_sha") == expected and data.get("head_branch") == BRANCH
            and data.get("repository", {}).get("full_name") == REPOSITORY
            and data.get("html_url") == f"https://github.com/{REPOSITORY}/actions/runs/{run_id}",
            "capture-run-identity", "Existing GitHub run receipt does not match the reviewed source, branch, repository and first attempt")
    return {"runID": run_id, "runAttempt": 1, "sourceSHA": expected, "receiptSHA256": receipt_sha,
            "receiptProvenance": "Caller supplied existing GET response; checksum checks bytes, not independent GitHub authenticity",
            "runStatus": data.get("status"), "runConclusion": data.get("conclusion"),
            "environment": {"FIGHTER_CAPTURE_SOURCE_SHA": expected, "FIGHTER_CAPTURE_RUN_ID": run_id,
                            "FIGHTER_CAPTURE_RUN_ATTEMPT": "1"},
            "testResultInherited": False}


def rules_fingerprint(files, build):
    def framed(value):
        data = str(value).encode("utf-8")
        return str(len(data)).encode("ascii") + b":" + data
    result = bytearray(b"fighter-network-rules-v1\n")
    result.extend(framed(len(build)))
    for key in sorted(build):
        result.extend(framed(key)); result.extend(framed(build[key]))
    result.extend(framed(len(files)))
    for row in files:
        for key in ("path", "bytes", "sha256"):
            result.extend(framed(row[key]))
    return hashlib.sha256(result).hexdigest()


def rules_check(path, source, info, host):
    data = json_file(path, maximum=262144)
    require(set(data) == {"schemaVersion", "recipe", "build", "files", "fingerprint"}
            and data["schemaVersion"] == 1 and data["recipe"] == "fighter-network-rules-v1",
            "rules-schema", "Compiled rules manifest has the wrong schema")
    expected = sorted((r for p, r in source["files"].items()
                       if p in RULES_HELPERS or (p.endswith(".swift") and any(p.startswith(d + "/") for d in SOURCE_DIRS[:3]))),
                      key=lambda r: r["path"])
    require(data["files"] == expected, "compiled-source-inputs", "Compiled rules manifest does not match every reviewed source input")
    build = data["build"]
    require(isinstance(build, dict) and set(build) == {"mode", *BUILD_KEYS}
            and all(isinstance(v, str) and len(v) <= 256 and re.fullmatch(r"[A-Za-z0-9_.+ =()$-]*", v) for v in build.values()),
            "rules-build", "Compiled rules build context is invalid")
    exact = {"mode": "xcode", "TARGET_NAME": "ShiftReminder", "CONFIGURATION": "Debug",
             "PLATFORM_NAME": "iphonesimulator", "SWIFT_VERSION": "5.0", "ENABLE_TESTABILITY": "YES",
             "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "FIGHTER_ASSET_RELEASE_SHA256": RELEASE_SHA256}
    require(all(build.get(k) == v for k, v in exact.items()), "rules-build", "Compiled build context differs from the reviewed debug simulator recipe")
    require(build["XCODE_VERSION_ACTUAL"] == "2660" and info.get("DTXcode") == "2660"
            and info.get("DTXcodeBuild") == host["xcodeBuild"]
            and info.get("DTPlatformName") == "iphonesimulator"
            and info.get("DTSDKName") == "iphonesimulator" + build["SDK_VERSION"]
            and re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", build["SDK_VERSION"]) is not None,
            "compiled-xcode", "App and rules SDK/Xcode metadata do not agree with the inspected Apple host")
    require(data["fingerprint"] == rules_fingerprint(expected, build), "rules-fingerprint", "Compiled rules fingerprint differs")
    return {"fingerprint": data["fingerprint"], "sourceFiles": len(expected), "build": build,
            "scope": "Source manifest matches this checkout; this is not independent machine-code provenance"}


def bundle_identity(path, expected_identifier):
    path = nonsymlink(path)
    require(path.is_dir(), "bundle-missing", "Required built bundle is absent", blocked=True)
    info = checked_plist(path / "Info.plist")
    name = info.get("CFBundleExecutable")
    require(isinstance(name, str) and NAME_RE.fullmatch(name) and ".." not in name,
            "bundle-executable", "Unsafe bundle executable name")
    require(info.get("CFBundleIdentifier") == expected_identifier, "bundle-identity", "Built bundle identifier differs")
    paths = [path / name]
    if (path / (name + ".debug.dylib")).exists():
        paths.append(path / (name + ".debug.dylib"))
    records = []
    for executable in paths:
        kind = 6 if executable != path / name else (8 if path.suffix == ".xctest" else 2)
        row = executable_identity(executable, kind)
        records.append({"name": executable.name, **row})
    return info, {"path": str(path), "bundleIdentifier": expected_identifier, "executables": records}


def executable_identity(path, file_type):
    require(nonsymlink(path).stat().st_mode & 0o111 != 0, "executable-permission", "Bundle executable lacks its execute permission")
    row = snapshot(path, maximum=256_000_000, prefix_bytes=512)
    prefix, size = row["prefix"], row["bytes"]
    magic = prefix[:4]
    if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        require(len(prefix) >= 32, "macho-header", "Truncated 64-bit Mach-O header")
        endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
        _, cpu, _, kind, count, commands_size, _, _ = struct.unpack(endian + "8I", prefix[:32])
        require(cpu in (0x01000007, 0x0100000c) and kind == file_type and 0 < count <= 4096
                and 8 * count <= commands_size <= size - 32,
                "macho-header", "Mach-O architecture, executable kind or load-command bounds are invalid")
        format_name = "64-bit Mach-O header"
    elif magic in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
        require(len(prefix) >= 8, "macho-header", "Truncated fat Mach-O header")
        endian = ">" if magic[0] == 0xca else "<"
        wide = magic in (b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca")
        count = struct.unpack(endian + "I", prefix[4:8])[0]
        entry_size = 32 if wide else 20
        require(1 <= count <= 8 and len(prefix) >= 8 + count * entry_size,
                "macho-header", "Fat Mach-O architecture table is invalid")
        ranges, cpus = [], set()
        for index in range(count):
            fields = struct.unpack(endian + ("IIQQII" if wide else "5I"), prefix[8 + index * entry_size:8 + (index + 1) * entry_size])
            cpu, _, offset, length, alignment = fields[:5]
            require(cpu in (0x01000007, 0x0100000c) and cpu not in cpus and 0 <= alignment <= 30
                    and offset >= 8 + count * entry_size and length >= 32 and offset + length <= size
                    and offset % (1 << alignment) == 0,
                    "macho-header", "Fat Mach-O slice bounds are invalid")
            cpus.add(cpu)
            ranges.append((offset, offset + length))
        ordered = sorted(ranges)
        require(all(a[1] <= b[0] for a, b in zip(ordered, ordered[1:])), "macho-header", "Fat Mach-O slices overlap")
        format_name = "fat Mach-O container header"
    else:
        raise CheckError("macho-header", "Bundle executable has no supported Mach-O/fat magic")
    return {"bytes": size, "sha256": row["sha256"], "checkedFormat": format_name,
            "semanticOrSignatureValidation": False}


def app_resources(app, rows):
    expected = {r["name"]: r for r in checked_rows(rows)}
    found = {name: [] for name in expected}
    scanned, directory_stamps = 0, []
    for base, directories, files in os.walk(nonsymlink(app), followlinks=False):
        directory_stamps.append((Path(base), stamp(Path(base).stat())))
        for name in directories:
            nonsymlink(Path(base) / name)
        for name in files:
            path = nonsymlink(Path(base) / name)
            scanned += 1
            require(scanned <= 20000, "app-file-count", "App resource scan exceeds its bound")
            if name in expected:
                found[name].append(path)
            elif path.suffix.lower() in (".pem", ".key", ".pkcs8", ".p12", ".pfx", ".enc", ".cms"):
                raise CheckError("private-material-in-app", "Key or protected-staging material must not be packaged into the App")
            elif name.startswith(("SF3", "Fidelity_")):
                raise CheckError("unlisted-app-resource", "App contains a private resource outside the pinned inventory")
    require(all(len(paths) == 1 for paths in found.values()), "compiled-resource-closure", "An expected App resource is missing or appears more than once")
    containers = {paths[0].parent for paths in found.values()}
    require(len(containers) == 1 and next(iter(containers)) in (app, app / "FighterPrivate"),
            "compiled-resource-location", "All pinned files must share the loader's one App-root or FighterPrivate directory")
    verified = []
    for name, row in expected.items():
        require(len(found[name]) == 1, "compiled-resource-closure", "Missing or duplicate App resource: " + name)
        path = found[name][0]
        value = snapshot(path, maximum=MAX_RESOURCE_BYTES, size=row["bytes"], sha256=row["sha256"])
        verified.append((path, value["stamp"]))
    for path, previous in verified:
        nonsymlink(path)
        require(stamp(path.lstat()) == previous, "app-resource-race", "Compiled App resource changed during inspection")
    for directory, previous in directory_stamps:
        nonsymlink(directory)
        require(stamp(directory.stat()) == previous, "app-resource-race", "Compiled App directory closure changed during inspection")
    return {"verifiedFiles": len(rows), "verifiedBytes": sum(r["bytes"] for r in rows),
            "compiledContentSHA256": COMPILED_CONTENT_SHA256, "loaderResourceDirectory": str(next(iter(containers)))}


def within(path, directory):
    return path == directory or directory in path.parents


def plan_path(value, testroot, derived_data, host_path=None):
    require(isinstance(value, str) and value, "xctestrun-path", "Missing xctestrun bundle path")
    replacements = {"__TESTROOT__": str(testroot)}
    if host_path is not None:
        replacements["__TESTHOST__"] = str(host_path)
    for token, replacement in replacements.items():
        value = value.replace(token, replacement)
    require("__" not in value and "$" not in value and Path(value).is_absolute()
            and ".." not in Path(value).parts, "xctestrun-path", "Unsupported or escaping xctestrun path placeholder")
    path = nonsymlink(Path(value))
    require(within(path, derived_data), "xctestrun-escape", "Built product path escapes the reviewed DerivedData")
    return path


def host_bundle(path):
    # Apple xcodebuild.xctestrun(5): __TESTHOST__ denotes TestHostPath's
    # directory. Do not silently reinterpret the TEST_HOST build setting's
    # executable form as an observed/verified xctestrun directory contract.
    require(path.is_dir() and path.suffix == ".app", "test-host-layout",
            "This app-hosted plan requires an App directory in TestHostPath; other forms need actual Xcode evidence", blocked=True)
    return path


def test_environment(target, test, host, testroot, derived_data, developer_dir):
    required = target.get("TestingEnvironmentVariables")
    environment = target.get("EnvironmentVariables", {})
    app_environment = target.get("UITargetAppEnvironmentVariables", {})
    for group in (required, environment, app_environment):
        require(isinstance(group, dict) and len(group) <= 256
                and all(isinstance(k, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,127}", k)
                        and isinstance(v, str) and len(v) <= 4096 and "\0" not in v for k, v in group.items()),
                "test-environment", "Test environments must be bounded string dictionaries, including required TestingEnvironmentVariables")
        require(RESOURCE_ENV_OVERRIDES.isdisjoint(group), "resource-environment-override",
                "Test environment overrides the installed Bundle resource inputs")
    require(all(environment[k] == required[k] for k in set(environment) & set(required)),
            "test-environment-conflict", "Scheme and testing environments give conflicting values to the test host")
    substitutions = {"__TESTROOT__": testroot, "__TESTHOST__": host, "__TESTBUNDLE__": test}
    permitted_roots = [derived_data / "Build/Products"]
    if developer_dir is not None:
        developer = nonsymlink(developer_dir)
        substitutions.update({"__PLATFORMS__": developer / "Platforms", "__SHAREDFRAMEWORKS__": developer.parent / "SharedFrameworks"})
        permitted_roots += [developer, developer.parent / "SharedFrameworks"]
    host_info = checked_plist(host / "Info.plist")
    injection = {"XCInjectBundle": test, "XCTestBundlePath": test,
                 "XCInjectBundleInto": host / host_info["CFBundleExecutable"]}
    path_lists = {"DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES",
                  "DYLD_FALLBACK_FRAMEWORK_PATH", "DYLD_FALLBACK_LIBRARY_PATH"}
    checked_count = 0
    for key, raw in {**required, **environment}.items():
        if key not in injection and key not in path_lists:
            continue
        values = raw.split(":") if key in path_lists else [raw]
        require(bool(values) and all(values), "test-environment-path", "Empty injected path is not permitted")
        for value in values:
            # Only TestingEnvironmentVariables has documented placeholder expansion.
            if key in required:
                for token, replacement in substitutions.items():
                    value = value.replace(token, str(replacement))
            require("__" not in value and "$" not in value and Path(value).is_absolute() and ".." not in Path(value).parts,
                    "test-environment-path", "Unresolved or escaping test injection/search path", blocked=True)
            resolved = nonsymlink(Path(value))
            require(any(within(resolved, root) for root in permitted_roots),
                    "test-environment-path", "Test injection/search path is outside reviewed Products and the inspected Xcode")
            if key in injection:
                require(resolved == injection[key], "test-injection-target", "Test injection points at another bundle or host")
            checked_count += 1
    return {"testingEnvironmentPresent": True, "checkedInjectionOrSearchPaths": checked_count,
            "resourceOverrides": 0, "environmentValuesPublished": False}


def xctestrun_check(path, *, target_name, selectors, app, derived_data, capture=None, developer_dir=None):
    path = nonsymlink(path)
    require(within(path, derived_data / "Build/Products"), "xctestrun-location", "xctestrun must stay inside the actual Build/Products directory")
    data = checked_plist(path)
    version = data.get("__xctestrun_metadata__", {}).get("FormatVersion", 1)
    require(type(version) is int and version in (1, 2)
            and ((version == 2) == ("TestConfigurations" in data)),
            "xctestrun-format", "xctestrun format metadata must agree with its v1/v2 structure")
    def no_hidden_skip(value):
        if isinstance(value, dict):
            for key, item in value.items():
                require(key not in ("SkipTestIdentifiers", "SkipTests", "IsSkipped") or not item,
                        "test-skip", "A skip setting exists inside the test configuration")
                require(key != "UseDestinationArtifacts" or item is False,
                        "destination-artifacts", "The plan may not substitute unverified artifacts already installed on the simulator")
                no_hidden_skip(item)
        elif isinstance(value, list):
            for item in value:
                no_hidden_skip(item)
    no_hidden_skip(data)
    if "TestConfigurations" in data:
        configs = data["TestConfigurations"]
        require(isinstance(configs, list) and len(configs) == 1 and configs[0].get("IsEnabled", True) is True,
                "test-configuration", "Exactly one enabled test configuration is required")
        targets = configs[0].get("TestTargets", [])
    else:
        targets = [value for key, value in data.items() if key != "__xctestrun_metadata__"
                   and isinstance(value, dict) and "TestBundlePath" in value]
    require(isinstance(targets, list) and len(targets) == 1 and targets[0].get("BlueprintName") == target_name,
            "test-target", "Expected exactly the reviewed test target in its scheme plan")
    target = targets[0]
    expected = [s.split("/", 1)[1] for s in selectors]
    require(target.get("IsEnabled", True) is True and not target.get("SkipTestIdentifiers")
            and not target.get("IsSkipped", False) and not target.get("SkipTests", False),
            "test-skip", "Disabled or skipped test target is forbidden")
    only = target.get("OnlyTestIdentifiers", [])
    require(only == [] or (isinstance(only, list) and len(only) == len(expected) and set(only) == set(expected)),
            "test-selection", "xctestrun selection differs from the full required target subset")
    ui = target_name == "ArenaFlowTests"
    require(target.get("IsUITestBundle", False) is ui, "test-kind", "Native/UI test bundle kind differs")
    host = host_bundle(plan_path(target.get("TestHostPath"), path.parent, derived_data))
    test = plan_path(target.get("TestBundlePath"), path.parent, derived_data, host)
    require(test.name == target_name + ".xctest" and test.parent == host / "PlugIns",
            "test-bundle-layout", "The test bundle must be the expected immediate PlugIns child of its actual host")
    environment_check = test_environment(target, test, host, path.parent, derived_data, developer_dir)
    if ui:
        require(host_bundle(plan_path(target.get("UITargetAppPath"), path.parent, derived_data, host)) == app,
                "ui-app-host", "UI plan points at a different App")
        require(capture is not None, "capture-run-missing", "UI plan requires verified existing run identity", blocked=True)
        environment = target.get("EnvironmentVariables", {})
        require(isinstance(environment, dict) and all(environment.get(k) == v for k, v in capture["environment"].items()),
                "capture-plan", "UI xctestrun must already contain the exact verified capture identity", blocked=True)
        _, runner = bundle_identity(host, "com.kriswu.shiftreminder.arenaflowtests.xctrunner")
    else:
        require(host == app, "native-app-host", "Native plan points at a different App")
        runner = None
    _, test_identity = bundle_identity(test, "com.kriswu.shiftreminder." + ("arenaflowtests" if ui else "sitetests"))
    return {"path": str(path), "sha256": snapshot(path, maximum=MAX_METADATA_BYTES)["sha256"],
            "target": target_name, "selectedCount": len(expected), "skipCount": 0,
            "formatVersion": version, "hostPath": str(host), "testBundle": test_identity, "runner": runner,
            "environment": environment_check}


def isolated_argv(argv, host):
    # Reviewable argv with no inherited caller secrets or SERPENT/ERLANG overrides.
    prefix = ["/usr/bin/env", "-i", "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=" + str(Path.home()), "LC_ALL=C"]
    if host["developerDirectory"]:
        prefix.append("DEVELOPER_DIR=" + host["developerDirectory"])
    return prefix + argv


def build_commands(root, derived_data, host):
    require(derived_data is not None, "derived-data-missing", "An explicit separate DerivedData path is required", blocked=True)
    derived_data = nonsymlink(derived_data, missing=True)
    require(not within(derived_data, root) and not within(root, derived_data),
            "derived-data-overlap", "DerivedData and the source checkout must not overlap")
    commands = [{"purpose": "Generate the reviewed project", "cwd": str(root),
                 "argv": isolated_argv([host["xcodegen"], "generate", "--spec", str(root / "project.yml"), "--project", str(root)], host)}]
    for scheme in ("ShiftReminder", "ArenaFlow"):
        commands.append({"purpose": "Build without running: " + scheme, "cwd": str(root),
                         "argv": isolated_argv(["/usr/bin/xcodebuild", "build-for-testing", "-project", str(root / "ShiftReminder.xcodeproj"),
                                  "-scheme", scheme, "-configuration", "Debug", "-sdk", "iphonesimulator",
                                  "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(derived_data),
                                  "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
                                  "FIGHTER_ASSET_RELEASE_SHA256=" + RELEASE_SHA256, "FIGHTER_XUXIAO_PROFILE_SHA256="], host)})
    return commands


def test_commands(root, derived_data, host, native, ui, plan):
    """Reviewed argv only. Actual results must prove 27+1 passed and zero skips."""
    commands = []
    for label, config, selectors in (("native", native, plan["nativeSelectors"]), ("ui", ui, plan["uiSelectors"])):
        result = nonsymlink(derived_data / ("completion-" + label + ".xcresult"), missing=True)
        require(not result.exists(), "result-already-exists",
                "The proposed xcresult path already exists; review existing evidence instead of silently repeating a run", blocked=True)
        commands.append({"purpose": "Execute the reviewed " + label + " selectors once", "cwd": str(root),
                         "argv": isolated_argv(["/usr/bin/xcodebuild", "test-without-building", "-xctestrun", config["path"],
                                  "-destination", "platform=iOS Simulator,id=" + host["deviceUDID"],
                                  "-parallel-testing-enabled", "NO", "-test-iterations", "1",
                                  "-resultBundlePath", str(result), *["-only-testing:" + s for s in selectors]], host),
                         "requiredResult": {"passed": len(selectors), "failures": 0, "skipped": 0}, "executed": False})
    return commands


def checked(name, action, checks):
    try:
        value = action()
    except CheckError as error:
        checks[name] = {"status": "blocked" if error.blocked else "failed", "code": error.code, "reason": error.message}
        return None
    except (OSError, KeyError, TypeError, ValueError, UnicodeError, RecursionError, AttributeError, IndexError):
        checks[name] = {"status": "failed", "code": "invalid-input", "reason": "Malformed, unsupported or concurrently changed input; no contents logged"}
        return None
    checks[name] = {"status": "passed", "details": value}
    return value


def dependency(checks, name, reason):
    checks[name] = {"status": "blocked", "code": "dependency", "reason": reason}


def run(args):
    checks = {}
    root = absolute(args.repo)
    resources = absolute(args.resources) if args.resources else root / RESOURCE_RELATIVE
    derived = absolute(args.derived_data) if args.derived_data else None
    report = {"schema": "fighter-completion-native-preflight-v1", "execution": "not-started",
              "phase": "post-build" if any((args.built_app, args.native_xctestrun, args.ui_xctestrun)) else "prepare-build",
              "expectedSourceSHA": args.expected_source_sha, "repository": REPOSITORY, "candidateBranch": BRANCH,
              "pins": {"planSHA256": PLAN_SHA256, "inventorySHA256": INVENTORY_SHA256,
                       "compiledContentSHA256": COMPILED_CONTENT_SHA256, "releaseSHA256": RELEASE_SHA256},
              "checks": checks, "commandsForReview": [], "readyForBuild": False, "readyForTests": False,
              "binarySourceProvenanceVerified": False,
              "nativePassed": None, "uiPassed": None, "physicalDeviceAccepted": False,
              "workflowStarted": False, "environmentApproved": False, "testflightUploaded": False,
              "limitations": ["This tool never builds, runs, stages, decrypts, uploads or contacts GitHub.",
                              "Source declarations and byte checks are not SceneKit loading, passing native tests, dual-device networking or physical-device acceptance."]}
    values = checked("metadata", lambda: metadata(root), checks)
    if values:
        plan, inv = values
        checks["metadata"]["details"] = {"nativeRequired": 27, "uiRequired": 1, "files": RESOURCE_COUNT,
                                         "bytes": RESOURCE_BYTES, "planSHA256": PLAN_SHA256, "inventorySHA256": INVENTORY_SHA256}
    else:
        plan = inv = None
    source = checked("source", lambda: source_snapshot(nonsymlink(root), args.expected_source_sha), checks)
    if source:
        checks["source"]["details"] = {"sha": source["sha"], "branch": source["branch"],
                                       "checkedFiles": len(source["files"]), "checkedSourceSubsetMatchesCommit": True,
                                       "scope": "Swift under App/ShiftCore/Shared/Widget and the two test targets, plus pinned plan/inventory, project, source identity hook and App/Widget Info; entitlements are generated from pinned project.yml",
                                       "notClaimed": "Entire repository cleanliness or identity of unrelated assets and helpers; 541 private resources are checked separately"}
    project = checked("project", lambda: project_check(root), checks)
    if plan and source:
        checked("selectors", lambda: selectors_check(plan, source), checks)
    else:
        dependency(checks, "selectors", "Pinned plan and reviewed source are required")
    if inv:
        resource_result = checked("resources", lambda: flat_resources(resources, inv["compiledFiles"]), checks)
    else:
        dependency(checks, "resources", "Pinned inventory is required before reading any staged bytes")
        resource_result = None
    if project and resource_result:
        checked("installation", lambda: installation_check(root, resources), checks)
    else:
        dependency(checks, "installation", "Both project mapping and real staged resources must pass")
    host = checked("appleHost", lambda: host_check(args.device_udid, args.developer_dir), checks)
    capture = checked("uiCaptureIdentity", lambda: capture_check(args.capture_run_id, args.capture_run_json,
                                                                args.capture_run_json_sha256, args.expected_source_sha), checks)
    build_gates = ("metadata", "source", "project", "selectors", "resources", "installation", "appleHost")
    if all(checks[n]["status"] == "passed" for n in build_gates):
        commands = checked("buildPreparation", lambda: build_commands(root, derived, host), checks)
        if commands:
            report["commandsForReview"] = commands
            report["readyForBuild"] = True
            checks["buildPreparation"]["details"] = {"commands": len(commands), "sharedDerivedData": str(derived), "executed": False}
    else:
        dependency(checks, "buildPreparation", "Source, exact installed inventory, project mapping and actual Apple host must all pass")
    if report["phase"] == "post-build":
        # This phase only releases test commands after inspecting existing
        # products; it must not suggest repeating the build as a side effect.
        report["commandsForReview"] = []
        if all((source, inv, host, args.built_app, args.native_xctestrun, args.ui_xctestrun, derived)):
            app = absolute(args.built_app)
            def inspect_app():
                require(within(app, derived / "Build/Products"), "app-location", "App must be inside the reviewed DerivedData products")
                info, identity = bundle_identity(app, "com.kriswu.shiftreminder")
                require(info.get("FighterAssetReleaseSHA256") == RELEASE_SHA256 and info.get("FighterXuXiaoProfileSHA256") == "",
                        "compiled-release-pin", "Built App release/founder pins differ")
                return {"bundle": identity, "resources": app_resources(app, inv["compiledFiles"]),
                        "rules": rules_check(app / "FighterNetworkRules.json", source, info, host)}
            built = checked("compiledApp", inspect_app, checks)
            if built:
                native = checked("nativeTestPlan", lambda: xctestrun_check(absolute(args.native_xctestrun), target_name="SiteTests",
                       selectors=plan["nativeSelectors"], app=app, derived_data=derived, developer_dir=Path(host["developerDirectory"])), checks)
                ui = checked("uiTestPlan", lambda: xctestrun_check(absolute(args.ui_xctestrun), target_name="ArenaFlowTests",
                       selectors=plan["uiSelectors"], app=app, derived_data=derived, capture=capture, developer_dir=Path(host["developerDirectory"])), checks)
                if native and ui and report["readyForBuild"]:
                    commands = checked("testPreparation", lambda: test_commands(root, derived, host, native, ui, plan), checks)
                    if commands:
                        report["commandsForReview"] = commands
                        report["readyForTests"] = True
                        checks["testPreparation"]["details"] = {"commands": 2, "executed": False,
                                                                 "meaning": "Declared inputs match actual App and test configurations; no test result or independent binary source provenance is claimed"}
                else:
                    dependency(checks, "testPreparation", "Both actual test plans and build input gates must pass")
            else:
                dependency(checks, "nativeTestPlan", "Actual compiled App inspection must pass")
                dependency(checks, "uiTestPlan", "Actual compiled App inspection must pass")
        else:
            dependency(checks, "compiledApp", "Post-build inspection requires reviewed source, pinned inventory, actual Apple host, DerivedData, App and both xctestrun files")
        report["limitations"].append("Unsigned App hashes and its source manifest do not independently prove compiler provenance. readyForTests means checked input/configuration agreement only; real xcodebuild execution, xcresult and capture evidence remain required.")
    if source:
        final_source = checked("finalSourceIdentity", lambda: source_unchanged(root, source), checks)
        if final_source is None:
            report["commandsForReview"] = []
            report["readyForBuild"] = report["readyForTests"] = False
    required = list(checks)
    okay = all(checks[name]["status"] == "passed" for name in required)
    if not okay:
        report["status"] = "failed" if any(c["status"] == "failed" for c in checks.values()) else "blocked"
    else:
        report["status"] = "prepared-for-review"
    report["blockingChecks"] = [name for name in required if checks[name]["status"] != "passed"]
    return report, 0 if okay else 2


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    result.add_argument("--repo", type=Path, default=Path(__file__).absolute().parent.parent)
    result.add_argument("--expected-source-sha", required=True)
    result.add_argument("--resources", type=Path, help="Existing clear resources; outside project input remains installation-pending")
    result.add_argument("--derived-data", type=Path, help="One explicit directory shared by both reviewed build schemes")
    result.add_argument("--device-udid", help="Existing iPhone 17 Pro Max / iOS 26.5 simulator, never created or booted here")
    result.add_argument("--developer-dir", type=Path, help="Existing selected Xcode Developer directory")
    result.add_argument("--capture-run-id", help="Real existing GitHub run ID, never synthesized")
    result.add_argument("--capture-run-json", type=Path, help="Previously obtained GitHub GET run JSON; tool does not fetch it")
    result.add_argument("--capture-run-json-sha256", help="External SHA-256 of that previously obtained GET response")
    result.add_argument("--built-app", type=Path)
    result.add_argument("--native-xctestrun", type=Path)
    result.add_argument("--ui-xctestrun", type=Path)
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        report, code = run(args)
    except CheckError as error:
        report, code = {"schema": "fighter-completion-native-preflight-v1", "execution": "not-started",
                        "status": "blocked" if error.blocked else "failed", "code": error.code,
                        "reason": error.message, "readyForBuild": False, "readyForTests": False,
                        "nativePassed": None, "uiPassed": None, "commandsForReview": []}, 2
    print(json.dumps(report, ensure_ascii=True, sort_keys=True, indent=2))
    return code


if __name__ == "__main__":
    sys.exit(main())
