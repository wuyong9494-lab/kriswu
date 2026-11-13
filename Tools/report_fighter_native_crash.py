"""Bounded symbol-only diagnostics for this unsigned synthetic CI host.

Do not publish full crash reports, application state, registers or process
environment. This workflow never stages private fighter resources.
"""
import argparse
import json
from pathlib import Path


def summarize(path):
    raw = path.read_text(errors="replace")
    if len(raw) > 16_000_000:
        return None
    # Apple .ips files have one metadata JSON line before the report object.
    try:
        report = json.loads(raw)
    except json.JSONDecodeError:
        _, _, tail = raw.partition("\n")
        report = json.loads(tail)
    if report.get("procName") != "ShiftReminder":
        return None
    threads = report.get("threads", [])
    fault = report.get("faultingThread")
    crashed = next((t for t in threads if t.get("triggered")), None)
    if crashed is None and type(fault) is int and 0 <= fault < len(threads):
        crashed = threads[fault]
    frames = (crashed or {}).get("frames", [])[:24]
    return {
        "exception": {k: report.get("exception", {}).get(k) for k in ("type", "signal", "subtype")},
        "termination": {k: report.get("termination", {}).get(k) for k in ("namespace", "code", "indicator")},
        "faultingSymbols": [{"symbol": f.get("symbol"), "offset": f.get("symbolLocation")} for f in frames],
        "frameCount": len((crashed or {}).get("frames", [])),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--since", type=float, required=True)
    args = parser.parse_args()
    directory = Path.home() / "Library/Logs/DiagnosticReports"
    found = 0
    for path in sorted(directory.glob("ShiftReminder*.ips"))[-10:]:
        if path.is_symlink() or path.stat().st_mtime < args.since:
            continue
        try:
            result = summarize(path)
            if result:
                print(json.dumps(result)); found += 1
        except (OSError, ValueError, TypeError, AttributeError):
            print("Current host crash summary could not be parsed.")
    if found == 0:
        print("No current ShiftReminder .ips report was available; no crash cause is inferred.")
