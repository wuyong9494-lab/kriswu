#!/usr/bin/env python3
"""Authenticated private fighter asset/evidence envelope. No network or key output.

The random 256-bit password lives in FIGHTER_LIU_MODEL_KEY. OpenSSL provides
AES-256-CBC with a fresh salt and PBKDF2-SHA256/200000. A separately derived
HMAC-SHA256 authenticates the version, purpose and complete ciphertext BEFORE
decryption. Only ciphertext is committed to this public repository.
"""
import hashlib
import hmac
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HEADER = b"FIGHTER1\0"
SIZE = 5_043_964
SHA = "ac9c5f1e1186a66466ec37457601b82bfcd654bcac9aee8cde65b36ed173caa9"
ROOT = Path(__file__).resolve().parents[2]


def key():
    value = os.environ.get("FIGHTER_LIU_MODEL_KEY", "")
    if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("Private fighter key is missing or malformed")
    return bytes.fromhex(value)


def mac_key(purpose):
    return hmac.digest(key(), b"fighter-envelope-mac-v1\0" + purpose.encode(), "sha256")


def openssl(data, decrypt=False):
    binary = next((p for p in [os.environ.get("FIGHTER_OPENSSL", ""),
        "/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl",
        shutil.which("openssl")] if p and Path(p).is_file()), None)
    if not binary:
        raise ValueError("OpenSSL is required")
    key()
    command = [binary, "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "200000", "-md", "sha256",
               "-pass", "env:FIGHTER_LIU_MODEL_KEY"]
    if decrypt:
        command.append("-d")
    result = subprocess.run(command, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError("Private envelope cipher failed")
    return result.stdout


def seal(data, purpose):
    prefix = HEADER + purpose.encode() + b"\0"
    body = prefix + openssl(data)
    return body + hmac.digest(mac_key(purpose), body, "sha256")


def unseal(data, purpose):
    prefix = HEADER + purpose.encode() + b"\0"
    if len(data) < len(prefix) + 48 or not data.startswith(prefix):
        raise ValueError("Invalid private envelope")
    body, tag = data[:-32], data[-32:]
    if not hmac.compare_digest(tag, hmac.digest(mac_key(purpose), body, "sha256")):
        raise ValueError("Private envelope authentication failed")
    return openssl(body[len(prefix):], decrypt=True)


def write_atomic(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def verify_model(data):
    if len(data) != SIZE or hashlib.sha256(data).hexdigest() != SHA:
        raise ValueError("Private fighter asset integrity mismatch")


def verify_app(path):
    """Fail closed before upload if the signed app would use the stand-in."""
    app = Path(path)
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Expected a built .app bundle")
    # Match the exact two locations that DuelCharacterAsset.bundledURL reads.
    candidates = [app / "Liu_FullBody_Mobile.glb",
                  app / "FighterPrivate/Liu_FullBody_Mobile.glb"]
    models = [p for p in candidates if p.is_file()]
    if len(models) != 1:
        raise ValueError("Expected exactly one bundled Liu character; refusing stand-in release")
    verify_model(models[0].read_bytes())
    # Neither the distribution key nor the ciphertext is an app resource.
    if any(p.name in ("Fighter_Liu_Model_Key.txt", "liu-fullbody-v1.glb.enc") for p in app.rglob("*")):
        raise ValueError("Private staging material must not be bundled")
    print("Bundled Liu character verified; actual model is present")


def stage():
    key()
    encrypted = ROOT / ".github/private/liu-fullbody-v1.glb.enc"
    clear = unseal(encrypted.read_bytes(), "model")
    verify_model(clear)
    write_atomic(ROOT / "App/Resources/FighterPrivate/Liu_FullBody_Mobile.glb", clear)
    print("Private fighter model staged and SHA-256 verified")


def main():
    args = sys.argv[1:]
    if args == ["stage"]:
        stage()
    elif len(args) == 2 and args[0] == "verify-app":
        verify_app(args[1])
    elif len(args) == 4 and args[0] in ("seal", "unseal") and args[1] in ("model", "evidence"):
        operation = seal if args[0] == "seal" else unseal
        write_atomic(args[3], operation(Path(args[2]).read_bytes(), args[1]))
    else:
        raise ValueError("Usage: stage | verify-app APP | seal/unseal model/evidence INPUT OUTPUT")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
