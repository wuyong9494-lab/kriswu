#!/usr/bin/env python3
"""One official bootstrap integration observation in GitHub CI.

No resource secrets, custom proxy/TLS settings, redirects, retries, URL following,
APK download, client execution or media recovery. Response bytes stay encrypted.
The application-defined request is source-derived; Unity wire parity is unproven.
"""
import ast
import contextlib
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
REF = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
MESSAGE = "Verify Pangu official bootstrap integration 20261115"
WORKFLOW = ".github/workflows/fighter-pangu-index-discovery.yml"
SCRIPT = ".github/scripts/fighter_pangu_index_discovery.py"
TEST = ".github/scripts/test_fighter_pangu_index_discovery.py"
RECIPIENT = ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI_SHA = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
ENVELOPE = ".github/scripts/fighter_private_model.py"
EXISTING_RECIPIENT = ".github/scripts/fighter_recover_screenshots.py"
DEPENDENCY_PINS = {
    ENVELOPE: "925c25094359c4df9cc901a54e11e4374ea471e7cb8680b77380360767b15d79",
    EXISTING_RECIPIENT: "35b31b9de3b75708889db9e967a266f4e796954633c9b76ec68e94d39faf0241",
    RECIPIENT: "1b9eecfbe2b11c1599a3598e218be6f6d179cef14efbf5b7e91022c0c53b0321",
}
REQUEST_URL = "https://sf3lb.nekki.com?fv=1.46.0.0.16728-prod&rand=38491&p=Android"
MAX_BODY = 1024 * 1024
MAX_HEADERS = 64 * 1024
HTTP_SECONDS = 20
OLD_BODY_SHA = "ca71485324997c2c4cbf507b6e9cd20e1e8d1c7a644f87f5c993216cdafa56b0"
STEM = "pangu-bootstrap-evidence"
CIPHER_NAMES = (STEM + ".enc", STEM + ".key.enc", STEM + ".session-key.enc")
UPLOAD_NAMES = CIPHER_NAMES + (STEM + ".SHA256SUMS",)
PRIVATE_NAMES = ("identity.json", "request-started.json", "receipt.json", "response.bin", "private-evidence.zip")
SOURCE_PROOF = {
    "host": "supplied IPA internalSettings ServerSettings.Servers.prod[0]",
    "nativeImageSHA256": "7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b",
    "requestConstruction": "1606 -> 170836 -> 170879; null form, GET; explicit headers null",
    "native1606SHA256": "f144ae86753bcddcc26bd36dccbe150a2ddc3a2689188449442f266bc8a65374",
    "version": "official 19221.apk; actual member 1.46.0.0.16728-prod_splits.zip.enc",
    "officialArchivePrefixSHA256": "09ac85e2f868c8a387fa988eb9dabe174f6e1c96b2c07926190c3b42a0394e54",
    "platform": "source standard Android literal; actual Android SKU execution unverified",
    "localResponseSHA256": OLD_BODY_SHA,
}


class GuardError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise GuardError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def regular(path, limit):
    path = Path(path)
    require(not path.is_symlink(), "Symlink input rejected")
    info = path.stat()
    require(stat.S_ISREG(info.st_mode) and info.st_size <= limit, "Input must be a bounded regular file")
    return path


def write_new(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)


def write_json(path, data):
    write_new(path, (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode())


def read_json(path, limit=2 * 1024 * 1024):
    return json.loads(regular(path, limit).read_bytes())


def no_resource_keys(env=None):
    env = os.environ if env is None else env
    require(not any(k.startswith("FIGHTER_") and k.endswith("_KEY") for k in env),
            "Resource key variables must not enter this diagnostic")


def directory():
    parent = Path(os.environ["RUNNER_TEMP"])
    require(parent.is_absolute() and ".." not in parent.parts and parent.is_dir(), "Runner temporary directory required")
    require(all(not p.is_symlink() for p in (parent, *parent.parents)), "Symlink temporary parent rejected")
    path = parent / "fighter-pangu-index-discovery"
    require(not path.is_symlink() and not path.is_relative_to(ROOT), "Private output must be outside checkout")
    return path


def validate_event(env, event, actual_sha):
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("RUNNER_OS") == "Linux", "GitHub Linux job required")
    require(env.get("GITHUB_REPOSITORY") == REPOSITORY and env.get("GITHUB_REF") == REF, "Repository or ref differs")
    require(env.get("GITHUB_EVENT_NAME") == "push" and env.get("GITHUB_RUN_ATTEMPT") == "1", "Only first push attempt admitted")
    require(re.fullmatch(r"[0-9a-f]{40}", actual_sha or "") is not None and env.get("GITHUB_SHA") == actual_sha,
            "Checkout and event source SHA differ")
    require(env.get("GITHUB_WORKFLOW_SHA") == actual_sha and
            env.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@" + REF,
            "Workflow source differs from admitted checkout")
    require(re.fullmatch(r"[1-9][0-9]*", env.get("GITHUB_RUN_ID", "")) is not None, "Run identity missing")
    require(event.get("ref") == REF and event.get("repository", {}).get("full_name") == REPOSITORY,
            "Push payload repository or ref differs")
    require(event.get("head_commit", {}).get("id") == actual_sha and
            event.get("head_commit", {}).get("message") == MESSAGE, "Push payload source or message differs")


def public_digest(data):
    require(data.startswith(b"-----BEGIN PUBLIC KEY-----\n") and b"PRIVATE KEY" not in data,
            "Only a public evidence recipient is admitted")
    result = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=10)
    return sha(result.stdout)


def source_identity():
    no_resource_keys()
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    validate_event(os.environ, read_json(os.environ["GITHUB_EVENT_PATH"]), actual)
    names = (WORKFLOW, SCRIPT, TEST, *DEPENDENCY_PINS)
    tree = subprocess.check_output(["git", "ls-tree", "-rz", "HEAD", "--", *names], cwd=ROOT)
    committed = {}
    for row in tree.split(b"\0"):
        if not row:
            continue
        fields, name = row.split(b"\t", 1)
        mode, kind, digest = fields.decode().split()
        require(mode in ("100644", "100755") and kind == "blob", "Source tree must contain regular blobs")
        committed[name.decode()] = digest
    require(set(committed) == set(names), "All diagnostic source files must be committed")
    pins = {}
    for name in names:
        data = regular(ROOT / name, 128 * 1024).read_bytes()
        git_digest = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        require(git_digest == committed[name], "Diagnostic source differs from admitted commit")
        pins[name] = sha(data)
    require(all(pins[k] == v for k, v in DEPENDENCY_PINS.items()), "Reviewed evidence dependency changed")
    require(public_digest((ROOT / RECIPIENT).read_bytes()) == RECIPIENT_SPKI_SHA, "Recipient SPKI changed")
    return dict(sourceSHA=actual, workflowSHA=os.environ["GITHUB_WORKFLOW_SHA"],
                repository=REPOSITORY, ref=REF, runID=os.environ["GITHUB_RUN_ID"], attempt=1,
                sourceFiles=pins, recipientSPKISHA256=RECIPIENT_SPKI_SHA)


def prepare():
    identity = source_identity()
    path = directory()
    path.mkdir(mode=0o700, exist_ok=False)
    identity.update(preparedAtUTC=now(), sourceProof=SOURCE_PROOF, requestURL=REQUEST_URL,
                    requestBudget=1, maxResponseBodyBytes=MAX_BODY, deadlineSeconds=HTTP_SECONDS,
                    proxyAndTLS="Runner defaults; no proxy/TLS overrides", resourceSecrets=False,
                    nativeTests=False, deviceValidation=False, assetRecovery=False)
    write_json(path / "identity.json", identity)
    print("Admitted one official bootstrap CI diagnostic; no resource secrets or native tests.")


def identity():
    saved = read_json(directory() / "identity.json")
    current = source_identity()
    require(all(saved.get(k) == v for k, v in current.items()), "Prepared source/run identity changed")
    require(saved.get("requestURL") == REQUEST_URL and saved.get("requestBudget") == 1,
            "Prepared request identity changed")
    return saved


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


class RequestDeadline(TimeoutError):
    pass


@contextlib.contextmanager
def network_deadline():
    def expired(signum, frame):
        raise RequestDeadline("Network deadline reached")
    previous = signal.getsignal(signal.SIGALRM)
    require(signal.getitimer(signal.ITIMER_REAL) == (0.0, 0.0), "Existing process timer rejected")
    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, HTTP_SECONDS)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def strict_object(pairs):
    out = {}
    for key, value in pairs:
        require(key not in out, "Duplicate response JSON field")
        out[key] = value
    return out


def https_location(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 4096 or any(ord(c) < 33 for c in value):
        return False
    try:
        url = urllib.parse.urlsplit(value)
        return url.scheme == "https" and bool(url.hostname) and not url.username and not url.password and not url.fragment and url.port in (None, 443)
    except ValueError:
        return False


def classify(receipt, data):
    markers = (b"destination denied", b"blocked by network policy", b"egress denied",
               b"network policy denied", b"access denied by policy", b"policy_violation")
    header_text = "\n".join(str(k) + ": " + str(v) for k, v in receipt.get("responseHeaders", []))
    denial_text = data.lower() + header_text.encode().lower()
    receipt["explicitPolicyDenialMarker"] = any(value in denial_text for value in markers)
    receipt["jsonObject"] = False
    receipt["locatorCandidate"] = False
    if receipt["explicitPolicyDenialMarker"]:
        return "policy-denied"
    if receipt.get("transportFailure"):
        return "transport-failure"
    if not receipt["bodyComplete"]:
        return "incomplete-response"
    if receipt["status"] != 200:
        return "http-failure"
    if receipt.get("contentEncoding", "").lower() not in ("", "identity"):
        return "unsupported-content-encoding"
    try:
        document = json.loads(data, object_pairs_hook=strict_object)
    except (ValueError, UnicodeError, RecursionError):
        return "non-json-response"
    if not isinstance(document, dict):
        return "non-object-response"
    receipt["jsonObject"] = True
    bundles = document.get("bundles")
    if isinstance(bundles, dict):
        direct = https_location(bundles.get("url"))
        path = bundles.get("path")
        safe_path = isinstance(path, str) and 0 < len(path) <= 4096 and not any(ord(c) < 32 for c in path)
        mirrors = document.get("cdnMirrors")
        mirrored = safe_path and isinstance(mirrors, list) and any(https_location(x) for x in mirrors)
        receipt["locatorCandidate"] = bool(direct or mirrored)
    return "bootstrap-locator-candidate" if receipt["locatorCandidate"] else "json-without-locator"


def capture_http(opener=None):
    # Keep urllib's default ProxyHandler and verified HTTPSHandler. Do not disable
    # proxies, substitute certificates, change DNS or follow a returned location.
    opener = urllib.request.build_opener(NoRedirect()) if opener is None else opener
    request = urllib.request.Request(REQUEST_URL, method="GET")
    receipt = dict(schema="pangu-official-bootstrap-ci-v1", requestedAtUTC=now(),
                   request=dict(url=REQUEST_URL, method="GET", body=None, applicationHeaders=[],
                                clientDefaultHeaders=list(opener.addheaders)),
                   requestCount=0, redirects=0, retries=0, subsequentURLsFetched=0,
                   status=None, responseHeaders=[], bodyComplete=False, transportFailure=None,
                   pythonVersion=sys.version.split()[0], unityWireParityVerified=False)
    response = None
    data = bytearray()
    started = time.monotonic()
    try:
        with network_deadline():
            try:
                receipt["requestCount"] = 1
                response = opener.open(request, timeout=HTTP_SECONDS)
            except urllib.error.HTTPError as error:
                response = error
            receipt["status"] = response.status
            require(type(response.status) is int and 100 <= response.status <= 599, "Invalid HTTP status")
            headers = list(response.headers.items())
            header_bytes = sum(len(str(k).encode()) + len(str(v).encode()) + 4 for k, v in headers)
            if len(headers) > 128 or header_bytes > MAX_HEADERS:
                receipt["boundedStop"] = "headers-over-cap"
            else:
                receipt["responseHeaders"] = headers
                receipt["contentEncoding"] = response.headers.get("Content-Encoding", "")
                length = response.headers.get("Content-Length", "")
                declared = int(length) if re.fullmatch(r"[0-9]{1,20}", length) else None
                receipt["declaredBodyBytes"] = declared
                if declared is not None and declared > MAX_BODY:
                    receipt["boundedStop"] = "declared-body-over-cap"
                else:
                    while len(data) <= MAX_BODY:
                        block = response.read(min(64 * 1024, MAX_BODY + 1 - len(data)))
                        if not block:
                            receipt["bodyComplete"] = declared is None or declared == len(data)
                            if not receipt["bodyComplete"]:
                                receipt["boundedStop"] = "declared-body-truncated"
                            break
                        data.extend(block)
                    if len(data) > MAX_BODY:
                        receipt["boundedStop"] = "stream-body-over-cap"
    except Exception as error:
        # Keep exceptions out of public stdout/stderr; do not serialize ambient
        # proxy configuration or credential-bearing exception strings.
        receipt["transportFailure"] = type(error).__name__
        receipt["bodyComplete"] = False
    finally:
        if response is not None:
            with contextlib.suppress(Exception):
                response.close()
    receipt["elapsedSeconds"] = round(time.monotonic() - started, 3)
    receipt["bodyBytesRead"] = len(data)
    captured = bytes(data[:MAX_BODY])
    receipt["capturedBodyBytes"] = len(captured)
    receipt["capturedBodySHA256"] = sha(captured)
    receipt["completeBodySHA256"] = sha(captured) if receipt["bodyComplete"] else None
    receipt["matchesPrior26ByteFailure"] = receipt["bodyComplete"] and len(captured) == 26 and sha(captured) == OLD_BODY_SHA
    receipt["classification"] = classify(receipt, captured)
    receipt["D19Recovered"] = False
    return receipt, captured


def claim_once(path):
    write_json(path / "request-started.json", dict(startedAtUTC=now(), requestURL=REQUEST_URL, requestBudget=1))


def capture():
    saved = identity()
    path = directory()
    claim_once(path)
    receipt, data = capture_http()
    receipt["sourceSHA"] = saved["sourceSHA"]
    receipt["runID"] = saved["runID"]
    receipt["attempt"] = saved["attempt"]
    write_new(path / "response.bin", data)
    write_json(path / "receipt.json", receipt)
    print("One CI request recorded privately; recording completion does not mean D19 was recovered.")


def wrap_key(key, public, destination):
    public_path = destination.with_suffix(".public.pem")
    try:
        write_new(public_path, public)
        result = subprocess.run(["openssl", "pkeyutl", "-encrypt", "-pubin", "-inkey", str(public_path),
                                 "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256"],
                                input=key, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=10)
        write_new(destination, result.stdout)
    finally:
        public_path.unlink(missing_ok=True)


def existing_recipient():
    tree = ast.parse((ROOT / EXISTING_RECIPIENT).read_text())
    values = [ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
              and any(isinstance(t, ast.Name) and t.id == "PUBLIC_KEY" for t in n.targets)]
    require(len(values) == 1 and isinstance(values[0], str), "Existing public recipient missing")
    return values[0].encode()


def validated_capture(path, saved):
    receipt = read_json(path / "receipt.json")
    body = regular(path / "response.bin", MAX_BODY).read_bytes()
    require(all(receipt.get(k) == saved[k] for k in ("sourceSHA", "runID", "attempt")), "Captured identity differs")
    require(receipt.get("request", {}).get("url") == REQUEST_URL and type(receipt.get("requestCount")) is int and
            receipt["requestCount"] in (0, 1) and
            receipt.get("redirects") == 0 and receipt.get("retries") == 0 and receipt.get("subsequentURLsFetched") == 0,
            "Captured request exceeds reviewed scope")
    require(receipt.get("capturedBodyBytes") == len(body) and receipt.get("capturedBodySHA256") == sha(body),
            "Captured response bytes changed")
    require(receipt.get("D19Recovered") is False and
            receipt.get("classification") == classify(dict(receipt), body), "Captured outcome differs")
    return receipt


def seal():
    saved = identity()
    path = directory()
    validated_capture(path, saved)
    published = path / "published"
    published.mkdir(mode=0o700, exist_ok=False)
    archive = path / "private-evidence.zip"
    try:
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_STORED) as output:
            for name in PRIVATE_NAMES[:4]:
                output.write(regular(path / name, MAX_BODY + 128 * 1024), name)
        archive.chmod(0o600)
        require(archive.stat().st_size <= MAX_BODY + 256 * 1024, "Private receipt archive exceeded cap")
        key = secrets.token_bytes(32)
        wrap_key(key, existing_recipient(), published / CIPHER_NAMES[1])
        wrap_key(key, (ROOT / RECIPIENT).read_bytes(), published / CIPHER_NAMES[2])
        spec = importlib.util.spec_from_file_location("pangu_ci_authenticated_envelope", ROOT / ENVELOPE)
        envelope = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(envelope)
        # Fresh diagnostic-only key; no asset secret is supplied to this job.
        no_resource_keys()
        os.environ["FIGHTER_LIU_MODEL_KEY"] = key.hex()
        try:
            envelope.seal_evidence_file(archive, published / CIPHER_NAMES[0])
        finally:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
            key = b""
        require({p.name for p in published.iterdir()} == set(CIPHER_NAMES), "Unexpected published file")
        sums = "".join(sha(regular(published / name, MAX_BODY + 256 * 1024).read_bytes()) + "  " + name + "\n"
                       for name in CIPHER_NAMES)
        write_new(published / UPLOAD_NAMES[-1], sums.encode())
        print("Sealed bounded diagnostics for two existing public recipients; only four fixed files may upload.")
    except BaseException:
        shutil.rmtree(published, ignore_errors=True)
        raise
    finally:
        archive.unlink(missing_ok=True)


def public_report(receipt, saved, sealed):
    candidate = receipt is not None and receipt.get("classification") == "bootstrap-locator-candidate" and sealed
    return dict(sourceSHA=saved["sourceSHA"], runID=saved["runID"], attempt=saved["attempt"],
                result="bootstrap-locator-candidate" if candidate else "unrecovered",
                classification=receipt["classification"] if receipt else "capture-not-completed",
                ciRequestCompleted=bool(receipt and receipt.get("bodyComplete")),
                requestCount=receipt.get("requestCount", 0) if receipt else 0,
                httpStatus=receipt.get("status") if receipt else None,
                capturedBodyBytes=receipt.get("capturedBodyBytes", 0) if receipt else 0,
                completeBodySHA256=receipt.get("completeBodySHA256") if receipt else None,
                matchesPrior26ByteFailure=bool(receipt and receipt.get("matchesPrior26ByteFailure")),
                encryptedEvidenceComplete=sealed, D19Recovered=False, newD19MotionFiles=0,
                newD19Equipment=0, nativeTestsExecuted=0, deviceValidation=False)


def published_complete(path):
    if not path.is_dir() or path.is_symlink() or {p.name for p in path.iterdir()} != set(UPLOAD_NAMES):
        return False
    try:
        sums = "".join(sha(regular(path / name, MAX_BODY + 256 * 1024).read_bytes()) + "  " + name + "\n"
                       for name in CIPHER_NAMES)
        return regular(path / UPLOAD_NAMES[-1], 1024).read_bytes() == sums.encode()
    except (OSError, GuardError):
        return False


def report():
    saved = identity()
    path = directory()
    receipt = validated_capture(path, saved) if (path / "receipt.json").exists() else None
    published = path / "published"
    sealed = published_complete(published)
    result = public_report(receipt, saved, sealed)
    text = "CI 请求完成不表示已获得 D19。本任务新增 D19 动作文件 0、装备 0；实际响应只在加密回执内。"
    print(json.dumps(result, sort_keys=True))
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write("### Pangu official bootstrap integration\n\n" + text + "\n\n```json\n" + json.dumps(result, indent=2) + "\n```\n")
    return 0 if result["result"] == "bootstrap-locator-candidate" else 1


def cleanup():
    no_resource_keys()
    path = directory()
    for name in PRIVATE_NAMES:
        candidate = path / name
        require(not candidate.is_symlink(), "Symlink plaintext cleanup rejected")
        candidate.unlink(missing_ok=True)
    print("Removed only this diagnostic's private plaintext; encrypted artifact files retained.")


def main():
    os.umask(0o077)
    require(len(sys.argv) == 2 and sys.argv[1] in ("prepare", "capture", "seal", "report", "cleanup"),
            "Usage: prepare | capture | seal | report | cleanup")
    return globals()[sys.argv[1]]() or 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except GuardError as error:
        print("Bootstrap diagnostic guard rejected: " + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("Bootstrap diagnostic failed; response content and exception details were not printed.", file=sys.stderr)
        sys.exit(1)
