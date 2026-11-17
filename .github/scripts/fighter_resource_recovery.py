#!/usr/bin/env python3
"""Recover five pinned, already stored resources into a recipient-only envelope.

This job has its own immutable source and one-push scope. It never invokes old
acceptance workflow entry points, changes their guards, builds an App, runs a
game, signs, calls Apple, publishes plaintext or recovers source credentials.
"""
from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
import hashlib
import importlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
PARENT_SHA = "b91f63dcbd6b19bf4b717a269856d6a46ef0c55c"
SOURCE_SHA = "13e23f617d38180120f48870f206779e9d3c1d32"
COMMIT_TITLE = "Recover exact stored fighter inputs with canonical test paths 20261117"
HELPER = ".github/scripts/fighter_resource_recovery.py"
TEST = ".github/scripts/test_fighter_resource_recovery.py"
WORKFLOW = ".github/workflows/fighter-resource-recovery.yml"
ALLOWED_CHANGES = frozenset((HELPER, TEST, WORKFLOW))
SOURCE_ROOT = ROOT / "recovery-source"
WORK_NAME = "fighter-resource-recovery-20261117"
KEYS = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_H17_D19_KEY")
CERTIFICATE_SHA = "939a58d21ad2b1cf25abca8b4a4241fa28a83d0608ff66f1e5b21d449045c6fb"
RECIPIENT_SPKI_SHA = "64ea9fef86fcdeee1cf1780158437cce28f8b4ebf471c09830908f8ba3f9bc78"
CERTIFICATE_PEM = b'-----BEGIN CERTIFICATE-----\nMIIENzCCAp+gAwIBAgIUGvwbbomuUPPjaAcdU9BEblLUDYwwDQYJKoZIhvcNAQEL\nBQAwKzEpMCcGA1UEAwwgRmlnaHRlciBTb3VyY2UgUmVjb3ZlcnkgMjAyNjExMTcw\nHhcNMjYxMTE3MDQxNTA2WhcNMjYxMTE5MDQxNTA2WjArMSkwJwYDVQQDDCBGaWdo\ndGVyIFNvdXJjZSBSZWNvdmVyeSAyMDI2MTExNzCCAaIwDQYJKoZIhvcNAQEBBQAD\nggGPADCCAYoCggGBAOIUNa6Ld9eobDiFopyX/d0oHXqiEIg3gJ9gyYMrhxw3czlC\nBzgzCBcYUg1tPwKj4T/I8yJjRO35JgZfOq1s+aqA9APqez4SLlcQv4AciCrhuogt\neKziteqWRxWHerTjEu+1ox0KD4omuE6kURjXy64DOMdYt/y/zjTdzSkNDzmFsm8H\nX5PG0XunOgYBrv8YTDQPpk/s42U2yICLXYaySVHxV7e37Z1X2Krfa6LyalQqPNyI\n7VlS8DcBpVs9k6GTq/TRUw1GC52ooDxoSMKGCAZkyurrGSZuz49oszEjDqASroWd\n2keYjyjEhRQs4QoQJ/XK3R4QI0rLN+6PlZThAzU5jxvqr1oJ1zegmN7nZSPo8lTt\nOjYVPOPhAf0d0kkmLTVlR7lQTOInHuyXoyws/24kN3SyUQuq0B5IC6cmgCjbWn1/\n/cIKjkX4XG84ocUr1UTB1h5fXPuOT++u1D4DmIv4KDi5LyG+nba9YG0QYfXTn3vm\naufJ4u2kwrmfPUQ0RQIDAQABo1MwUTAdBgNVHQ4EFgQUXlQmW0EsdZk2CgpT6qyb\n8CvIV4gwHwYDVR0jBBgwFoAUXlQmW0EsdZk2CgpT6qyb8CvIV4gwDwYDVR0TAQH/\nBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAYEAHs2K1xP+XUK3sZeYRuQSquo286pA\nHkSuVr7aMzLpFY9DTXXDPh+7Y95fOl9CWWIe3cHCa4x/oGJ0k8MTKJSRoLCEGEno\nzo3c9UrkBMgC0X9PjLHQjnMP+A/3Vg37mPbLpA6koqoVJ5SKWC9rMDxmg7zxmAq6\nKhWjBJQyynSbSy6mpVNCX+I6MEPMYnzp+bHMEVH27SiVLlD0Q+JffDezDRak0Ijs\nzSwcIRq/CISaCh7VLuk0+qboXpZN36286qA0zUsaC9jefeKkJWfiYzsBGpE7/j39\n3DzgeAp02Rxf5g7QBQvwLqPApdVoxAeXWxDu6IAGuUTOSNiB5e5KEOSnj3CRPHyK\npfRQMuztt4Z6ynWqi/2ngYryIPQlnvqhezN3SPNbKDrbhAzMaOf9O9+rfbhHqn4O\nZjmITVZxwmu5921lKZk/MXaIvfvmzyavlJNFPzIv++PztHBjShPrRXQqV+hW+QFi\nq0SHoWEC3z39ki2AzCaTdhfNW2uO2Oixs2h5\n-----END CERTIFICATE-----\n'
MAX_OUTPUT = 64 * 1024**2
OLD_RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
LATER_RELEASE_SHA = "eec331dbc99b73478c4f2c3bae3e7a1d32bd57636b6badc38ae514bc03d33823"
SOURCE_FILES = {
    ".github/scripts/fighter_private_model.py": "925c25094359c4df9cc901a54e11e4374ea471e7cb8680b77380360767b15d79",
    ".github/scripts/fighter_sf3_assets.py": "fb8cd750f4ff134fd27f1040e47691a3932c062660d7ba7b4e9508e4d6151d11",
    ".github/scripts/fighter_h17_d19_native.py": "896cb07ddea3fa2c816a64063d52c69af18910568b01ebd9675012e3a0b595d1",
    ".github/scripts/fighter_shared_root_native.py": "945f612990abba097a5b53a45b25d9230f8bfde14628d4a78e6e631e26782036",
    "scripts/stage_h17_shared_root_release.py": "31bf0de7697678630b6722914d44b93c65773d0a38c11bedc4721a805a384bbd",
    "scripts/stage_h17_floorfall_release.py": "0bf36ee23b2d2e85623c560d5de764a37e6ac2f38c7ddcec2c79be4ba1b7e409",
    "scripts/source_floorfall_audio.py": "066091ae3f8188409283e5584e0edc054e3f6503d3251315747417f6d3287fd1",
}
MANIFESTS = {
    ".github/private/sf3/manifest.json": "f454b50969212171dfe07c34abc497854a6fc59fd55f62aceec64e74eef5c7d0",
    ".github/private/fighter-h17-d19/manifest.json": "697d62e8d9bf81da4521b6b828e4b1c4d2aa00e7141eab4d1558b3aa2ee032ff",
    ".github/private/fighter-h17-shared-root/manifest.json": "d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9",
}
PAYLOADS = {
    "SF3_Palace_Exterior.glb": (9292540, "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"),
    "SF3_H17_Morph.json": (7936, "fc6cad67889ead35ca683ede13b86d4c0423949609388c01ca04b36dc050416b"),
    "SF3_H17_MorphMask.texture": (32768, "f5572cfbbe87bd2feb2e9aa93843815b0acdf1b71c0dd7ab584df24ce3ede514"),
    "SF3_DistinctFighters.json": (29221179, "fbd9ecbd9fb16de79c0240404e315af81d8cbbaa113b6042e6afc5ed7b1d0330"),
    "SF3_FighterRelease.json": (33278, OLD_RELEASE_SHA),
}
PROVENANCE = {
    "provenance/sf3-manifest.json": ".github/private/sf3/manifest.json",
    "provenance/h17-overlay-manifest.json": ".github/private/fighter-h17-d19/manifest.json",
    "provenance/shared-root-delta-manifest.json": ".github/private/fighter-h17-shared-root/manifest.json",
}


class RecoveryError(ValueError):
    pass


def require(condition, code):
    if not condition:
        raise RecoveryError(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def raw_file(path, maximum=MAX_OUTPUT):
    path = Path(path).absolute()
    require(path.resolve(strict=True) == path, "symlink-input")
    with path.open("rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum, "input-size-or-type")
        raw = stream.read(maximum + 1)
    require(len(raw) == info.st_size, "input-changed")
    return raw


def checked(path, expected_sha, expected_bytes=None, maximum=MAX_OUTPUT):
    raw = raw_file(path, maximum)
    require(sha(raw) == expected_sha and (expected_bytes is None or len(raw) == expected_bytes),
            "input-identity")
    return raw


def unique_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate-json-key")
            result[key] = value
        return result
    def invalid(_):
        raise RecoveryError("nonfinite-json")
    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)


def write_new(path, raw):
    path = Path(path)
    require(path.parent.resolve(strict=True) == path.parent and not path.exists(), "output-not-new")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(raw)


def write_json(path, document):
    write_new(path, (json.dumps(document, ensure_ascii=True, indent=2, allow_nan=False) + "\n").encode())


def clean_env(extra=None):
    allowed = ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR", "DEVELOPER_DIR", "SDKROOT")
    result = {key: os.environ[key] for key in allowed if key in os.environ}
    result.update(extra or {})
    return result


def run(command, *, data=None, extra_env=None, timeout=240, cwd=None):
    result = subprocess.run(command, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=clean_env(extra_env), timeout=timeout, cwd=cwd, check=False)
    require(result.returncode == 0, "bounded-subprocess-failed")
    return result.stdout


@contextmanager
def resource_environment(values):
    old = dict(os.environ)
    os.environ.clear()
    os.environ.update({key: old[key] for key in ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR") if key in old})
    os.environ.update(values)
    try:
        yield
    finally:
        os.environ.clear()
        os.environ.update(old)


def git(root, *arguments):
    return run(["git", *arguments], cwd=root, timeout=60).decode().strip()


def no_resource_keys():
    require(not any(name.startswith("FIGHTER_") and name.endswith("_KEY") for name in os.environ),
            "resource-key-outside-stage")


def work():
    parent = Path(os.environ["RUNNER_TEMP"]).absolute()
    require(parent.resolve(strict=True) == parent and parent.is_dir(), "runner-temp-directory")
    result = parent / WORK_NAME
    require(not result.is_symlink(), "work-symlink")
    return result


def validate_event(env, event, head, parents, title, changed):
    require(env.get("GITHUB_REPOSITORY") == REPOSITORY and env.get("GITHUB_REF") == BRANCH
            and env.get("GITHUB_EVENT_NAME") == "push" and env.get("GITHUB_RUN_ATTEMPT") == "1",
            "unreviewed-event")
    require(re.fullmatch(r"[0-9a-f]{40}", head) and env.get("GITHUB_SHA") == head
            and env.get("GITHUB_WORKFLOW_SHA") == head, "workflow-source-mismatch")
    require(env.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@" + BRANCH,
            "workflow-path-mismatch")
    require(parents == [PARENT_SHA] and title == COMMIT_TITLE, "commit-parent-or-title")
    require({HELPER, WORKFLOW} <= set(changed) <= ALLOWED_CHANGES, "commit-scope")
    require(event.get("repository", {}).get("full_name") == REPOSITORY
            and event.get("ref") == BRANCH and event.get("before") == PARENT_SHA
            and event.get("after") == head and event.get("deleted") is False
            and event.get("forced") is False, "push-shape")
    commits = event.get("commits")
    require(isinstance(commits, list) and len(commits) == 1 and commits[0].get("id") == head
            and event.get("head_commit", {}).get("id") == head
            and event["head_commit"].get("message") == COMMIT_TITLE
            and commits[0].get("message") == COMMIT_TITLE, "one-reviewed-commit-required")


def identity():
    head = git(ROOT, "rev-parse", "HEAD")
    parent_line = git(ROOT, "rev-list", "--parents", "-n", "1", "HEAD").split()
    title = git(ROOT, "show", "-s", "--format=%B", "HEAD")
    changed = git(ROOT, "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").splitlines()
    event = unique_json(raw_file(Path(os.environ["GITHUB_EVENT_PATH"]), 8 * 1024**2))
    validate_event(os.environ, event, head, parent_line[1:], title, changed)
    expected = os.environ.get("EXPECTED_RESOURCE_RECOVERY_HELPER_SHA256", "")
    require(re.fullmatch(r"[0-9a-f]{64}", expected), "missing-helper-pin")
    checked(ROOT / HELPER, expected, maximum=128 * 1024)
    require(not git(ROOT, "diff", "--name-only", "HEAD", "--", *ALLOWED_CHANGES), "modified-control-files")
    require(git(SOURCE_ROOT, "rev-parse", "HEAD") == SOURCE_SHA, "stored-source-commit")
    for name, expected_sha in {**SOURCE_FILES, **MANIFESTS}.items():
        checked(SOURCE_ROOT / name, expected_sha, maximum=2 * 1024**2)
    return dict(workflowCommit=head, storedSourceCommit=SOURCE_SHA,
                helperSHA256=expected, workflowSHA256=sha(raw_file(ROOT / WORKFLOW, 32 * 1024)),
                runID=os.environ.get("GITHUB_RUN_ID"), runAttempt=1,
                recipientCertificateSHA256=CERTIFICATE_SHA, recipientSPKISHA256=RECIPIENT_SPKI_SHA)


def openssl_path():
    options = ("/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl", shutil.which("openssl"))
    binary = next((path for path in options if path and Path(path).is_file()), None)
    require(binary is not None and run([binary, "version"]).startswith(b"OpenSSL 3."), "openssl-3-required")
    return binary


def validate_recipient(binary, path):
    checked(path, CERTIFICATE_SHA, maximum=8192)
    run([binary, "x509", "-in", str(path), "-checkend", "600", "-noout"])
    public = run([binary, "x509", "-in", str(path), "-pubkey", "-noout"])
    der = run([binary, "pkey", "-pubin", "-outform", "DER"], data=public)
    require(sha(der) == RECIPIENT_SPKI_SHA, "recipient-public-key")


def once(phase):
    write_new(work() / (phase + ".started"), b"started\n")


def prepared():
    current = identity()
    saved = unique_json(raw_file(work() / "prepared.json", 16 * 1024))
    require(current == saved, "prepared-identity-changed")
    return current


def prepare():
    no_resource_keys()
    current = identity()
    target = work()
    require(not target.exists(), "one-new-work-directory-required")
    target.mkdir(mode=0o700)
    (target / "private").mkdir(mode=0o700)
    (target / "published").mkdir(mode=0o700)
    require(sha(CERTIFICATE_PEM) == CERTIFICATE_SHA, "embedded-certificate-pin")
    cert = target / "private/recipient-public.crt"
    write_new(cert, CERTIFICATE_PEM)
    validate_recipient(openssl_path(), cert)
    write_json(target / "prepared.json", current)
    print("Pinned one recovery commit, stored inputs and recipient; no resource key read.")


def imported_sources():
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(SOURCE_ROOT / "scripts"))
    sys.path.insert(0, str(SOURCE_ROOT / ".github/scripts"))
    names = ("fighter_sf3_assets", "fighter_h17_d19_native", "fighter_shared_root_native")
    modules = [importlib.import_module(name) for name in names]
    for module in modules:
        require(Path(module.__file__).resolve().is_relative_to(SOURCE_ROOT), "import-origin")
    return modules


def audit_inventory(directory, inventory):
    expected = {row["file"]: row for row in inventory}
    require(len(expected) == len(inventory), "duplicate-inventory-name")
    require({p.name for p in directory.iterdir()} == set(expected), "inventory-closure")
    for name, row in expected.items():
        require(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,191}", name) and ".." not in name,
                "inventory-name")
        checked(directory / name, row["sha256"], row["bytes"], maximum=128 * 1024**2)


def stage():
    current = prepared()
    once("stage")
    model_key = os.environ.get(KEYS[0], "")
    h17_key = os.environ.get(KEYS[1], "")
    require(re.fullmatch(r"[0-9a-f]{64}", model_key), "model-key-format")
    try:
        decoded = base64.b64decode(h17_key, validate=True)
    except ValueError:
        raise RecoveryError("h17-key-format") from None
    require(len(decoded) == 32 and base64.b64encode(decoded).decode() == h17_key, "h17-key-format")
    decoded = b""
    for name in KEYS:
        os.environ.pop(name, None)
    no_resource_keys()
    assets, legacy, shared = imported_sources()
    private = work() / "private"
    source_overlay = SOURCE_ROOT / ".github/private/fighter-h17-d19"
    source_delta = SOURCE_ROOT / ".github/private/fighter-h17-shared-root"
    base = legacy.validate_release_manifest(unique_json(raw_file(source_overlay / "manifest.json", 2 * 1024**2)))
    delta = unique_json(raw_file(source_delta / "manifest.json", 2 * 1024**2))
    require(base["releaseSHA256"] == "7bf9aa17a1e15273dbe7ae04eecd1ef092c2ad9a72360b99cd4f7ac08695704b"
            and len(base["files"]) == 295 and delta["targetReleaseSHA256"] == OLD_RELEASE_SHA
            and len(delta["targetFiles"]) == 13 and delta["unchangedBaseFiles"] == 289,
            "stored-release-boundary")
    cipher = private / "overlay.enc"
    legacy.assemble_cipher(base, source_overlay, cipher)
    row = delta["cipher"]
    delta_cipher = source_delta / row["name"]
    checked(delta_cipher, row["sha256"], row["bytes"], maximum=8 * 1024**2 + 28)
    clear, delta_clear, swift = (private / name for name in ("overlay.zip", "delta.zip", "authenticate.swift"))
    write_new(swift, shared.GCM_SWIFT.encode())
    run(["swift", str(swift), str(cipher), str(clear), str(delta_cipher), str(delta_clear)],
        extra_env={KEYS[1]: h17_key}, timeout=240)
    h17_key = ""
    overlay = private / "overlay"
    legacy.overlay_zip(raw_file(clear, 128 * 1024**2), base, overlay)
    delta_doc, payloads = shared.decode_delta(raw_file(delta_clear, 8 * 1024**2), delta)
    shared.reconstruct_delta(delta_doc, payloads, overlay, base)
    final = {row["file"]: row for row in base["files"]}
    final.update({row["name"]: dict(file=row["name"], bytes=row["bytes"], sha256=row["sha256"])
                  for row in delta["targetFiles"]})
    require(len(final) == 302 and final["SF3_FighterRelease.json"]["sha256"] == OLD_RELEASE_SHA,
            "older-final-release")
    audit_inventory(overlay, list(final.values()))
    with resource_environment({KEYS[0]: model_key, "FIGHTER_OPENSSL": openssl_path()}):
        scenery = assets.verified_assets(SOURCE_ROOT / ".github/private/sf3")
    model_key = ""
    selected = {name: (scenery[name] if name == "SF3_Palace_Exterior.glb" else raw_file(overlay / name))
                for name in PAYLOADS}
    for name, raw in selected.items():
        size, expected_sha = PAYLOADS[name]
        require(len(raw) == size and sha(raw) == expected_sha, "selected-resource-identity")
    payload = private / "payload"
    payload.mkdir(mode=0o700)
    (payload / "FighterPrivate").mkdir(mode=0o700)
    (payload / "provenance").mkdir(mode=0o700)
    for name, raw in selected.items():
        write_new(payload / "FighterPrivate" / name, raw)
    for name, source in PROVENANCE.items():
        write_new(payload / name, checked(SOURCE_ROOT / source, MANIFESTS[source], maximum=2 * 1024**2))
    receipt = dict(schema="five-stored-fighter-resources-recovered-v1", **current,
                   payloads=[dict(file=name, bytes=size, sha256=digest) for name, (size, digest) in PAYLOADS.items()],
                   originalOverlayFilesVerified=295, deltaPayloadFilesVerified=13,
                   olderFinalOverlayFilesVerified=302, recoveredReleaseSHA256=OLD_RELEASE_SHA,
                   requiredLaterD15BaseReleaseSHA256=LATER_RELEASE_SHA, equalsLaterD15Base=False,
                   newSourceDownloads=0, originalMediaDecodedAgain=False,
                   appBuilt=False, nativeAcceptancePerformed=False, productionReady=False,
                   signed=False, uploadedToTestFlight=False, keysIncluded=False,
                   boundary="Older shared-root source material recovery only. Current D15 morph mapping and the later imperial base remain separate work.")
    write_json(payload / "recovery-receipt-private.json", receipt)
    write_new(work() / "stage.complete", b"verified-five-resources\n")
    print("Verified stored 302-file older overlay; selected five exact recovery resources. No App was built.")


def selected_inventory(payload):
    expected = {"FighterPrivate/" + name for name in PAYLOADS} | set(PROVENANCE) | {"recovery-receipt-private.json"}
    paths = list(payload.rglob("*"))
    require(not any(path.is_symlink() for path in paths), "payload-symlink")
    require({p.relative_to(payload).as_posix() for p in paths if p.is_file()} == expected,
            "payload-allowlist")
    rows = []
    for name in sorted(expected):
        raw = raw_file(payload / name)
        if name.startswith("FighterPrivate/"):
            size, expected_sha = PAYLOADS[Path(name).name]
            require(len(raw) == size and sha(raw) == expected_sha, "payload-changed")
        elif name in PROVENANCE:
            require(sha(raw) == MANIFESTS[PROVENANCE[name]], "provenance-changed")
        else:
            receipt = unique_json(raw)
            require(receipt["recoveredReleaseSHA256"] == OLD_RELEASE_SHA
                    and receipt["equalsLaterD15Base"] is False and receipt["productionReady"] is False,
                    "receipt-boundary-changed")
        rows.append(dict(path=name, bytes=len(raw), sha256=sha(raw)))
    require(sum(row["bytes"] for row in rows) <= MAX_OUTPUT, "payload-byte-bound")
    return rows


def cms_encrypt(binary, clear, recipient, output):
    require(not output.exists(), "envelope-not-new")
    run([binary, "cms", "-encrypt", "-aes-256-gcm", "-binary", "-in", str(clear),
         "-outform", "DER", "-out", str(output), "-recip", str(recipient),
         "-keyopt", "rsa_padding_mode:oaep", "-keyopt", "rsa_oaep_md:sha256",
         "-keyopt", "rsa_mgf1_md:sha256"], timeout=180)
    os.chmod(output, 0o600)
    raw = raw_file(output, MAX_OUTPUT + 65536)
    require(len(raw) > 512, "envelope-size")
    return raw


def seal():
    no_resource_keys()
    current = prepared()
    require(raw_file(work() / "stage.complete", 128) == b"verified-five-resources\n", "stage-incomplete")
    once("seal")
    private, published = work() / "private", work() / "published"
    payload = private / "payload"
    rows = selected_inventory(payload)
    binary, recipient = openssl_path(), private / "recipient-public.crt"
    validate_recipient(binary, recipient)
    clear = private / "recovered-inputs.zip"
    with zipfile.ZipFile(clear, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for row in rows:
            raw = checked(payload / row["path"], row["sha256"], row["bytes"])
            info = zipfile.ZipInfo(row["path"], date_time=(2026, 11, 17, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100600 << 16
            archive.writestr(info, raw, compress_type=zipfile.ZIP_DEFLATED)
    os.chmod(clear, 0o600)
    clear_raw = raw_file(clear)
    temporary = private / "recovered-inputs.cms.partial"
    cipher = cms_encrypt(binary, clear, recipient, temporary)
    destination = published / "recovered-inputs.cms"
    require(not destination.exists(), "published-envelope-not-new")
    os.replace(temporary, destination)
    public = dict(schema="sealed-five-resource-recovery-v1", **current,
                  encryptedFile=destination.name, encryptedBytes=len(cipher), encryptedSHA256=sha(cipher),
                  clearZIPBytes=len(clear_raw), clearZIPSHA256=sha(clear_raw),
                  resourceFiles=5, provenanceManifests=3, privateReceipts=1,
                  recoveredReleaseSHA256=OLD_RELEASE_SHA, equalsLaterD15Base=False,
                  envelope="CMS AuthEnvelopedData AES-256-GCM with RSA-OAEP-SHA256", plaintextPublished=False,
                  productionReady=False, nativeAcceptancePerformed=False, AppBuilt=False, TestFlight=False)
    write_json(published / "sealed-recovery-report.json", public)
    write_new(published / "SHA256SUMS", (sha(cipher) + "  recovered-inputs.cms\n").encode())
    print("Sealed five resources to the pinned private recipient; artifact contains no plaintext resource or key.")


def cleanup():
    target = work()
    if target.exists():
        private = target / "private"
        require(not private.is_symlink(), "cleanup-symlink")
        if private.exists():
            shutil.rmtree(private)
        for name in ("prepared.json", "stage.started", "stage.complete", "seal.started"):
            path = target / name
            require(not path.is_symlink(), "cleanup-marker-symlink")
            path.unlink(missing_ok=True)
    print("Removed temporary plaintext recovery workspace.")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("prepare", "stage", "seal", "cleanup"))
    args = parser.parse_args()
    try:
        globals()[args.phase]()
    except RecoveryError as error:
        print("Resource recovery stopped: " + str(error), file=sys.stderr)
        return 1
    except Exception as error:
        print("Resource recovery stopped: " + type(error).__name__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
