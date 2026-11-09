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
import stat
import subprocess
import sys
import tempfile
import time

HEADER = b"FIGHTER1\0"
SIZE = 5_043_964
SHA = "ac9c5f1e1186a66466ec37457601b82bfcd654bcac9aee8cde65b36ed173caa9"
ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_BUFFER_BYTES = 1024 * 1024
MAX_EVIDENCE_BYTES = 9 * 1024**3


def key():
    value = os.environ.get("FIGHTER_LIU_MODEL_KEY", "")
    if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("Private fighter key is missing or malformed")
    return bytes.fromhex(value)


def mac_key(purpose):
    return hmac.digest(key(), b"fighter-envelope-mac-v1\0" + purpose.encode(), "sha256")


def openssl_command(decrypt=False):
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
    return command


def openssl(data, decrypt=False):
    command = openssl_command(decrypt)
    result = subprocess.run(command, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError("Private envelope cipher failed")
    return result.stdout


def seal(data, purpose):
    prefix = HEADER + purpose.encode() + b"\0"
    body = prefix + openssl(data)
    return body + hmac.digest(mac_key(purpose), body, "sha256")


def seal_evidence_file(source, destination):
    """Stream the existing evidence envelope; publish only a complete MACed file.

    Models and the byte-oriented API retain their existing behavior. OpenSSL
    still receives the password only through the existing environment variable.
    Temporary files never match the workflow's final .enc upload path.
    """
    source, destination = Path(source), Path(destination)
    if source.is_symlink() or destination.exists() or destination.is_symlink():
        raise ValueError("Evidence sealing requires a regular source and new output")
    command = openssl_command()
    prefix = HEADER + b"evidence\0"
    authenticator = hmac.new(mac_key("evidence"), prefix, "sha256")
    # O_NONBLOCK prevents a substituted FIFO from hanging before fstat rejects
    # it. O_NOFOLLOW closes the final-component symlink check/open race.
    source_fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    temporary = None
    process = None
    try:
        with os.fdopen(source_fd, "rb") as original:
            before = os.fstat(original.fileno())
            if not stat.S_ISREG(before.st_mode) or not 0 <= before.st_size <= MAX_EVIDENCE_BYTES:
                raise ValueError("Evidence source is not a regular file within the size bound")
            fd, temporary = tempfile.mkstemp(prefix=".fighter-seal-", suffix=".tmp", dir=destination.parent)
            with os.fdopen(fd, "wb") as target:
                target.write(prefix)
                process = subprocess.Popen(command, stdin=original, stdout=subprocess.PIPE,
                                           stderr=subprocess.DEVNULL)
                count, salt_header = 0, b""
                # The unchanged command defaults to an 8-byte salt, including
                # OpenSSL 3.2/3.6, for compatibility with the existing reader:
                # https://docs.openssl.org/3.6/man1/openssl-enc/#options
                # Fail closed if a cipher implementation changes that format.
                expected = 16 + (before.st_size // 16 + 1) * 16
                try:
                    while block := process.stdout.read(EVIDENCE_BUFFER_BYTES):
                        count += len(block)
                        if count > expected:
                            raise ValueError("Evidence changed during sealing")
                        if len(salt_header) < 8:
                            salt_header += block[:8 - len(salt_header)]
                        target.write(block)
                        authenticator.update(block)
                finally:
                    process.stdout.close()
                if process.wait() or count != expected or salt_header != b"Salted__":
                    raise ValueError("Private envelope cipher failed")
                after = os.fstat(original.fileno())
                if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                        after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                    raise ValueError("Evidence changed during sealing")
                target.write(authenticator.digest())
            # Same-filesystem link publishes atomically without replacing an
            # existing output, including one that appeared while encrypting.
            os.link(temporary, destination)
            return before.st_size
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)


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
        if args[:2] == ["seal", "evidence"]:
            started = time.monotonic()
            print("Sealing private evidence with bounded memory", flush=True)
            size = seal_evidence_file(args[2], args[3])
            print(f"Private evidence sealed: {size} source bytes, {time.monotonic() - started:.1f} seconds", flush=True)
        else:
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
