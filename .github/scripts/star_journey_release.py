#!/usr/bin/env python3
"""Record the owner's direct beta upload without representing failed visuals as passed."""
import argparse
import json
import os
from pathlib import Path

import arena_private_pack as private_pack

KNOWN_VALIDATION_NOTE = "已知验证结果：完整 UI 回归 8 项中 7 项失败；竞技资源 Metal 渲染 2 项中 1 项失败。本版按要求直接上传内测，相关验收延期，不代表通过。"


def visual_policy(request):
    validation = private_pack.validation_specification(request)
    if validation and validation["mode"] == "star-master-replay-verified-582":
        import star_master_release as master
        return {"deferred": True, "passed": False, "source_sha": request["source_sha"],
                "build_number": request["build_number"], "private_resource_pack": private_pack.JOURNEY_PACK,
                "validation": "unchanged-private-resources-prior-deferral-retained",
                "tile_native_and_ui_validation": "success", "note": master.NOTE}
    if validation and validation["mode"] == "star-pulse-direct-upload-569":
        return {"deferred": True, "passed": False, "source_sha": request["source_sha"],
                "build_number": request["build_number"], "validation": "deferred-by-owner-for-direct-beta-upload",
                "note": "Pulse native interactions remain unverified; prior private Metal failure remains unverified. Archive integrity checks remain mandatory."}
    if not validation or validation["mode"] != private_pack.JOURNEY_DIRECT_MODE:
        return {"deferred": False}
    if KNOWN_VALIDATION_NOTE not in request.get("notes", ""):
        raise ValueError("Direct beta notes must disclose the observed native validation failures")
    return {
        "deferred": True,
        "passed": False,
        "validation": "deferred-by-owner-for-direct-beta-upload",
        "source_sha": request["source_sha"],
        "build_number": request["build_number"],
        "private_resource_pack": private_pack.JOURNEY_PACK,
        "previous_actual_result": {
            "run_id": 42228071190,
            "job_id": 127936581405,
            "control_sha": "f6c59a5a05ca403f299a2dcaeed9a4c1169e29fa",
            "artifact_id": 13510601200,
            "artifact_sha256": "1c8c3f45b28ffd33b9c4e7955b65b946c2524f79b9ebb559f9088fb870233ffe",
            "device": "iPhone 17 Pro Max",
            "totalTestCount": 2,
            "passedTests": 1,
            "failedTests": 1,
            "skippedTests": 0,
        },
        "note": "This is the prior observed result, not a new test run or successful acceptance. Exact pack integrity and signed archive checks remain mandatory.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request", type=Path)
    args = parser.parse_args()
    policy = visual_policy(json.loads(args.request.read_text()))
    if policy["deferred"]:
        Path("promotion-private-rendering.json").write_text(json.dumps(policy, ensure_ascii=False, indent=2) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("deferred=" + str(policy["deferred"]).lower() + "\n")
    print(json.dumps(policy, ensure_ascii=False))


if __name__ == "__main__":
    main()
