#!/usr/bin/env python3
"""One pinned, unsigned Apple source build; no test or private-resource phase."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
WORKFLOW = ".github/workflows/fighter-erlang-source-compile.yml"
HELPER = ".github/scripts/fighter_erlang_source_compile.py"
COMMIT_MESSAGE = "Verify Erlang integrated source 20261115"
PUBLIC_SHADER_COMMIT_MESSAGE = "Verify public fighter shaders 20261115"
INPUTS = ("App", "Sources", "Shared", "Widget", "Tests", "project.yml",
          "scripts/build_fighter_network_rules.py",
          "scripts/check_fighter_public_shaders.py", "scripts/check_fighter_public_shaders.swift")
INPUT_COUNT = 908
INPUT_BYTES = 59442658
INPUT_SHA256 = "95ef15b6917132434ca7a7d5b580e11dfbf15a1172f999b17de7c4ade26854fa"
FOCUS_SHA256 = {
    "App/Services/DuelWeaponAssets.swift": "5d7738a85657ec84d566722a76bf7d5fcbcd1785173696d81fabaf2fa5863153",
    "App/Services/DuelErlangAssetIdentity.swift": "ea77d78f993e2e37fda38dbe796dff382c81f89e7bf475707ba10ee49a3e89f8",
    "App/Services/DuelErlangSourceAudio.swift": "1d6532634d2a057614a6c4d29129292f3661a88d7820c4f8513af145c71eb9b7",
    "App/Services/DuelErlangCompanionAssets.swift": "4cecb0dd4be48db16c04a503152bbdec1b2474e56604ecb4f7f9ef8b0b1a3d44",
    "App/Services/DuelErlangHoundEffects.swift": "2711ea84d48ebf89801797b2182b5f4980f24675d8c8bfefb4d13452992e8cc7",
    "App/Services/DuelErlangStompEffects.swift": "467391658917f1449a7c52d77da25b59661b907fd15436cfc886beba98791194",
    "App/Services/DuelErlangSwordEffects.swift": "f54ff76a15eb64d030ede9b20060169f14afd0a7c969387722402579a1286348",
    "App/Services/DuelTriadSourceMorphAssets.swift": "843f32f779926bde218605458c45032d26bc9ee4f43a367a6f132912c008b32e",
    "App/Services/DuelTriadSourceMorph.swift": "ad36099207430b2ff2dd9dee5cf46fa8e4e426aef76cdb2f6a2041ef751e069c",
    "App/Services/DuelTriadSourceEffects.swift": "38850e2aa5c1099a705f499217eecb61bc698e9cc9c5e8d157fbc7c76cffa9c3",
    "App/Views/DuelWorld.swift": "d8b60cd8fe380de42d386001c84d0cc0d001769a597215b00de8e4aa80716904",
    "Sources/ShiftCore/DuelWeaponFight.swift": "b5a95abb26fc1e715d7996bc149d151dac97d578e2dead426fd24829ab0169c4",
    "Sources/ShiftCore/DuelErlangFightState.swift": "d30d71008bba3b4776c25001750649fafc1772df19d1eead891ee1448a83720e",
    "Sources/ShiftCore/DuelErlangCombatRules.swift": "1751c6ece68059ae5c066ec0e19cb81c5d7a473eea4c350db095715f99c16db6",
    "Sources/ShiftCore/DuelErlangSwordMotion.swift": "0794b1e80d37b95cb89d4399d4202d3b788795bf975f2b091f414cc588b89f91",
    "Sources/ShiftCore/DuelErlangSourceEvent.swift": "a82c49f26327b663f1ec46a3f861be1e8efc3f1b65f590a1e7fe2c1f43bb10d8",
    "scripts/build_fighter_network_rules.py": "50593000b48c128206cffbdde72f71c60daacddae9fe10cc8a76182c49f9ac45",
    "project.yml": "21ad8ca03cafb81c7ad72821627227076da7602a855020f7bbf4b16cdb08c0d1",
    "App/Services/DuelSourceProjectedShadowRenderer.swift": "d2f771207da81e30d53599376155efe54388ad902f98fe3f209a3635b9815788",
    "scripts/check_fighter_public_shaders.py": "54c72257d367305603873da57fd147ab3d9992ed4bf524a6f5d5bb47f3a2ddbf",
    "scripts/check_fighter_public_shaders.swift": "2f58a491c534669afb2926c97521834b0739d11b2a4747f751cacf154710ad59",
    "App/Services/DuelErlangSkillEffects.swift": "352188b11d16aabb5fa60b4ad364e7c524f8cc121aac2282dae0b82208abcaf1",
    "App/Services/DuelErlangSkillEffectClock.swift": "f99ec2a056154b9f0b7cf0539f133e473cdb0158dce6fd3793f6a6c710e979fc",
    "Sources/ShiftCore/DuelImperialHeavyMotion.swift": "ee512668a2f54d400e1f5129e736d6e363938a088a7290acce50fd6b8f3e4f3b",
    "App/Services/DuelErlangParticleFacing.swift": "966ef206f8ee3c369711dfb3600f462b174f803e3a5b0e04604d7ce0c3dee426",
    "App/Services/DuelTriadSourceMaterial.swift": "20d3fa83baedc4f0b81fffa4325ba4d0d6a2132b9de0b1c6e5c6f1bd9fae6e38",
    "Sources/ShiftCore/DuelSourceParticleOrder.swift": "9239b37de1ce9b9ee5d645ecc464dc24952425bff6e2d97d9a7abe9ddf384a97",
    "Sources/ShiftCore/DuelErlangPelvisScale.swift": "4fccf27f2f427943fd6539d71d88d0538527924014b7008eb67ab4f9ba265fc2",
    "Sources/ShiftCore/DuelWeaponMotion.swift": "434405b1158eb27653d273500d6baff8a106f2b799b1e887a40dbf43a8c2ac85",
    "Sources/ShiftCore/DuelReplayState.swift": "9c67310fef401edf66ccd72116ff4cf429f398a5f9bdcfd5424642fe41954d7d",
    "Tests/ShiftCoreTests/DuelErlangPelvisScaleTests.swift": "e36fbaf850a99fc7730b3070f2170805d95a1495e488d453ca97a523cb8c970b"
}

GENERATED_FILES = {"App/ShiftReminder.entitlements", "Widget/ShiftWidget.entitlements"}
PRIVATE_PREFIXES = ("SF3_", "SF3UI_", "SF3FX_", "SF3WE_", "SF3PG_", "SF3H17FX_")
PRIVATE_SUFFIXES = {".enc", ".pem", ".key", ".arenapack", ".texture"}
XCODE = Path("/Applications/Xcode_26.6.app")


class BuildFailure(Exception):
    pass


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT, timeout=30)


def regular(path: Path, maximum: int) -> Path:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= maximum:
        raise BuildFailure("Expected a bounded regular input file")
    if path.resolve(strict=True) != path:
        raise BuildFailure("Source and evidence inputs cannot contain symlinks")
    return path


def validate_event(*, expected_message: str = COMMIT_MESSAGE) -> dict:
    if expected_message not in (COMMIT_MESSAGE, PUBLIC_SHADER_COMMIT_MESSAGE):
        raise BuildFailure("Unknown fixed verification entry")
    expected = os.environ.get("GITHUB_SHA", "")
    event_path = Path(os.environ["GITHUB_EVENT_PATH"])
    event = json.loads(regular(event_path, 4 * 1024**2).read_text())
    head = event.get("head_commit") or {}
    checks = (
        re.fullmatch(r"[a-f0-9]{40}", expected) is not None,
        git("rev-parse", "HEAD").decode().strip() == expected,
        os.environ.get("GITHUB_REPOSITORY") == REPOSITORY,
        os.environ.get("GITHUB_REF") == BRANCH,
        os.environ.get("GITHUB_EVENT_NAME") == "push",
        os.environ.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@" + BRANCH,
        os.environ.get("GITHUB_WORKFLOW_SHA") == expected,
        os.environ.get("GITHUB_RUN_ATTEMPT") == "1",
        re.fullmatch(r"[0-9]+", os.environ.get("GITHUB_RUN_ID", "")) is not None,
        event.get("repository", {}).get("full_name") == REPOSITORY,
        event.get("ref") == BRANCH,
        head.get("id") == expected,
        head.get("message") == expected_message,
        not event.get("deleted", False),
    )
    if not all(checks):
        raise BuildFailure("Repository, branch, workflow, push identity or first-attempt gate failed")
    helper_sha = sha256(regular(ROOT / HELPER, 64 * 1024))
    if helper_sha != os.environ.get("EXPECTED_ERLANG_COMPILE_HELPER_SHA256"):
        raise BuildFailure("The compile helper differs from the workflow's reviewed SHA256")
    if git("diff", "--name-only", "HEAD", "--").strip():
        raise BuildFailure("Checkout contains tracked modifications before compilation")
    return {
        "repository": REPOSITORY, "ref": BRANCH, "sourceSHA": expected,
        "runID": os.environ["GITHUB_RUN_ID"], "attempt": 1,
        "runURL": "https://github.com/" + REPOSITORY + "/actions/runs/" + os.environ["GITHUB_RUN_ID"],
        "workflow": WORKFLOW, "workflowSHA256": sha256(ROOT / WORKFLOW), "helperSHA256": helper_sha,
    }


def no_private_resources() -> None:
    if any(name.startswith("FIGHTER_") and name.endswith("_KEY") for name in os.environ):
        raise BuildFailure("Source-only compilation cannot receive asset keys")
    if os.environ.get("FIGHTER_ASSET_RELEASE_SHA256"):
        raise BuildFailure("Source-only compilation cannot select a private release")
    resources = ROOT / "App/Resources"
    directory = resources / "FighterPrivate"
    if resources.is_symlink() or directory.is_symlink():
        raise BuildFailure("Optional resource directories cannot be symbolic links")
    if directory.exists() and (not directory.is_dir() or any(directory.iterdir())):
        raise BuildFailure("FighterPrivate must be absent or empty")
    if resources.exists() and any(resources.glob("*.arenapack")):
        raise BuildFailure("Source-only compilation cannot install an original arena pack")


def source_inventory(*, generated: bool = False) -> tuple[list[dict], str]:
    """Pin every path, Git mode, byte count and SHA256, including discovery-only Tests."""
    rows = []
    for entry in git("ls-files", "--stage", "-z", "--", *INPUTS).split(b"\0"):
        if not entry:
            continue
        metadata, relative = entry.decode("utf-8").split("\t", 1)
        mode, _, stage = metadata.split()
        if stage != "0" or mode not in ("100644", "100755"):
            raise BuildFailure("Compile inputs must be resolved, regular Git files")
        path = regular(ROOT / relative, 16 * 1024**2)
        rows.append({"path": relative, "mode": mode, "bytes": path.stat().st_size, "sha256": sha256(path)})
    rows.sort(key=lambda row: row["path"])
    paths = {row["path"] for row in rows}
    actual = set()
    for directory in INPUTS[:5]:
        for base, folders, files in os.walk(ROOT / directory, followlinks=False):
            for name in folders:
                if (Path(base) / name).is_symlink():
                    raise BuildFailure("A compile input directory is a symlink")
            for name in files:
                path = regular(Path(base) / name, 16 * 1024**2)
                actual.add(path.relative_to(ROOT).as_posix())
    expected = {path for path in paths if path.split("/", 1)[0] in INPUTS[:5]}
    allowed = GENERATED_FILES if generated else set()
    if actual - allowed != expected:
        raise BuildFailure("Unexpected untracked, ignored or missing file in an engineering input directory")
    canonical = json.dumps(rows, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode("ascii")
    fingerprint = hashlib.sha256(canonical).hexdigest()
    if (len(rows) != INPUT_COUNT or sum(row["bytes"] for row in rows) != INPUT_BYTES
            or fingerprint != INPUT_SHA256):
        raise BuildFailure("The complete compile/discovery input fingerprint differs from review")
    hashes = {row["path"]: row["sha256"] for row in rows}
    if any(hashes.get(path) != pin for path, pin in FOCUS_SHA256.items()):
        raise BuildFailure("Character source, material or build-phase input pin differs from review")
    return rows, fingerprint


def run_logged(command: list[str], label: str, timeout: int, *, work: Path,
               deadline: float, environment: dict, report: dict) -> Path:
    remaining = min(timeout, int(deadline - time.monotonic()))
    if remaining <= 0:
        raise BuildFailure("The one-build time budget is exhausted")
    print("Starting " + label + " (one invocation, no retry).", flush=True)
    started = time.monotonic()
    log = work / (label + ".log")
    with log.open("xb") as output:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            code = 124
    report["commands"].append({"phase": label, "exitCode": code,
                               "seconds": round(time.monotonic() - started, 3),
                               "logBytes": log.stat().st_size, "logSHA256": sha256(log)})
    print(label + " exit code: " + str(code), flush=True)
    if code:
        # This job has only public source/demo inputs and no injected asset secrets.
        # Bound the public failure tail; complete logs remain only in runner temp.
        with log.open("rb") as handle:
            handle.seek(max(0, log.stat().st_size - 48 * 1024))
            tail = handle.read().decode("utf-8", errors="replace").splitlines()[-100:]
        for line in tail:
            print("compile diagnostic | " + line.replace(str(ROOT), "$SOURCE")[:1200])
        raise BuildFailure(label + " failed; no retry was made")
    return log


def check_products(work: Path) -> dict:
    products = work / "derived/Build/Products"
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    info = plistlib.loads(regular(app / "Info.plist", 2 * 1024**2).read_bytes())
    if info.get("FighterAssetReleaseSHA256") not in (None, ""):
        raise BuildFailure("The compiled application unexpectedly enables a private release")
    if list(products.rglob("*.xctest")) or list(products.rglob("*.xctestrun")):
        raise BuildFailure("The build-only job unexpectedly produced a test bundle or test plan")
    for path in app.rglob("*"):
        if path.is_file() and (path.name.startswith(PRIVATE_PREFIXES) or path.suffix in PRIVATE_SUFFIXES):
            raise BuildFailure("The compiled application unexpectedly contains private resources")
    rules_path = regular(app / "FighterNetworkRules.json", 262_144)
    rules = json.loads(rules_path.read_text())
    if (rules.get("build", {}).get("mode") != "xcode"
            or rules["build"].get("TARGET_NAME") != "ShiftReminder"
            or rules["build"].get("FIGHTER_ASSET_RELEASE_SHA256") != ""):
        raise BuildFailure("The normal public-source network-rules build phase is not verified")
    return {"unsignedApplicationBuilt": True, "privateReleaseEnabled": False,
            "testBundlesProduced": 0, "networkRulesSHA256": sha256(rules_path),
            "networkRulesFingerprint": rules.get("fingerprint")}


def main() -> int:
    started = time.monotonic()
    deadline = started + 17 * 60
    report = {"schemaVersion": 1, "status": "blocked", "evidenceType": "source-compile-only",
              "testsExecuted": 0, "simulatorLaunched": False, "deviceValidated": False,
              "privateResourcesStaged": False, "artifactUploaded": False, "commands": [],
              "limitations": ["Compilation is not runtime, simulator or iPhone acceptance.",
                              "Original H17/D15/D19 models, audio and resource closure are not exercised.",
                              "Tests are pinned only because project generation discovers their source paths."]}
    try:
        if sys.platform != "darwin" or len(sys.argv) != 1:
            raise BuildFailure("This fixed compile entry requires macOS and accepts no arguments")
        report.update(validate_event())
        no_private_resources()
        rows, fingerprint = source_inventory()
        report.update({"inputCount": len(rows), "inputBytes": INPUT_BYTES,
                       "inputManifestSHA256": fingerprint, "focusSHA256": FOCUS_SHA256})
        parent = Path(os.environ["RUNNER_TEMP"])
        if not parent.is_absolute() or not parent.is_dir() or parent.is_symlink():
            raise BuildFailure("A real absolute runner temporary directory is required")
        work = parent / "fighter-erlang-source-compile-20261115"
        work.mkdir(mode=0o700, exist_ok=False)
        (work / "source-inputs.json").write_text(json.dumps(rows, sort_keys=True, indent=2) + "\n")
        if not XCODE.is_dir():
            raise BuildFailure("Installed Xcode 26.6 is absent; no Xcode or SDK installation is permitted")
        version = plistlib.loads(regular(XCODE / "Contents/version.plist", 64 * 1024).read_bytes())
        if version.get("CFBundleShortVersionString") != "26.6":
            raise BuildFailure("The selected installed Xcode version is not 26.6")
        report["xcodeVersion"] = version["CFBundleShortVersionString"]
        report["xcodeBuild"] = version.get("ProductBuildVersion")
        environment = dict(os.environ, DEVELOPER_DIR=str(XCODE / "Contents/Developer"),
                           HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_INSTALL_CLEANUP="1",
                           HOMEBREW_NO_ANALYTICS="1", FIGHTER_ASSET_RELEASE_SHA256="")

        def run(command: list[str], label: str, timeout: int) -> Path:
            return run_logged(command, label, timeout, work=work, deadline=deadline,
                              environment=environment, report=report)

        xcodegen = shutil.which("xcodegen")
        report["xcodegenInstalledByThisRun"] = xcodegen is None
        if xcodegen is None:
            brew = shutil.which("brew")
            if brew is None:
                raise BuildFailure("Neither xcodegen nor the established Homebrew build dependency installer is present")
            run([brew, "install", "xcodegen"], "install-xcodegen", 240)
            xcodegen = shutil.which("xcodegen")
            if xcodegen is None:
                raise BuildFailure("The single xcodegen installation did not make the tool available")
        version_log = run([xcodegen, "--version"], "xcodegen-version", 30)
        report["xcodegenVersion"] = version_log.read_text().strip()[:256]
        no_private_resources()
        (ROOT / "App/Resources/FighterPrivate").mkdir(mode=0o700, parents=True, exist_ok=True)
        run([xcodegen, "generate"], "generate-project", 120)
        source_inventory(generated=True)
        # The unchanged project.yml retains its normal network-rules build phase.
        # A generic simulator destination compiles without booting a simulator.
        (work / "build-started").open("x").close()
        run([str(XCODE / "Contents/Developer/usr/bin/xcodebuild"), "build",
             "-project", "ShiftReminder.xcodeproj", "-scheme", "ShiftReminder",
             "-configuration", "Debug", "-sdk", "iphonesimulator",
             "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(work / "derived"),
             "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
             "FIGHTER_ASSET_RELEASE_SHA256=", "SWIFT_EMIT_LOC_STRINGS=NO"], "unsigned-source-build", 840)
        source_inventory(generated=True)
        no_private_resources()
        report["products"] = check_products(work)
        report["status"] = "compiled"
    except (BuildFailure, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report["failure"] = str(error).replace(str(ROOT), "$SOURCE")[:1000]
        if any(row["phase"] == "unsigned-source-build" for row in report["commands"]):
            report["status"] = "failed"
    finally:
        report["elapsedSeconds"] = round(time.monotonic() - started, 3)
        encoded = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2)
        print(encoded, flush=True)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as handle:
                handle.write("## Erlang character source compilation\n\n" +
                             "Compile evidence only; no tests, simulator launch, original-resource staging or device validation.\n\n" +
                             "```json\n" + encoded + "\n```\n")
    return 0 if report["status"] == "compiled" else 1


if __name__ == "__main__":
    sys.exit(main())
