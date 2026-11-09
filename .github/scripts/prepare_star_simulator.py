#!/usr/bin/env python3
"""Prepare a disposable exact-model simulator after the core compiler exits."""
import json
from pathlib import Path
import re
import struct
import subprocess
import time
import zlib

MODEL = "iPhone 17 Pro Max"
STATUS = Path("star-simulator-preparation.json")


def selection(catalog):
    models = [item for item in catalog.get("devicetypes", []) if item.get("name") == MODEL]
    runtimes = [item for item in catalog.get("runtimes", [])
                if ".iOS-" in item.get("identifier", "") and item.get("isAvailable") is True
                and int(item.get("version", "0").split(".")[0]) >= 26]
    if len(models) != 1 or not runtimes:
        raise ValueError("The exact iPhone 17 Pro Max model and an available iOS 26+ runtime are required")
    runtime = max(runtimes, key=lambda item: tuple(map(int, re.findall(r"\d+", item["version"]))))
    return models[0]["identifier"], runtime["identifier"]


def write_json(path, value):
    temporary = path.with_suffix(".partial")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def prepare():
    try:
        # The first query also starts CoreSimulatorService. The Intel image's
        # cold service exceeded 60 seconds; retain one bounded initialization
        # retry rather than treating an empty or timed-out catalog as ready.
        for attempt in range(2):
            try:
                started = time.monotonic()
                print("Reading available simulator runtimes (attempt", attempt + 1, ")", flush=True)
                catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"], timeout=180))
                print("Simulator catalog ready after", round(time.monotonic() - started, 1), "seconds", flush=True)
                break
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
                if attempt == 1:
                    raise
                print("CoreSimulator catalog initialization will be retried once", flush=True)
        model, runtime = selection(catalog)
        device = subprocess.check_output(["xcrun", "simctl", "create", "Star Journey Acceptance",
                                          model, runtime], text=True, timeout=60).strip()
        if not re.fullmatch(r"[A-Fa-f0-9-]{36}", device):
            raise ValueError("simctl did not return a simulator UUID")
        metadata = {"runtime": runtime, "name": MODEL, "udid": device}
        write_json(Path("star-test-device.json"), metadata)
        print("Starting isolated simulator:", device, runtime, flush=True)
        subprocess.run(["xcrun", "simctl", "boot", device], check=True, timeout=120)
        write_json(STATUS, {"prepared": True, "udid": device})
    except Exception as error:
        write_json(STATUS, {"prepared": False, "error": str(error)})
        raise


def valid_png(data):
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return False
    offset, dimensions, pixels = 8, None, False
    while offset + 12 <= len(data):
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + size + 12
        if end > len(data):
            return False
        kind, payload = data[offset + 4:offset + 8], data[offset + 8:end - 4]
        if zlib.crc32(kind + payload) & 0xffffffff != struct.unpack(">I", data[end - 4:end])[0]:
            return False
        if kind == b"IHDR":
            if dimensions is not None or size != 13:
                return False
            dimensions = struct.unpack(">II", payload[:8])
            if min(dimensions) <= 0:
                return False
        elif kind == b"IDAT":
            if dimensions is None or not payload:
                return False
            pixels = True
        elif kind == b"IEND":
            return size == 0 and end == len(data) and dimensions is not None and pixels
        offset = end
    return False


def capture_ready(device, destination=Path("star-simulator-ready.png")):
    # CoreSimulator reports Finished before its first framebuffer is responsive.
    # A failed or partial capture is never accepted as a healthy display.
    command = ["xcrun", "simctl", "io", device, "screenshot", "--type=png", str(destination)]
    for attempt in range(3):
        destination.unlink(missing_ok=True)
        try:
            subprocess.run(command, check=True, timeout=45)
            if not destination.is_file() or not valid_png(destination.read_bytes()):
                raise ValueError("Simulator returned an incomplete screenshot")
            print("Simulator display ready; complete PNG captured", flush=True)
            return
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError) as error:
            destination.unlink(missing_ok=True)
            print("Display capture attempt", attempt + 1, "failed:", error, flush=True)
            if attempt == 2:
                raise RuntimeError("Simulator display did not become ready; native acceptance is blocked") from error
            time.sleep(2)


def wait_for_boot(device, retry_cold_boot=False):
    command = ["xcrun", "simctl", "bootstatus", device, "-b"]
    try:
        subprocess.run(command, check=True, timeout=240)
    except subprocess.TimeoutExpired:
        if not retry_cold_boot:
            raise
        # Cold hosted runners sometimes still initialize SpringBoard after the
        # first bounded wait. Inspect this exact device, then allow ONE further
        # wait instead of rebuilding every native test bundle on another runner.
        catalog = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "-j"], timeout=30))
        matches = [item for devices in catalog.get("devices", {}).values()
                   for item in devices if item.get("udid") == device]
        if (len(matches) != 1 or matches[0].get("isAvailable") is not True
                or matches[0].get("state") not in ("Booted", "Booting")):
            raise RuntimeError("Target simulator is not still booting; native acceptance is blocked")
        print("Target simulator is still initializing; allowing one additional 180-second boot wait", flush=True)
        subprocess.run(command, check=True, timeout=180)


def wait_ready(retry_cold_boot=False):
    prepared = json.loads(STATUS.read_text())
    if prepared.get("prepared") is not True:
        raise ValueError("Simulator preparation did not succeed")
    device = json.loads(Path("star-test-device.json").read_text())
    if device.get("name") != MODEL or device.get("udid") != prepared.get("udid"):
        raise ValueError("Prepared simulator identity differs from the target device")
    wait_for_boot(device["udid"], retry_cold_boot=retry_cold_boot)
    capture_ready(device["udid"])


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready", action="store_true")
    parser.add_argument("--retry-cold-boot", action="store_true",
                        help="Allow one additional bounded wait; requires a 20-minute combined preparation budget")
    args = parser.parse_args()
    if args.retry_cold_boot and not args.ready:
        parser.error("--retry-cold-boot requires --ready")
    wait_ready(retry_cold_boot=args.retry_cold_boot) if args.ready else prepare()
