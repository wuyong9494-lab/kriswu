#!/usr/bin/env python3
"""One authorized, bounded official Android client launch; no game/API bypass.

SDK installation is delegated to the separately reviewed fixed-archive helper.
Only public metadata/summary reaches Actions. Raw Android logs, screenshots and
ordinary external-files caches are sealed with the existing authenticated
fighter evidence envelope and the already reviewed RSA public recipient.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import signal
import socket
import stat
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
MESSAGE = "Verify active renderer preparation and approved Android continuation 20261115"
WORKFLOW = ".github/workflows/fighter-android-official-client.yml"
HELPER = ".github/scripts/fighter_android_official_client.py"
SDK_HELPER = ".github/scripts/fighter_android_sdk_install.py"
ENVELOPE = ".github/scripts/fighter_private_model.py"
ENVELOPE_SHA = "925c25094359c4df9cc901a54e11e4374ea471e7cb8680b77380360767b15d79"
RECIPIENT = ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
PACKAGE = "com.nekki.shadowfight3"
APK_URL = "https://sf3assets.nekki.com/builds/apk/7/19221.apk"
APK_BYTES = 263_891_547
MANIFEST_SHA = "4b009c7cfa57dace3c4affec9b6d8757bdadc5d3d2d90a47d3dd97b1af705171"
CENTRAL_SHA = "abaebf457c31bd2bb5d2231225098afef0a9a3a41a45a0e28930dcb68539b583"
LICENSE_SHA256 = "1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16"
LICENSE_SHA1 = "efa68a6b3c661d18699d5c026771d5911cdc2f83"
OFFICIAL_LICENSE_SHA1 = "24333f8a63b6825ea9c5514f83c2829b004d1fee"
OFFICIAL_LICENSE_SHA256 = "aaf80cd0aee7e569ffa8a4be1b61189c0fefccf23068e38dfafe336289b8c723"
LICENSE_ACCEPTANCE_BASIS = "official_adapted_identity_not_original_XML_bytes"
SYSTEM_SDK = Path("/usr/local/lib/android/sdk")
EXTERNAL_ROOT = "/sdcard/Android/data/" + PACKAGE + "/files"
CONFIG_ROOT = EXTERNAL_ROOT + "/gamedata/Resources/Configs"
MIB = 1024**2
STEM = "fighter-android-official-client-evidence"
PORT = 5556
ADB_PORT = 5038
SERIAL = "emulator-" + str(PORT)
MAX_EMULATOR_SECONDS = 600
MAX_GUEST_NETWORK_BYTES = 256 * MIB
ACTIVE_EMULATOR_DEADLINE = None
BACKGROUND_LOGS = {}


class BoundedBackgroundLog:
    """Drain a background child without allowing its log to fill the runner."""
    def __init__(self, stream, label):
        self.stream, self.label = stream, label
        self.total, self.hasher, self.tail = 0, hashlib.sha256(), bytearray()
        self.complete, self.error = False, None
        self.thread = threading.Thread(target=self.read, daemon=True)
        self.thread.start()

    def read(self):
        try:
            while block := self.stream.read(65536):
                self.total += len(block)
                self.hasher.update(block)
                self.tail.extend(block)
                if len(self.tail) > 2*MIB:
                    del self.tail[:-2*MIB]
            self.complete = True
        except Exception as error:
            self.error = type(error).__name__

    def finish(self):
        self.thread.join(timeout=5)
        raw = bytes(self.tail)
        (evidence()/(self.label+".log")).write_bytes(raw)
        write_json(evidence()/(self.label+"-capture.json"), {"sourceBytesObserved":self.total,
            "sourceSHA256Observed":self.hasher.hexdigest(), "streamComplete":self.complete,
            "archivedBytes":len(raw), "archivedSHA256":sha(raw),
            "tailOnly":self.total != len(raw), "readError":self.error})


class Blocked(Exception):
    """A fixed, non-sensitive reason safe for the public summary."""


def need(condition, reason):
    if not condition:
        raise Blocked(reason)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def work():
    root = Path(os.environ["RUNNER_TEMP"])
    need(root.is_absolute() and root.is_dir() and not root.is_symlink(), "runner_temp_invalid")
    return root / "fighter-android-official-client"


def evidence():
    return work() / "evidence"


def read_state():
    return json.loads((evidence() / "result.json").read_text())


def save_state(state):
    write_json(evidence() / "result.json", state)


def admit():
    expected = {"GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": REPOSITORY,
                "GITHUB_REF": BRANCH, "GITHUB_EVENT_NAME": "push", "GITHUB_RUN_ATTEMPT": "1"}
    need(all(os.environ.get(k) == v for k, v in expected.items()), "execution_identity_mismatch")
    need(re.fullmatch(r"[a-f0-9]{40}", os.environ.get("GITHUB_SHA", "")), "source_sha_invalid")
    need(re.fullmatch(r"[0-9]+", os.environ.get("GITHUB_RUN_ID", "")), "run_id_invalid")
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    need(event.get("after") == os.environ["GITHUB_SHA"] and event.get("ref") == BRANCH
         and event.get("repository", {}).get("full_name") == REPOSITORY
         and event.get("head_commit", {}).get("message") == MESSAGE, "push_identity_mismatch")
    for path, variable in ((HELPER, "EXPECTED_ANDROID_CLIENT_HELPER_SHA256"),
                           (SDK_HELPER, "EXPECTED_ANDROID_SDK_HELPER_SHA256")):
        need(digest(ROOT / path) == os.environ.get(variable), "reviewed_helper_pin_mismatch")
    need(digest(ROOT / ENVELOPE) == ENVELOPE_SHA, "reviewed_envelope_pin_mismatch")
    need(not any(os.environ.get(k) for k in ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_H17_D19_KEY",
                                            "FIGHTER_PRESENTATION_KEY")), "resource_secrets_forbidden")
    public_der = subprocess.run(["openssl", "pkey", "-pubin", "-in", str(ROOT / RECIPIENT),
                                 "-outform", "DER"], capture_output=True, timeout=15, check=True).stdout
    need(sha(public_der) == RECIPIENT_SPKI, "recipient_identity_mismatch")


def command(args, label, timeout=30, *, env=None, input_bytes=None, ok=(0,), maximum=8*MIB):
    """Never print command output: APK/tool/App output may include private URLs."""
    if ACTIVE_EMULATOR_DEADLINE is not None:
        timeout = min(timeout, ACTIVE_EMULATOR_DEADLINE-time.monotonic())
        need(timeout > 0, "emulator_lifetime_bound")
    log = evidence() / (label + ".log")
    need(not log.exists(), "command_label_reused")
    started = time.monotonic()
    with log.open("xb") as output:
        proc = subprocess.Popen(list(map(str, args)), stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
                                stdout=output, stderr=subprocess.STDOUT, env=env)
        try:
            if input_bytes is not None:
                proc.stdin.write(input_bytes)
                proc.stdin.close()
            while proc.poll() is None:
                if time.monotonic() - started > timeout or log.stat().st_size > maximum:
                    proc.kill()
                    proc.wait(timeout=10)
                    raise Blocked("command_time_or_output_bound_" + label)
                time.sleep(0.1)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=10)
    raw = log.read_bytes()
    write_json(evidence() / (label + "-process.json"), {
        "exitCode": proc.returncode, "elapsedSeconds": time.monotonic()-started,
        "bytes": len(raw), "sha256": sha(raw)})
    need(proc.returncode in ok, "command_failed_" + label)
    return raw.decode("utf-8", errors="replace"), proc.returncode


def tools_inventory(state):
    need(sys.platform == "linux" and os.uname().machine == "x86_64", "runner_architecture_mismatch")
    need(shutil.disk_usage(work()).free >= 18 * 1024**3, "insufficient_disk_before_install")
    paths = {"sdkmanager": SYSTEM_SDK / "cmdline-tools/latest/bin/sdkmanager",
             "avdmanager": SYSTEM_SDK / "cmdline-tools/latest/bin/avdmanager",
             "adb": SYSTEM_SDK / "platform-tools/adb"}
    versions = sorted((p for p in (SYSTEM_SDK / "build-tools").iterdir()
                       if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", p.name)),
                      key=lambda p: tuple(map(int, p.name.split("."))), reverse=True)
    candidates = [p for p in versions if (p / "apksigner").is_file() and (p / "aapt").is_file()]
    need(candidates, "existing_apk_verification_tools_missing")
    paths.update({"apksigner": candidates[0] / "apksigner", "aapt": candidates[0] / "aapt"})
    for name in ("getfacl", "setfacl", "sudo", "java", "openssl"):
        executable = shutil.which(name)
        need(executable, "existing_tool_missing_" + name)
        paths[name] = Path(executable)
    need(all(p.is_file() and os.access(p, os.X_OK) for p in paths.values()), "existing_tool_not_executable")
    kvm = Path("/dev/kvm")
    need(kvm.exists() and stat.S_ISCHR(kvm.stat().st_mode), "kvm_device_missing")
    info = kvm.stat()
    state["runner"] = {"imageOS": os.environ.get("ImageOS"), "imageVersion": os.environ.get("ImageVersion"),
        "architecture": os.uname().machine, "uid": os.getuid(), "freeBytes": shutil.disk_usage(work()).free,
        "tools": {k: {"path": str(v), "sha256": digest(v)} for k, v in paths.items()},
        "kvmIdentity": [info.st_dev, info.st_ino, info.st_rdev, info.st_uid, info.st_gid]}
    state["toolPaths"] = {k: str(v) for k, v in paths.items()}
    save_state(state)
    for name, args in (("java", ["-version"]), ("adb", ["version"]), ("apksigner", ["version"]),
                       ("aapt", ["version"]), ("sdkmanager", ["--version"])):
        command([paths[name], *args], "existing-" + name + "-version", 45)
    return paths


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def download_apk_once(state):
    destination = work() / "downloads" / "19221.apk"
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    need(not destination.exists(), "apk_download_already_attempted")
    state["executed"]["apkDownloads"] += 1
    save_state(state)
    request = urllib.request.Request(APK_URL, headers={"Accept-Encoding": "identity"})
    started, count, hasher = time.monotonic(), 0, hashlib.sha256()
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
            need(response.status == 200 and response.geturl() == APK_URL, "official_apk_response_mismatch")
            need(response.headers.get("Content-Encoding", "identity").lower() == "identity", "apk_content_encoding")
            length = response.headers.get("Content-Length")
            need(length is None or length == str(APK_BYTES), "apk_declared_size_changed")
            with destination.open("xb") as target:
                while block := response.read(MIB):
                    count += len(block)
                    need(count <= APK_BYTES and time.monotonic()-started <= 240, "apk_download_bound")
                    target.write(block)
                    hasher.update(block)
    except (urllib.error.URLError, TimeoutError, OSError):
        raise Blocked("official_apk_download_failed") from None
    need(count == APK_BYTES, "apk_download_incomplete")
    state["apk"] = {"url": APK_URL, "bytes": count, "sha256": hasher.hexdigest(),
                    "downloadSeconds": time.monotonic()-started, "downloadCount": 1}
    save_state(state)
    return destination


def central_directory(raw_tail, file_size):
    pos = raw_tail.rfind(b"PK\x05\x06")
    need(pos >= 0 and len(raw_tail)-pos >= 22, "apk_eocd_missing")
    fields = struct.unpack_from("<4s4H2IH", raw_tail, pos)
    _, disk, central_disk, disk_count, count, size, offset, comment = fields
    absolute = file_size-len(raw_tail)+pos
    need(disk == central_disk == 0 and disk_count == count == 3119
         and size == 293445 and offset+size == absolute
         and pos+22+comment == len(raw_tail), "apk_central_directory_changed")
    return offset, size


def verify_apk(path, tools, state):
    with path.open("rb") as stream:
        stream.seek(-min(path.stat().st_size, 65557), 2)
        offset, size = central_directory(stream.read(), path.stat().st_size)
        stream.seek(offset)
        need(sha(stream.read(size)) == CENTRAL_SHA, "apk_central_hash_changed")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        need(len(entries) == 3119 and len({i.filename for i in entries}) == 3119, "apk_member_identity_changed")
        need(sum(i.file_size for i in entries) <= 2 * 1024**3, "apk_uncompressed_bound")
        need(sha(archive.read("AndroidManifest.xml")) == MANIFEST_SHA, "apk_manifest_changed")
        need(archive.testzip() is None, "apk_zip_crc_failed")
        counts = {abi: sum(i.filename.startswith("lib/"+abi+"/") and i.filename.endswith(".so")
                           for i in entries) for abi in ("arm64-v8a", "armeabi-v7a", "x86", "x86_64")}
        need(counts == {"arm64-v8a":24, "armeabi-v7a":24, "x86":0, "x86_64":0}, "apk_native_abi_changed")
    signature, _ = command([tools["apksigner"], "verify", "--verbose", "--print-certs", path], "apk-signature", 120)
    signers = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
    need(signers, "apk_signature_digest_missing")
    badging, _ = command([tools["aapt"], "dump", "badging", path], "apk-badging", 60)
    need(re.search(r"package: name='com\.nekki\.shadowfight3' versionCode='19221' versionName='1\.46\.0'", badging),
         "apk_package_version_mismatch")
    state["apk"].update({"packageName":PACKAGE, "versionName":"1.46.0", "versionCode":19221,
                         "manifestSHA256":MANIFEST_SHA, "centralDirectorySHA256":CENTRAL_SHA,
                         "zipCRCVerified":True, "nativeLibraries":counts, "signerSHA256":signers})
    state["gates"]["apkSignatureVerified"] = True
    save_state(state)


def effective_acl(entries):
    """Parse getfacl numeric ACL; never grant a broader mask to enable KVM."""
    result = {}
    for line in entries.splitlines():
        if not line or line.startswith("#"):
            continue
        item = line.split("\t", 1)[0].split(" #", 1)[0]
        parts = item.split(":")
        need(len(parts) == 3 and parts[0] in ("user", "group", "mask", "other")
             and re.fullmatch(r"[r-][w-][x-]", parts[2]), "unexpected_kvm_acl")
        result[(parts[0], parts[1])] = parts[2]
    return result


def prepare_kvm(tools, state):
    raw, _ = command([tools["getfacl"], "-n", "-p", "/dev/kvm"], "kvm-before", 15)
    acl = effective_acl(raw)
    state["kvm"] = {"changed":False, "beforeACL":raw, "restored":False}
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        mask = acl.get(("mask", ""), acl.get(("group", ""), "---"))
        need(mask[:2] == "rw", "kvm_mask_would_require_broadening")
        need(("user", str(os.getuid())) not in acl, "existing_runner_acl_requires_separate_review")
        change = [tools["sudo"], "-n", tools["setfacl"], "--no-mask", "-m", "u:"+str(os.getuid())+":rw", "/dev/kvm"]
        command([*change[:3], "--test", *change[3:]], "kvm-acl-proposal", 15)
        # Set intent first: cleanup checks actual ACL even if the command fails.
        state["kvm"]["changeAttempted"] = True
        save_state(state)
        command(change, "kvm-acl-apply", 15)
        after, _ = command([tools["getfacl"], "-n", "-p", "/dev/kvm"], "kvm-after", 15)
        parsed = effective_acl(after)
        expected = dict(acl)
        expected[("user", str(os.getuid()))] = "rw-"
        if ("mask", "") not in expected:
            expected[("mask", "")] = mask
        need(parsed == expected and os.access("/dev/kvm", os.R_OK | os.W_OK), "kvm_acl_not_exact")
        state["kvm"].update({"changed":True, "afterACL":after})
    state["gates"]["kvmReady"] = True
    save_state(state)


def android_env(sdk_root):
    values = dict(os.environ)
    values.update({"ANDROID_HOME":str(sdk_root), "ANDROID_SDK_ROOT":str(sdk_root),
        "ANDROID_USER_HOME":str(work()/"android-user"), "ANDROID_AVD_HOME":str(work()/"avds"),
        "ANDROID_ADB_SERVER_PORT":str(ADB_PORT), "ADB_SERVER_PORT":str(ADB_PORT),
        "ADB_SERVER_SOCKET":"tcp:127.0.0.1:"+str(ADB_PORT)})
    return values


def adb_command(tools, args, label, timeout=30, **kwargs):
    state = read_state()
    owner = state.get("adbServer")
    need(owner and Path("/proc", str(owner["pid"])).exists()
         and same_owned_process(owner["pid"], owner["processIdentity"]), "owned_adb_server_unavailable")
    return command([tools["adb"], "-P", str(ADB_PORT), "-s", SERIAL, *args], label, timeout, **kwargs)


def proc_identity(pid):
    path = Path("/proc") / str(pid)
    raw = (path/"stat").read_text()
    return {"startTimeTicks":raw[raw.rfind(")")+2:].split()[19],
            "uid":path.stat().st_uid, "processGroup":os.getpgid(pid),
            "commandSHA256":sha((path/"cmdline").read_bytes())}


def same_owned_process(pid, expected):
    actual = proc_identity(pid)
    # exec from the emulator launcher to QEMU changes argv, never ownership,
    # process start time or our new process group. Do not mistake it for reuse.
    return all(actual[k] == expected[k] for k in ("startTimeTicks", "uid", "processGroup")) and actual["processGroup"] == pid


def wait_owned_exit(pid, seconds):
    deadline = time.monotonic()+seconds
    while Path("/proc",str(pid)).exists() and time.monotonic()<deadline:
        try:
            child, _ = os.waitpid(pid,os.WNOHANG)
            if child:
                break
        except ChildProcessError:
            pass
        time.sleep(0.2)
    return not Path("/proc",str(pid)).exists()


def guest_bytes(text):
    total = 0
    for line in text.splitlines():
        if ":" not in line:
            continue
        name, value = line.split(":", 1)
        fields = value.split()
        if name.strip() != "lo" and len(fields) == 16 and all(x.isdecimal() for x in fields):
            total += int(fields[0])+int(fields[8])
    return total


def start_emulator(tools, sdk, state):
    global ACTIVE_EMULATOR_DEADLINE
    emulator = Path(sdk["emulator_path"])
    env = android_env(Path(sdk["private_sdk_root"]))
    private_avdmanager = Path(sdk["avdmanager_path"])
    need(private_avdmanager.is_file() and digest(private_avdmanager) == digest(tools["avdmanager"]),
         "private_avdmanager_copy_changed")
    # The official CLI locates its SDK via canonical toolsdir, not ANDROID_HOME.
    # The helper copied the already installed CLI, so this path must be real.
    need(Path(sdk["private_sdk_root"]).resolve() in private_avdmanager.resolve().parents,
         "avdmanager_canonical_sdk_not_private")
    # Emulator's SDK-relative adb discovery reuses the existing platform tools.
    # This is a symlink, not an OS read-only mount and not another package install.
    platform_link = Path(sdk["private_sdk_root"])/"platform-tools"
    need(not platform_link.exists() and not platform_link.is_symlink(), "private_platform_tools_path_exists")
    platform_link.symlink_to(SYSTEM_SDK/"platform-tools", target_is_directory=True)
    state["existingPlatformToolsReuse"] = {"policy":"reuse_existing_no_upgrade", "type":"directory_symlink",
        "target":str(SYSTEM_SDK/"platform-tools"), "adbSHA256":digest(tools["adb"]), "osReadOnlyMount":False}
    state["androidEnvironment"] = {k:env[k] for k in ("ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_USER_HOME", "ANDROID_AVD_HOME")}
    for directory in (work()/"android-user", work()/"avds"):
        directory.mkdir(mode=0o700, exist_ok=True)
    command([emulator, "-version"], "emulator-version", 30, env=env)
    command([emulator, "-accel-check"], "emulator-accel-check", 30, env=env)
    state["gates"]["prerequisitesReady"] = True
    save_state(state)
    gpu_help, _ = command([emulator, "-help-gpu"], "emulator-gpu-help", 30, env=env)
    need(re.search(r"\bswiftshader\b", gpu_help), "approved_software_gpu_mode_unavailable")
    net_help, _ = command([emulator, "-help-netspeed"], "emulator-network-help", 30, env=env)
    need("<up>" in net_help or "upload" in net_help.lower() or "<speed>" in net_help, "network_rate_control_unavailable")
    devices, _ = command([private_avdmanager, "list", "device"], "avd-device-profiles", 45, env=env)
    need('"pixel_2"' in devices, "reviewed_device_profile_unavailable")
    for port in (PORT, PORT+1, ADB_PORT):
        with socket.socket() as sock:
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                raise Blocked("owned_android_port_unavailable") from None
    name = "fighter_d19_" + os.environ["GITHUB_RUN_ID"]
    avd = work()/"avds"/(name+".avd")
    need(not avd.exists(), "avd_already_exists")
    command([private_avdmanager, "create", "avd", "-n", name, "-k",
             "system-images;android-30;google_apis;x86_64", "-p", avd, "-d", "pixel_2"],
            "avd-create", 60, env=env, input_bytes=b"no\n")
    config = avd/"config.ini"
    content = config.read_text()
    for key, value in (("hw.ramSize", "2048"), ("disk.dataPartition.size", "2G")):
        content = re.sub(r"(?m)^"+re.escape(key)+r"=.*\n?", "", content)+key+"="+value+"\n"
    config.write_text(content)
    adb_process = subprocess.Popen([str(tools["adb"]), "-P", str(ADB_PORT), "nodaemon", "server"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, start_new_session=True)
    BACKGROUND_LOGS["adb-server"] = BoundedBackgroundLog(adb_process.stdout, "adb-server")
    state["adbServer"] = {"pid":adb_process.pid, "processIdentity":proc_identity(adb_process.pid), "port":ADB_PORT}
    state["adbServerStarted"] = True
    save_state(state)
    adb_ready_deadline = time.monotonic()+15
    while True:
        need(adb_process.poll() is None, "owned_adb_server_exited")
        try:
            with socket.create_connection(("127.0.0.1", ADB_PORT), timeout=1):
                break
        except OSError:
            need(time.monotonic()<adb_ready_deadline, "owned_adb_server_start_timeout")
            time.sleep(0.2)
    state["executed"]["emulatorBoots"] += 1
    need(state["executed"]["emulatorBoots"] == 1, "emulator_restart_forbidden")
    args = [str(emulator), "-avd", name, "-no-snapshot", "-no-window", "-no-audio", "-accel", "on",
            "-gpu", "swiftshader", "-netspeed", "1024:1024", "-port", str(PORT)]
    process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, start_new_session=True)
    BACKGROUND_LOGS["emulator-runtime"] = BoundedBackgroundLog(process.stdout, "emulator-runtime")
    ACTIVE_EMULATOR_DEADLINE = time.monotonic()+MAX_EMULATOR_SECONDS
    state["emulator"] = {"pid":process.pid, "processIdentity":proc_identity(process.pid), "name":name,
        "serial":SERIAL, "consolePort":PORT, "adbServerPort":ADB_PORT, "startedAt":now(),
        "monotonicStart":time.monotonic(), "arguments":args, "avdPath":str(avd)}
    save_state(state)
    deadline = time.monotonic()+180
    for index in range(37):
        need(process.poll() is None, "emulator_exited_before_boot")
        value, _ = adb_command(tools, ["shell", "getprop", "sys.boot_completed"], "boot-poll-"+str(index), 5, ok=(0,1))
        if value.strip() == "1":
            break
        need(time.monotonic() < deadline, "emulator_boot_deadline")
        time.sleep(5)
    else:
        raise Blocked("emulator_boot_deadline")
    observed_name, _ = adb_command(tools, ["emu", "avd", "name"], "avd-identity", 15)
    need(observed_name.splitlines()[0] == name, "connected_device_identity_mismatch")
    props = {}
    for key in ("ro.build.version.sdk", "ro.product.cpu.abilist", "ro.product.cpu.abilist32",
                "ro.product.cpu.abilist64", "ro.dalvik.vm.native.bridge", "ro.build.fingerprint"):
        raw, _ = adb_command(tools, ["shell", "getprop", key], "device-"+key, 15)
        props[key] = raw.strip()
    need(props["ro.build.version.sdk"] == "30", "booted_api_mismatch")
    state["deviceProperties"] = props
    state["gates"]["imageBooted"] = True
    arm = set(props["ro.product.cpu.abilist"].split(",")) & {"arm64-v8a", "armeabi-v7a"}
    state["gates"]["apkABICompatible"] = bool(arm and props["ro.dalvik.vm.native.bridge"] not in ("", "0"))
    state["abiCompatibilityBasis"] = "guest_advertised_ABI_and_native_bridge_only_not_game_execution"
    save_state(state)
    need(state["gates"]["apkABICompatible"], "image_arm_native_bridge_unavailable")


def wall_reason(xml_raw):
    """Read visible UI only; no click, login, agreement or permission acceptance."""
    try:
        root = ET.fromstring(xml_raw)
    except ET.ParseError:
        return None
    text = "\n".join(n.get("text", "")+" "+n.get("content-desc", "") for n in root.iter("node")).casefold()
    patterns = {
        "new_terms_or_privacy_prompt": r"terms (?:of (?:use|service)|and conditions)|privacy policy|user agreement|end.user licen[cs]e|用户协议|隐私政策|使用条款|服务条款|условия использования|политик[аи] конфиденциальности",
        "account_or_captcha_prompt": r"sign in|log in|login to|enter your (?:email|password)|captcha|验证码|登录账号|登录账户|войти в аккаунт",
        "purchase_prompt": r"purchase|buy now|payment method|立即购买|支付方式",
        "system_permission_prompt": r"allow .* (?:access|record|take|send)|while using the app|only this time|允许.*(?:访问|录音|相机|通知)|仅在使用",
    }
    for reason, pattern in patterns.items():
        if re.search(pattern, text):
            return reason
    return None


def snapshot(tools, index):
    owner = read_state().get("adbServer")
    need(owner and Path("/proc",str(owner["pid"])).exists()
         and same_owned_process(owner["pid"],owner["processIdentity"]), "owned_adb_server_unavailable")
    image_path = evidence()/f"screen-{index:02d}.png"
    timeout = min(20, ACTIVE_EMULATOR_DEADLINE-time.monotonic()) if ACTIVE_EMULATOR_DEADLINE is not None else 20
    need(timeout > 0, "emulator_lifetime_bound")
    proc = subprocess.run([str(tools["adb"]), "-P", str(ADB_PORT), "-s", SERIAL,
                           "exec-out", "screencap", "-p"], capture_output=True, timeout=timeout)
    need(proc.returncode == 0 and proc.stdout.startswith(b"\x89PNG\r\n\x1a\n") and len(proc.stdout) <= 16*MIB,
         "screenshot_capture_failed")
    image_path.write_bytes(proc.stdout)
    remote = "/sdcard/fighter_d19_"+os.environ["GITHUB_RUN_ID"]+"_ui.xml"
    _, code = adb_command(tools, ["shell", "uiautomator", "dump", remote], "ui-dump-"+str(index), 20, ok=(0,1))
    if code:
        return None
    xml, code = adb_command(tools, ["shell", "cat", remote], "ui-hierarchy-"+str(index), 15, ok=(0,1), maximum=2*MIB)
    return wall_reason(xml) if code == 0 else None


def cache_name_allowed(path):
    prefix = PurePosixPath(CONFIG_ROOT)
    candidate = PurePosixPath(path)
    return (candidate.parent == prefix and candidate.name not in (".", "..")
            and re.fullmatch(r"bundles_[0-9]{1,20}\.bytes", candidate.name) is not None
            and str(candidate) == path)


def collect_cache(tools, state):
    # Exact package and known relative cache chain only. No app sandbox, root,
    # run-as, backup, guessed archive URL or blanket filesystem traversal.
    listing, code = adb_command(tools, ["shell", "ls", "-1", CONFIG_ROOT], "ordinary-config-cache-list", 20, ok=(0,1,2))
    state["cache"] = {"requestedRoot":CONFIG_ROOT, "ordinaryShellReadable":code == 0, "files":[]}
    if code:
        save_state(state)
        return
    names = [line for line in listing.splitlines() if cache_name_allowed(CONFIG_ROOT+"/"+line)]
    need(len(names) <= 8, "bootstrap_cache_count_bound")
    total = 0
    for index, name in enumerate(names):
        path = CONFIG_ROOT+"/"+name
        # A colon is safe in adb's remote shell; an unquoted pipe is not.
        details, _ = adb_command(tools, ["shell", "stat", "-c", "%f:%s", path], "cache-stat-"+str(index), 15)
        need(re.fullmatch(r"[0-9a-fA-F]+:[0-9]+\s*", details), "cache_stat_invalid")
        mode, size_text = details.strip().split(":")
        need(stat.S_ISREG(int(mode,16)), "cache_not_regular")
        size = int(size_text)
        total += size
        need(0 < size <= 32*MIB and total <= 64*MIB, "bootstrap_cache_bytes_bound")
        destination = evidence()/"cache"/name
        destination.parent.mkdir(mode=0o700, exist_ok=True)
        adb_command(tools, ["pull", path, str(destination)], "cache-pull-"+str(index), 45)
        need(destination.is_file() and not destination.is_symlink() and destination.stat().st_size == size,
             "bootstrap_cache_pull_mismatch")
        state["cache"]["files"].append({"file":name, "bytes":size, "sha256":digest(destination),
            "origin":"ordinary-external-files-cache", "contentDecoded":False, "d19AssetsProven":False})
    state["gates"]["readableBootstrapCatalogObtained"] = bool(names)
    save_state(state)


def launch(tools, apk, state):
    state["executed"]["apkInstalls"] += 1
    save_state(state)
    output, _ = adb_command(tools, ["install", str(apk)], "official-apk-install", 90)
    need(re.search(r"(?m)^Success\s*$", output), "apk_install_not_successful")
    state["gates"]["apkInstalled"] = True
    resolved, _ = adb_command(tools, ["shell", "cmd", "package", "resolve-activity", "--brief", "-a",
        "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", PACKAGE], "main-activity-resolver", 20)
    matches = [line.strip() for line in resolved.splitlines() if re.fullmatch(re.escape(PACKAGE)+r"/[A-Za-z0-9_.$]+", line.strip())]
    need(len(matches) == 1, "official_main_activity_not_unique")
    state["activity"] = matches[0]
    state["executed"]["apkLaunches"] += 1
    need(state["executed"]["apkLaunches"] == 1, "app_relaunch_forbidden")
    state["launchStartedAt"] = now()
    save_state(state)
    started, _ = adb_command(tools, ["shell", "am", "start", "-W", "-n", matches[0]], "official-app-start", 45)
    need("Status: ok" in started and "Error:" not in started, "app_launch_failed")
    state["gates"]["normalLaunchObserved"] = True
    state["observation"] = {"limitSeconds":180, "stopReason":None, "humanPixels":"PENDING", "audioOrPerformanceAcceptance":False}
    save_state(state)
    observation_start = time.monotonic()
    for index in range(12):
        need(time.monotonic()-state["emulator"]["monotonicStart"] < MAX_EMULATOR_SECONDS, "emulator_lifetime_bound")
        net, _ = adb_command(tools, ["shell", "cat", "/proc/net/dev"], "guest-network-"+str(index), 10)
        count = guest_bytes(net)
        state["observation"]["guestInterfaceBytes"] = count
        need(count <= MAX_GUEST_NETWORK_BYTES, "guest_network_budget")
        pid, code = adb_command(tools, ["shell", "pidof", PACKAGE], "app-pid-"+str(index), 10, ok=(0,1))
        if code or not re.fullmatch(r"[0-9]+\s*", pid):
            state["observation"]["stopReason"] = "app_process_unavailable"
            snapshot(tools, index)
            break
        state["appPID"] = int(pid.strip())
        wall = snapshot(tools, index)
        if wall:
            state["observation"]["stopReason"] = wall
            break
        if time.monotonic()-observation_start >= 180:
            state["observation"]["stopReason"] = "bounded_observation_complete"
            break
        time.sleep(min(10, max(0, 180-(time.monotonic()-observation_start))))
    if state["observation"]["stopReason"] is None:
        state["observation"]["stopReason"] = "bounded_observation_complete"
    state["observation"]["elapsedSeconds"] = time.monotonic()-observation_start
    save_state(state)
    if state.get("appPID"):
        adb_command(tools, ["logcat", "--pid="+str(state["appPID"]), "-d", "-v", "threadtime"],
                    "official-app-logcat", 20, ok=(0,1), maximum=24*MIB)
    collect_cache(tools, state)


def stop_owned(state):
    global ACTIVE_EMULATOR_DEADLINE
    ACTIVE_EMULATOR_DEADLINE = None
    tools = {k:Path(v) for k,v in state.get("toolPaths", {}).items()}
    attempt = state.get("cleanupAttempts", 0)+1
    state["cleanupAttempts"] = attempt
    def cleanup_command(args, label, timeout=15):
        return command(args, label+"-attempt-"+str(attempt), timeout)
    cleanup = {"emulatorStopped":not bool(state.get("emulator")), "adbStopped":not state.get("adbServerStarted",False),
               "kvmRestored":not state.get("kvm",{}).get("changeAttempted",False), "errors":[]}
    emu = state.get("emulator")
    if emu:
        try:
            pid = emu["pid"]
            if Path("/proc", str(pid)).exists():
                need(same_owned_process(pid, emu["processIdentity"]), "owned_emulator_pid_changed")
                os.killpg(pid, signal.SIGTERM)
                if not wait_owned_exit(pid,20):
                    need(same_owned_process(pid, emu["processIdentity"]), "owned_emulator_pid_changed")
                    os.killpg(pid, signal.SIGKILL)
                    need(wait_owned_exit(pid,5), "owned_emulator_exit_not_confirmed")
            need(not Path("/proc",str(pid)).exists(), "owned_emulator_exit_not_confirmed")
            cleanup["emulatorStopped"] = True
        except Exception as error:
            cleanup["errors"].append("emulator:"+type(error).__name__)
    if state.get("adbServerStarted"):
        try:
            owner = state["adbServer"]
            pid = owner["pid"]
            if Path("/proc",str(pid)).exists():
                need(same_owned_process(pid,owner["processIdentity"]), "owned_adb_pid_changed")
                os.killpg(pid,signal.SIGTERM)
                if not wait_owned_exit(pid,10):
                    need(same_owned_process(pid,owner["processIdentity"]), "owned_adb_pid_changed")
                    os.killpg(pid,signal.SIGKILL)
                    need(wait_owned_exit(pid,5), "owned_adb_exit_not_confirmed")
            need(not Path("/proc",str(pid)).exists(), "owned_adb_exit_not_confirmed")
            cleanup["adbStopped"] = True
        except Exception as error:
            cleanup["errors"].append("adb:"+type(error).__name__)
    kvm = state.get("kvm", {})
    if kvm.get("changeAttempted"):
        try:
            info = Path("/dev/kvm").stat()
            need([info.st_dev,info.st_ino,info.st_rdev,info.st_uid,info.st_gid] == state["runner"]["kvmIdentity"],
                 "kvm_device_identity_changed")
            current, _ = cleanup_command([tools["getfacl"], "-n", "-p", "/dev/kvm"], "kvm-cleanup-current", 15)
            original = effective_acl(kvm["beforeACL"])
            actual = effective_acl(current)
            uid_key = ("user", str(os.getuid()))
            if uid_key in actual:
                need(actual[uid_key] == "rw-" and uid_key not in original, "kvm_owned_acl_changed")
                cleanup_command([tools["sudo"], "-n", tools["setfacl"], "--no-mask", "-x", "u:"+str(os.getuid()), "/dev/kvm"],
                        "kvm-owned-acl-remove", 15)
            after, _ = cleanup_command([tools["getfacl"], "-n", "-p", "/dev/kvm"], "kvm-cleanup-after", 15)
            parsed = effective_acl(after)
            if ("mask", "") not in original and ("mask", "") in parsed:
                # Our added ACL may create a mask. Remove it only if every
                # other entry remains the exact saved original.
                without = {k:v for k,v in parsed.items() if k != ("mask", "")}
                need(without == original, "concurrent_kvm_acl_change")
                cleanup_command([tools["sudo"], "-n", tools["setfacl"], "--no-mask", "-x", "m", "/dev/kvm"], "kvm-owned-mask-remove", 15)
                after, _ = cleanup_command([tools["getfacl"], "-n", "-p", "/dev/kvm"], "kvm-final", 15)
                parsed = effective_acl(after)
            need(parsed == original, "kvm_cleanup_not_original")
            cleanup["kvmRestored"] = True
        except Exception as error:
            cleanup["errors"].append("kvm:"+type(error).__name__)
    for name, reader in BACKGROUND_LOGS.items():
        try:
            reader.finish()
            if not reader.complete:
                cleanup["errors"].append("log_stream:"+name)
        except Exception as error:
            cleanup["errors"].append("log_capture:"+type(error).__name__)
    state["cleanup"] = cleanup
    save_state(state)
    return cleanup


def license_acceptance_summary(receipt=None):
    """Keep user-approved XML bytes separate from official-tool acceptance."""
    receipt = receipt if isinstance(receipt, dict) else {}
    legal = receipt.get("license") if isinstance(receipt.get("license"), dict) else {}
    original = legal.get("approvedOriginal")
    adapted = legal.get("officialAdaptedIdentity")
    accepted = (receipt.get("approvedTermsAccepted") is True
        and receipt.get("licenseAcceptedForExactText") is True
        and receipt.get("licenseAcceptedForExactTextBasis") == LICENSE_ACCEPTANCE_BASIS
        and legal.get("acceptedRepresentation") == "official_jaxb_adapted"
        and legal.get("acceptedRecordSHA1") == OFFICIAL_LICENSE_SHA1
        and legal.get("originalBytesEqual") is False
        and legal.get("approvedOriginalBytesAcceptedVerbatim") is False
        and original == {"id":"android-sdk-license", "utf8Bytes":16962,
                         "sha1":LICENSE_SHA1, "sha256":LICENSE_SHA256}
        and adapted == {"id":"android-sdk-license", "utf8Bytes":16960,
                        "sha1":OFFICIAL_LICENSE_SHA1, "sha256":OFFICIAL_LICENSE_SHA256})
    return {"approvedTermsAccepted":accepted,
        "acceptedRepresentation":legal.get("acceptedRepresentation"),
        "acceptedRecordSHA1":legal.get("acceptedRecordSHA1"),
        "compatibilityAliasBasis":LICENSE_ACCEPTANCE_BASIS,
        "approvedOriginal":original, "officialAdaptedIdentity":adapted,
        "originalBytesEqual":False, "approvedOriginalBytesAcceptedVerbatim":False}


def public_summary(state):
    return {"schema":"fighter-android-official-client-v1", "source":state["source"],
        "state":state["state"], "failureReason":state.get("failureReason"), "gates":state["gates"],
        "executed":state["executed"], "licenseAuthorization":state["licenseAuthorization"],
        "licenseAcceptance":state.get("licenseAcceptance", license_acceptance_summary()),
        "apk":state.get("apk"), "observationStopReason":state.get("observation",{}).get("stopReason"),
        "cachedCatalogFiles":len(state.get("cache",{}).get("files",[])), "d19FilesRecovered":0,
        "cleanup":state.get("cleanup"), "appleTests":0, "gameAssetsUploaded":0, "testFlightUploads":0,
        "doesNotProve":"D19 model/motion/equipment recovery, iOS rendering, hearing, performance or physical-device acceptance"}


def merge_sdk_progress(state):
    path = evidence()/"sdk-install-receipt.json"
    if not path.is_file() or path.stat().st_size > 2*MIB:
        return
    try:
        receipt = json.loads(path.read_text())
    except (ValueError, OSError):
        return
    state["sdkPartialReceipt"] = receipt
    # A failed later install cannot erase an observed official acceptance.
    # The compatibility gate explicitly refers to the official adapted bytes.
    state["licenseAcceptance"] = license_acceptance_summary(receipt)
    if state["licenseAcceptance"]["approvedTermsAccepted"]:
        state["gates"]["licenseAcceptedForExactText"] = True


def run():
    admit()
    need(not work().exists(), "once_only_work_directory_exists")
    work().mkdir(mode=0o700)
    evidence().mkdir(mode=0o700)
    state = {"source":{"sha":os.environ["GITHUB_SHA"], "runId":os.environ["GITHUB_RUN_ID"], "attempt":1,
        "helperSHA256":digest(ROOT/HELPER), "sdkHelperSHA256":digest(ROOT/SDK_HELPER),
        "workflowSHA256":digest(ROOT/WORKFLOW)}, "state":"running", "startedAt":now(),
        "licenseAuthorization":{"userApproved":True, "textSHA256":LICENSE_SHA256,
            "scope":"Emulator37.2.13/API30GoogleAPIsx86_64r16 plus one official19221 client launch; no other agreement"},
        "licenseAcceptance":license_acceptance_summary(),
        "executed":{"apkDownloads":0, "emulatorBoots":0, "apkInstalls":0, "apkLaunches":0},
        "gates":{key:False for key in ("prerequisitesReady", "licenseAcceptedForExactText", "sdkInstalled",
           "apkSignatureVerified", "kvmReady", "imageBooted", "apkABICompatible", "apkInstalled",
           "normalLaunchObserved", "readableBootstrapCatalogObtained")}}
    save_state(state)
    code = 1
    try:
        tools = tools_inventory(state)
        print("Existing tools and runner identity verified; installing the exact authorized SDK packages.", flush=True)
        sdk = importlib.import_module("fighter_android_sdk_install").install(work(), SYSTEM_SDK)
        state["sdk"] = sdk
        state["licenseAcceptance"] = license_acceptance_summary(sdk.get("receipt",{}))
        need(state["licenseAcceptance"]["approvedTermsAccepted"] is True
             and sdk.get("receipt",{}).get("licenseAcceptedForExactText") is True
             and sdk.get("receipt",{}).get("installedExactPackagesVerified") is True,
             "sdk_success_receipt_incomplete")
        state["gates"].update({"licenseAcceptedForExactText":True, "sdkInstalled":True})
        save_state(state)
        apk = download_apk_once(state)
        verify_apk(apk, tools, state)
        print("Official APK bytes, directory, manifest and signature verified; starting one owned device.", flush=True)
        prepare_kvm(tools, state)
        start_emulator(tools, sdk, state)
        launch(tools, apk, state)
        state["state"] = ("catalog_obtained_pending_private_decode" if state["gates"]["readableBootstrapCatalogObtained"]
                          else "launched_without_readable_catalog")
        if state.get("observation",{}).get("stopReason") not in (None, "bounded_observation_complete"):
            state["state"] = "blocked_after_launch"
        code = 0 if state["gates"]["readableBootstrapCatalogObtained"] else 1
    except Exception as error:
        state["state"] = "blocked"
        # SDK helper exceptions may contain paths/URLs; only its reviewed code
        # is promoted after explicit sanitization, never arbitrary stderr.
        reason = str(error) if isinstance(error, Blocked) else "phase_failed_"+type(error).__name__
        state["failureReason"] = reason if re.fullmatch(r"[A-Za-z0-9_.-]{1,160}", reason) else "private_phase_failure"
        write_json(evidence()/"failure-private.json", {"type":type(error).__name__, "detail":str(error)[:2000]})
    finally:
        merge_sdk_progress(state)
        cleanup = stop_owned(state)
        if cleanup["errors"]:
            code = 1
        state["endedAt"] = now()
        save_state(state)
        summary = public_summary(state)
        write_json(evidence()/"public-summary.json", summary)
        print(json.dumps(summary, ensure_ascii=True, indent=2), flush=True)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
                output.write("## One authorized official Android client observation\n\n```json\n"+
                             json.dumps(summary, indent=2)+"\n```\n")
    return code


def seal():
    admit()
    need(evidence().is_dir() and not (work()/"sealed.json").exists(), "evidence_missing_or_sealed")
    published = work()/"published"
    published.mkdir(mode=0o700, exist_ok=False)
    archive_path = work()/"private-evidence.zip"
    entries, total = [], 0
    try:
        with zipfile.ZipFile(archive_path, "x", compression=zipfile.ZIP_STORED) as output:
            for path in sorted(evidence().rglob("*")):
                info = path.lstat()
                need(not stat.S_ISLNK(info.st_mode), "evidence_symlink_forbidden")
                if stat.S_ISDIR(info.st_mode):
                    continue
                need(stat.S_ISREG(info.st_mode) and info.st_size <= 64*MIB, "evidence_member_bound")
                name = path.relative_to(evidence()).as_posix()
                total += info.st_size
                need(total <= 384*MIB and len(entries)<512, "evidence_aggregate_bound")
                output.write(path, name)
                entries.append({"file":name, "bytes":info.st_size, "sha256":digest(path), "tailOnly":False})
            output.writestr("private-evidence-inventory.json", json.dumps(entries, indent=2))
        key = secrets.token_bytes(32)
        wrapped = subprocess.run(["openssl", "pkeyutl", "-encrypt", "-pubin", "-inkey", str(ROOT/RECIPIENT),
            "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256"],
            input=key, capture_output=True, timeout=30, check=True).stdout
        (published/(STEM+".key.enc")).write_bytes(wrapped)
        os.environ["FIGHTER_LIU_MODEL_KEY"] = key.hex()
        try:
            importlib.import_module("fighter_private_model").seal_evidence_file(archive_path, published/(STEM+".enc"))
        finally:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
            key = b""
        (published/(STEM+".SHA256SUMS")).write_text("".join(digest(p)+"  "+p.name+"\n" for p in sorted(published.glob("*.enc"))))
        write_json(work()/"sealed.json", {"entries":len(entries), "plaintextBytes":total,
            "recipientSPKISHA256":RECIPIENT_SPKI, "sourceSHA":os.environ["GITHUB_SHA"]})
        print("Sealed bounded Android evidence once; no APK, SDK archive or key is published.")
    except BaseException:
        shutil.rmtree(published, ignore_errors=True)
        raise
    finally:
        archive_path.unlink(missing_ok=True)


def cleanup_private():
    admit()
    if not work().exists():
        return
    if (evidence()/"result.json").is_file():
        state = read_state()
        cleanup = state.get("cleanup", {})
        if not all(cleanup.get(k) for k in ("emulatorStopped", "adbStopped", "kvmRestored")):
            # One recovery of cleanup only, never another install or launch.
            cleanup = stop_owned(state)
        need(all(cleanup.get(k) for k in ("emulatorStopped", "adbStopped", "kvmRestored"))
             and not cleanup.get("errors"), "owned_cleanup_incomplete")
    # Keep bounded encrypted evidence and public summaries. Remove owned device,
    # SDK archives, APK and plaintext evidence only after confirmed sealing.
    need((work()/"sealed.json").is_file(), "private_cleanup_requires_sealed_evidence")
    for name in ("sdk", "downloads", "android-user", "avds", "evidence"):
        path = work()/name
        need(not path.is_symlink(), "private_cleanup_symlink")
        if path.exists():
            shutil.rmtree(path)
    print("Removed this run's private APK, SDK, AVD and plaintext evidence; ciphertext remains for collection.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("run", "seal", "cleanup"))
    args = parser.parse_args()
    if args.phase == "run":
        return run()
    {"seal":seal, "cleanup":cleanup_private}[args.phase]()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("Android evidence phase failed: "+type(error).__name__, file=sys.stderr)
        sys.exit(1)
