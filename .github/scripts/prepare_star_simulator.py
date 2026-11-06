#!/usr/bin/env python3
"""Prepare a disposable exact-model simulator after the core compiler exits."""
import json
from pathlib import Path
import re
import subprocess
import time

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


if __name__ == "__main__":
    prepare()
