"""Exact Build 569 direct beta; compilation, rules and archive integrity remain required."""
import time
import asc_promote as promotion

MODE = "star-pulse-direct-upload-569"
IDENTITY = {"build_number": "569", "source_sha": "a62b36c29a56ad1efd4b38cc991843e7263284f2", "source_run_id": 42329690668}
BRANCH = "codex/star-gameplay-pulse-20261107"
HEAD = "a6b942225ff721779a97bb1323ec1618fca7b6e0"  # source plus validation documentation only
RULE_RUN = 42329690554
NOTE = "本版按要求直接上传内测；脉冲原生交互与真机体验尚未完成验收。既往竞技资源 Metal 渲染失败尚未复验，不代表通过。"

class Pending(ValueError):
    pass


def validate_request(request):
    import arena_private_pack as pack
    if any(request.get(k) != v for k, v in IDENTITY.items()) or type(request.get("source_run_id")) is not int:
        raise ValueError("Pulse release identity mismatch")
    if request.get("source_validation") != {"mode": MODE, "rules_run_id": RULE_RUN}:
        raise ValueError("Pulse rules run identity mismatch")
    if request.get("private_resource_pack") != pack.JOURNEY_PACK or request.get("private_resource_pack_transport") != pack.JOURNEY_TRANSPORT:
        raise ValueError("Pulse release must preserve exact private pack")
    if NOTE not in request.get("notes", ""):
        raise ValueError("Pulse beta requires explicit incomplete acceptance disclosure")
    return request["source_validation"]


def validate_run(run, jobs, rule=False):
    expected = {"id": RULE_RUN if rule else IDENTITY["source_run_id"], "head_sha": IDENTITY["source_sha"],
                "head_branch": BRANCH, "event": "push", "path": ".github/workflows/star-gameplay-rules.yml" if rule else ".github/workflows/ios.yml"}
    if any(run.get(k) != v for k, v in expected.items()) or (not rule and str(run.get("run_number")) != "569"):
        raise ValueError("Pulse CI identity mismatch")
    if run.get("status") in ("queued", "in_progress", "pending", "waiting", "requested"):
        raise Pending("Exact Pulse source is still building")
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        raise ValueError("Pulse source CI did not pass")
    for name in (("rules",) if rule else ("build", "core-tests-linux")):
        found = [j for j in jobs if j.get("name") == name]
        if len(found) != 1 or found[0].get("status") != "completed" or found[0].get("conclusion") != "success":
            raise ValueError("Pulse required job did not pass: " + name)
    if any(j.get("status") != "completed" or j.get("conclusion") not in ("success", "skipped") for j in jobs):
        raise ValueError("Pulse CI has failed or unfinished jobs")


def check(request, wait=False):
    validate_request(request)
    deadline = time.monotonic() + 80 * 60
    while True:
        head = promotion.github("/git/ref/heads/" + BRANCH).get("object", {}).get("sha")
        if head != HEAD:
            raise ValueError("Pulse source branch superseded")
        try:
            for rule, run_id in ((False, IDENTITY["source_run_id"]), (True, RULE_RUN)):
                validate_run(promotion.github(f"/actions/runs/{run_id}"),
                             promotion.github(f"/actions/runs/{run_id}/jobs?filter=latest&per_page=100")["jobs"], rule)
            return {"validation_mode": MODE, "source_ci_conclusion": "success", "rules_run_id": RULE_RUN,
                    "rules_conclusion": "success", "tile_native_and_ui_validation": "deferred-by-owner",
                    "physical_device_validation": "pending", "source_branch_head": head}
        except Pending:
            if not wait or time.monotonic() >= deadline:
                raise
            print("Waiting for exact Build 569 device/core acceptance; no upload yet", flush=True)
            time.sleep(30)
