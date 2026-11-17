#!/usr/bin/env python3
"""Prepare a resource-only CMS recipient protected by the existing asset key.

The RSA key is not an account credential. Only its public certificate and an
authenticated encrypted PKCS8 are exported. Later native validation can open
the wrapped key inside the same existing protected asset environment.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
PARENT = "e8a8bdfeba67992b710512531824cc87d8d83d48"
TITLE = "Prepare protected fighter integration recipient 20261117"
HELPER = ".github/scripts/fighter_integration_recipient.py"
TEST = ".github/scripts/test_fighter_integration_recipient.py"
WORKFLOW = ".github/workflows/fighter-integration-recipient.yml"
ALLOWED = frozenset((HELPER, TEST, WORKFLOW))
WORK_NAME = "fighter-integration-recipient-20261117"
KEY_NAME = "FIGHTER_H17_D19_KEY"
DOMAIN = b"fighter-native-integration-recipient-20261117:wrapped-pkcs8-v1"
PUBLIC_NAMES = frozenset(("recipient-public.crt", "recipient-private.pkcs8.enc", "recipient-report.json"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def regular(path, maximum=128 * 1024):
    path = Path(path).absolute()
    info = path.lstat()
    require(path.resolve(strict=True) == path and stat.S_ISREG(info.st_mode)
            and 0 < info.st_size <= maximum, "Invalid bounded regular file")
    return path.read_bytes()


def unique_json(raw):
    def pairs(rows):
        out = {}
        for name, value in rows:
            require(name not in out, "Duplicate JSON key")
            out[name] = value
        return out
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: require(False, "Non-finite JSON"))


def run(command, data=None, timeout=60):
    env = {name: value for name, value in os.environ.items()
           if not re.search(r"KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL", name, re.I)}
    result = subprocess.run(command, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, timeout=timeout)
    require(result.returncode == 0, "A bounded crypto or source command failed")
    return result.stdout


def git(*args):
    return run(["git", "-C", str(ROOT), *args]).decode().strip()


def validate_event(env, event, head, parents, message, changed):
    require(env.get("GITHUB_REPOSITORY") == REPOSITORY and env.get("GITHUB_REF") == BRANCH,
            "Unexpected repository or ref")
    require(env.get("GITHUB_EVENT_NAME") == "push" and env.get("GITHUB_RUN_ATTEMPT") == "1",
            "Only one reviewed push attempt is accepted")
    require(re.fullmatch(r"[0-9a-f]{40}", head) is not None
            and env.get("GITHUB_SHA") == env.get("GITHUB_WORKFLOW_SHA") == head,
            "Workflow source differs")
    require(env.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@" + BRANCH,
            "Unexpected workflow")
    require(parents == [PARENT] and message == TITLE and set(changed) == ALLOWED,
            "Unreviewed commit scope")
    require(event.get("before") == PARENT and event.get("after") == head
            and event.get("ref") == BRANCH and event.get("deleted") is False
            and event.get("forced") is False
            and event.get("repository", {}).get("full_name") == REPOSITORY,
            "Unreviewed push")
    commits = event.get("commits")
    require(isinstance(commits, list) and len(commits) == 1 and commits[0].get("id") == head
            and event.get("head_commit", {}).get("id") == head
            and event["head_commit"].get("message") == TITLE, "Unreviewed pushed commit")


def identity():
    head = git("rev-parse", "HEAD")
    parents = git("rev-list", "--parents", "-n", "1", "HEAD").split()[1:]
    changed = git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").splitlines()
    event = unique_json(regular(Path(os.environ["GITHUB_EVENT_PATH"]), 8 * 1024**2))
    validate_event(os.environ, event, head, parents, git("show", "-s", "--format=%B", "HEAD"), changed)
    expected = os.environ.get("EXPECTED_RECIPIENT_HELPER_SHA256", "")
    require(re.fullmatch(r"[0-9a-f]{64}", expected) is not None
            and digest(regular(ROOT / HELPER)) == expected, "Helper integrity differs")
    require(not git("diff", "--name-only", "HEAD", "--", *ALLOWED), "Control files changed")
    return dict(sourceCommit=head, helperSHA256=expected,
                workflowSHA256=digest(regular(ROOT / WORKFLOW)),
                runID=os.environ["GITHUB_RUN_ID"], runAttempt=1)


def work():
    return Path(os.environ["RUNNER_TEMP"]).resolve(strict=True) / WORK_NAME


def write(path, raw):
    with path.open("xb") as output:
        output.write(raw)
    path.chmod(0o600)


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def resource_key(value):
    try:
        raw = base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        raise ValueError("Invalid existing resource key") from None
    require(len(raw) == 32 and base64.b64encode(raw).decode() == value,
            "Invalid existing resource key")
    return raw


def wrapper_hmac(key, wrapped):
    require(len(key) == 32 and 0 < len(wrapped) < 8192, "Invalid wrapped key input")
    auth_key = hmac.new(key, DOMAIN, hashlib.sha256).digest()
    return hmac.new(auth_key, wrapped, hashlib.sha256).hexdigest()


def openssl():
    choices = ("/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl", shutil.which("openssl"))
    binary = next((x for x in choices if x and Path(x).is_file()), None)
    require(binary and run([binary, "version"]).startswith(b"OpenSSL 3."), "OpenSSL 3 is required")
    return binary


def prepare():
    require(KEY_NAME not in os.environ, "Preparation must not receive a resource key")
    current = identity()
    root = work()
    require(not root.exists(), "Recipient workspace already exists")
    root.mkdir(mode=0o700)
    (root / "private").mkdir(mode=0o700)
    (root / "published").mkdir(mode=0o700)
    write(root / "prepared.json", json_bytes(current))
    print("Pinned one resource-only recipient preparation; no asset key read.")


def generate():
    current = identity()
    root = work()
    require(unique_json(regular(root / "prepared.json")) == current, "Prepared identity changed")
    write(root / "generate.started", b"once\n")
    key_text = os.environ.pop(KEY_NAME, None)
    key = resource_key(key_text)
    require(not any(re.search(r"FIGHTER_.*KEY", name) for name in os.environ), "Unrelated resource key present")
    private, published = root / "private", root / "published"
    binary = openssl()
    pem, certificate = private / "recipient-private.pem", private / "recipient-public.crt"
    previous = os.umask(0o077)
    try:
        run([binary, "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256", "-days", "7",
             "-subj", "/CN=Fighter Native Integration 20261117", "-keyout", str(pem), "-out", str(certificate)], timeout=120)
        require(stat.S_IMODE(pem.stat().st_mode) == 0o600, "Private key permissions differ")
        wrapped = private / "recipient-private.pkcs8.enc"
        run([binary, "pkcs8", "-topk8", "-in", str(pem), "-outform", "DER", "-out", str(wrapped),
             "-v2", "aes-256-cbc", "-v2prf", "hmacWithSHA256", "-iter", "210000", "-passout", "stdin"],
            data=(key_text + "\n").encode())
        cipher = regular(wrapped, 8192)
        cert = regular(certificate, 8192)
        public = run([binary, "x509", "-in", str(certificate), "-pubkey", "-noout"])
        spki = run([binary, "pkey", "-pubin", "-outform", "DER"], data=public)
        # Prove the encrypted key reopens and is the certificate's key before export.
        reopened = run([binary, "pkey", "-inform", "DER", "-in", str(wrapped), "-passin", "stdin",
                        "-pubout", "-outform", "DER"], data=(key_text + "\n").encode())
        require(reopened == spki, "Wrapped recipient does not match its certificate")
        report = dict(schema="protected-fighter-native-recipient-v1", **current,
            keyPurpose="decrypt reviewed game resources in the existing fighter-private-assets environment",
            certificateFile=certificate.name, certificateBytes=len(cert), certificateSHA256=digest(cert),
            recipientSPKISHA256=digest(spki), wrappedKeyFile=wrapped.name, wrappedKeyBytes=len(cipher),
            wrappedKeySHA256=digest(cipher), wrappedKeyHMACSHA256=wrapper_hmac(key, cipher),
            wrapping="PKCS8 PBES2 AES-256-CBC PBKDF2-HMAC-SHA256 210000 plus domain-separated HMAC-SHA256",
            authenticationKeyExisting=True, plaintextPrivateKeyPublished=False,
            gameResourcesRead=False, appBuilt=False, signed=False, uploadedToTestFlight=False)
        write(published / certificate.name, cert)
        write(published / wrapped.name, cipher)
        write(published / "recipient-report.json", json_bytes(report))
        require({p.name for p in published.iterdir()} == PUBLIC_NAMES, "Unexpected output")
        write(root / "generate.complete", b"public-certificate-and-authenticated-wrapped-key\n")
    finally:
        os.umask(previous)
    print("Prepared the resource-only public recipient and authenticated encrypted key; no plaintext key exported.")


def cleanup():
    root = work()
    if not root.exists():
        return
    require(root.resolve(strict=True) == root and root.is_dir(), "Unsafe cleanup root")
    private = root / "private"
    if private.exists():
        require(not private.is_symlink() and private.is_dir(), "Unsafe private workspace")
        shutil.rmtree(private)
    published = root / "published"
    require(not published.is_symlink() and published.is_dir(), "Unsafe output directory")
    require({p.name for p in published.iterdir()} <= PUBLIC_NAMES, "Unexpected output file")
    for path in published.iterdir():
        regular(path, 16384)
    print("Removed temporary plaintext recipient key.")


if __name__ == "__main__":
    require(len(sys.argv) == 2 and sys.argv[1] in ("prepare", "generate", "cleanup"), "Unexpected phase")
    globals()[sys.argv[1]]()
