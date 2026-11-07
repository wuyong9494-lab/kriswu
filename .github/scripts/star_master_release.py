"""Pinned Master beta: require exact core/device, rules and native replay acceptance."""
import time
import asc_promote as promotion

MODE = "star-master-replay-verified-582"
IDENTITY = {"build_number": "582", "source_sha": "88c205049acbad9e1d20b79e7b5e41c8658103db", "source_run_id": 42345846863}
BRANCH = "codex/star-gameplay-master-20261107"
HEAD = "a5d15a2b97adb8c817387c8a0eca952346a2aee3"
PREVIOUS_SOURCE = "a62b36c29a56ad1efd4b38cc991843e7263284f2"
RULE_RUN = 42345846960
NATIVE_RUN = 42345846928
NOTE = "iPhone 17 Pro Max 模拟器复盘验证通过；真机手感与真人首局千分之一通过率尚未验证。既往竞技资源 Metal 渲染失败未复验，原资源包保持不变。"
NATIVE_STEPS = ("Prepare iPhone 17 Pro Max", "Render actual SwiftUI replay",
                "Pick to result, scrub replay, return to unchanged result", "Export screenshots",
                "Run actions/upload-artifact@v4")
CODE_FILES = {
    ".github/workflows/star-gameplay-rules.yml", ".github/workflows/star-master-native.yml",
    "App/Views/TileGameHome.swift", "App/Views/TileGameView.swift", "App/Views/TileReplayView.swift",
    "Package.swift", "Sources/ShiftCore/TileDailyAttempts.swift", "Sources/ShiftCore/TileMaster.swift",
    "Sources/ShiftCore/TilePlanning.swift", "Sources/ShiftCore/TileReplay.swift",
    "Tests/ArenaFlowTests/TileFlowTests.swift", "Tests/SiteTests/TileVisualTests.swift",
    "Tests/ShiftCoreTests/TileDailyAttemptsTests.swift", "Tests/ShiftCoreTests/TileDepthTests.swift",
    "Tests/ShiftCoreTests/TileMasterTests.swift", "Tests/ShiftCoreTests/TilePlanningTests.swift",
    "Tests/ShiftCoreTests/TileReplayTests.swift", "Tools/TileDailyAudit/main.swift",
}

class Pending(ValueError):
    pass


def validate_request(request):
    import arena_private_pack as pack
    if any(request.get(k) != v for k, v in IDENTITY.items()) or type(request.get("source_run_id")) is not int:
        raise ValueError("Master release identity mismatch")
    expected = {"mode": MODE, "rules_run_id": RULE_RUN, "native_run_id": NATIVE_RUN}
    if request.get("source_validation") != expected:
        raise ValueError("Master validation run identity mismatch")
    if request.get("private_resource_pack") != pack.JOURNEY_PACK or request.get("private_resource_pack_transport") != pack.JOURNEY_TRANSPORT:
        raise ValueError("Master beta must preserve the exact existing private pack")
    if NOTE not in request.get("notes", ""):
        raise ValueError("Master beta must disclose physical-device and private-rendering limitations")
    return expected


def validate_scope(files):
    if not isinstance(files, list) or not files or len(files) >= 300:
        raise ValueError("Master source comparison must be complete and nonempty")
    def permitted(path):
        return isinstance(path, str) and (path in CODE_FILES or path.startswith("docs/"))
    for item in files:
        if not permitted(item.get("filename")) or (item.get("previous_filename") and not permitted(item["previous_filename"])):
            raise ValueError("Master release unexpectedly changes an unrelated resource/runtime file")
        if item.get("status") not in ("added", "modified", "renamed"):
            raise ValueError("Unexpected Master source change type")


def validate_run(run, jobs, kind):
    run_id, path, names = {
        "source": (IDENTITY["source_run_id"], ".github/workflows/ios.yml", ("build", "core-tests-linux")),
        "rules": (RULE_RUN, ".github/workflows/star-gameplay-rules.yml", ("rules",)),
        "native": (NATIVE_RUN, ".github/workflows/star-master-native.yml", ("replay",)),
    }[kind]
    expected = {"id": run_id, "head_sha": IDENTITY["source_sha"], "head_branch": BRANCH,
                "event": "push", "path": path}
    if any(run.get(k) != v for k, v in expected.items()) or (kind == "source" and str(run.get("run_number")) != IDENTITY["build_number"]):
        raise ValueError("Master CI identity mismatch")
    if run.get("status") in ("queued", "in_progress", "pending", "waiting", "requested"):
        raise Pending("Exact Master acceptance is still running")
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        raise ValueError("Master acceptance did not pass: " + kind)
    for name in names:
        found = [j for j in jobs if j.get("name") == name]
        if len(found) != 1 or found[0].get("status") != "completed" or found[0].get("conclusion") != "success":
            raise ValueError("Master required job did not pass: " + name)
        if kind == "native":
            for step in NATIVE_STEPS:
                matching = [s for s in found[0].get("steps", []) if s.get("name") == step]
                if len(matching) != 1 or matching[0].get("status") != "completed" or matching[0].get("conclusion") != "success":
                    raise ValueError("Master native step did not pass: " + step)
    if any(j.get("status") != "completed" or j.get("conclusion") not in ("success", "skipped") for j in jobs):
        raise ValueError("Master CI has unfinished or failed jobs")


def check(request, wait=False):
    validate_request(request)
    deadline = time.monotonic() + 80 * 60
    while True:
        head = promotion.github("/git/ref/heads/" + BRANCH).get("object", {}).get("sha")
        if head != HEAD:
            raise ValueError("Master source branch superseded")
        try:
            for kind, run_id in (("source", IDENTITY["source_run_id"]), ("rules", RULE_RUN), ("native", NATIVE_RUN)):
                validate_run(promotion.github(f"/actions/runs/{run_id}"),
                             promotion.github(f"/actions/runs/{run_id}/jobs?filter=latest&per_page=100")["jobs"], kind)
            validate_scope(promotion.github("/compare/" + PREVIOUS_SOURCE + "..." + IDENTITY["source_sha"]).get("files"))
            return {"validation_mode": MODE, "source_ci_conclusion": "success", "rules_run_id": RULE_RUN,
                    "native_run_id": NATIVE_RUN, "tile_native_and_ui_validation": "success",
                    "physical_device_validation": "pending", "human_win_rate": "unmeasured",
                    "private_resource_rendering": "unchanged-prior-deferral", "source_branch_head": head}
        except Pending:
            if not wait or time.monotonic() >= deadline:
                raise
            print("Waiting for exact Master device/core/rules/native acceptance; no upload yet", flush=True)
            time.sleep(30)
