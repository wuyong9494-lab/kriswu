#!/usr/bin/env python3
"""One bounded real-resource native probe. Never publish clear assets or evidence.

Existing resource envelopes/keys are unchanged. Only newly produced evidence is
sealed with a fresh random key, wrapped to both the existing recipient and the
public recipient pinned for this inspection. No signing, release or network API.
"""
import argparse
import collections
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time
import zipfile

import fighter_private_model as envelope
from fighter_recover_screenshots import PUBLIC_KEY as EXISTING_RECIPIENT

ROOT = Path(__file__).resolve().parents[2]
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
RECIPIENT = ROOT / ".github/public/fighter-visual-20261113.public.pem"
RECIPIENT_SPKI_SHA256 = "508ef86dfe26664669bcf566b5502fe0d3273961160f1c9388f8cd2e715dc22a"
MANIFESTS = [".github/private/sf3/manifest.json", ".github/private/sf3-distinct/manifest.json"]
BASELINE_SELECTED = [
    ("DuelWeaponAssetTests", "testPersonalHeadFollowsBodyFacingAndSourceNeckAnimation", "actual-model hierarchy assertions"),
    ("DuelWeaponAssetTests", "testRenderBothDistinctSourceBodiesWeaponsAndPersonalHeads", "actual models; fixed neutral orthographic test scene"),
    ("DuelSourceEffectsTests", "testActualHitAndBlockRenderFreezePauseAndRelease", "authenticated textures; synthetic contact events and test camera"),
    ("DuelWeaponEffectsTests", "testSourceWeaponTrailsRenderAtRealEndpointsAndFreezeAndRelease", "authenticated textures; synthetic endpoint poses and test camera"),
    ("DuelWeaponGameplayTests", "testActualSourceWeaponHeavyAndKickHitInBothDirectionsWithoutCrossingBodies", "actual resource catalog; authoritative combat assertions"),
    ("DuelWeaponGameplayTests", "testEquippedSessionsShowRealHitsPauseRestartAndReleaseTheirScenes", "actual fighters, stage, gameplay contacts and production world/camera"),
    ("DuelShadowPresentationTests", "testRealHammerTravelsBothWaysAndRestoresWithoutAccumulatingOrReplacingMesh", "actual source skinned weapon; authoritative provisional shadow geometry"),
    ("DuelShadowPresentationTests", "testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails", "actual source textures; authoritative provisional shadow poses"),
    ("DuelWeaponGameplayTests", "testRealOpticalFitRetainsLensOnInvalidSkinAndRecovers", "actual resources and production camera; artificial skin-failure injection"),
    ("DuelShadowPresentationTests", "testRealShadowReleaseAndCatchBoundariesRenderForBothFacings", "actual source models and authoritative shadow ticks; fixed test renderer"),
    ("DuelWeaponAssetTests", "testEmptyOrPartialSkinEnvelopeCannotClaimSuccessfulOpticalFit", "native optical-fit validation; synthetic empty/partial/complete skin envelopes; no image"),
]
BASELINE_IMAGE_LABELS = (
    ["distinct-source-render-" + role for role in ("idle", "weapon1", "heavy", "kick")]
    + ["source-hit-first-simulation-step", "source-hit-original-six-layers", "source-block-original-nine-layers"]
    + ["source-katana-first-active-step", "source-katana-original-material", "source-double-hammer-original-material",
       "source-katana-dash-two-materials", "source-hammer-smooth-trail-material"]
    + [f"equipped-{hero}-{role}-source-contact" for hero in ("ember", "liu") for role in ("weapon1", "heavy", "kick")]
    + [f"shadow-boundary-liu-facing-{facing}-tick-{tick}" for facing in ("positive", "negative") for tick in (23, 24, 71, 72)]
)
BASELINE_DATA_LABELS = ["shadow-boundary-liu-world-evidence", "real-optical-fit-failure-recovery-ember", "real-optical-fit-failure-recovery-liu"]

# Closed, source-controlled scopes. No caller-provided XCTest selectors or
# attachment names are accepted, and the original eleven-method capture remains
# distinct from a targeted follow-up of the material/lifecycle repairs.
FOLLOWUP_SELECTED = [
    ("DuelShadowPresentationTests", "testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails", "actual source textures; per-slot current owner and retired-strip lifetime assertions"),
    ("DuelWeaponTrailContinuityTests", "testActiveTeleportStartsAnUnbridgedStripAndNextValidStepResumes", "synthetic endpoint discontinuity; exact source-lifetime expiry; no image"),
    ("DuelWeaponEffectsTests", "testOrdinaryRibbonsUseSourceAlphaWithoutMeshAtlasAndPreserveAge", "authenticated source alpha; endpoint-ribbon adapter and age/UV assertions; not original skinned trail mesh"),
    ("DuelWeaponGameplayTests", "testOrdinaryRibbonAdapterContributesToRealSourceContacts", "actual source fighters and production world/camera; ordinary weapon/heavy contacts; ribbon-only pixel contribution"),
]
FOLLOWUP_ATTACHMENTS = {
    label: {"selector": "SiteTests/DuelWeaponEffectsTests/testOrdinaryRibbonsUseSourceAlphaWithoutMeshAtlasAndPreserveAge", "kind": "image"}
    for label in ("ribbon-katana-first-active-step", "ribbon-katana-source-alpha", "ribbon-double-hammer-source-alpha")
}
FOLLOWUP_ATTACHMENTS.update({
    f"ribbon-equipped-{hero}-{role}-source-contact": {
        "selector": "SiteTests/DuelWeaponGameplayTests/testOrdinaryRibbonAdapterContributesToRealSourceContacts", "kind": "image"
    }
    for hero in ("ember", "liu") for role in ("weapon1", "heavy")
})
PRESENTATION_SELECTED = [
    ("DuelPresentationAssetsTests", "testActualMasksAndEnvironmentMatcapsRenderWithoutChangingSkeletons", "actual masks/MatCap and both unchanged skeletons; fixed test camera; not original renderer equivalence"),
    ("DuelPresentationAssetsTests", "testCalloutDecodesAndFollowsOneActionThroughPauseCancellationAndRestart", "actual mastered WAV decoding; injected playback lifecycle assertions; not audible device acceptance"),
    ("DuelPresentationAssetsTests", "testAlteredMaskAndVoiceAreRejectedBeforeRenderingOrPlayback", "actual pack mutation rejection; no silent fallback"),
    ("DuelWeaponGameplayTests", "testEquippedSessionsShowRealHitsPauseRestartAndReleaseTheirScenes", "actual fighters and production camera; new material composition and source contact effects"),
    ("DuelWeaponGameplayTests", "testOrdinaryRibbonAdapterContributesToRealSourceContacts", "actual fighters and production camera; ordinary weapon/heavy ribbon contribution"),
    ("DuelWeaponGameplayTests", "testRealOpticalFitRetainsLensOnInvalidSkinAndRecovers", "actual resources and production camera; changed near framing plus artificial skin failure"),
]
PRESENTATION_ATTACHMENTS = {
    "fidelity-materials-" + environment: {"selector": "SiteTests/DuelPresentationAssetsTests/testActualMasksAndEnvironmentMatcapsRenderWithoutChangingSkeletons", "kind": "image"}
    for environment in ("palace", "autumn")
}
PRESENTATION_ATTACHMENTS.update({
    f"equipped-{hero}-{role}-source-contact": {"selector": "SiteTests/DuelWeaponGameplayTests/testEquippedSessionsShowRealHitsPauseRestartAndReleaseTheirScenes", "kind": "image"}
    for hero in ("ember", "liu") for role in ("weapon1", "heavy", "kick")
})
PRESENTATION_ATTACHMENTS.update({
    f"ribbon-equipped-{hero}-{role}-source-contact": {"selector": "SiteTests/DuelWeaponGameplayTests/testOrdinaryRibbonAdapterContributesToRealSourceContacts", "kind": "image"}
    for hero in ("ember", "liu") for role in ("weapon1", "heavy")
})
PRESENTATION_ATTACHMENTS.update({
    "real-optical-fit-failure-recovery-" + hero: {"selector": "SiteTests/DuelWeaponGameplayTests/testRealOpticalFitRetainsLensOnInvalidSkinAndRecovers", "kind": "data"}
    for hero in ("ember", "liu")
})
SOURCE_SKIN_SELECTED = [
    ("DuelSourceWeaponTrailTests", "testOriginalSkinBindingsRenderBothFacingsAndRemainFrozen", "authenticated original four-bone skins, existing source tracks, both facings; fixed test camera"),
    ("DuelWeaponGameplayTests", "testSourceSkinsContributeToRealSourceContactsAndRelease", "actual fighters and production contacts/camera; no duplicate ordinary history ribbon; pause/release"),
]
SOURCE_SKIN_ATTACHMENTS = {
    f"source-skin-{hero}-{role}-{facing}": {"selector": "SiteTests/DuelSourceWeaponTrailTests/testOriginalSkinBindingsRenderBothFacingsAndRemainFrozen", "kind": "image"}
    for hero in ("ember", "liu") for role in ("weapon1", "heavy") for facing in ("positive", "negative")
}
SOURCE_SKIN_ATTACHMENTS.update({
    f"skin-equipped-{hero}-{role}-source-contact": {"selector": "SiteTests/DuelWeaponGameplayTests/testSourceSkinsContributeToRealSourceContactsAndRelease", "kind": "image"}
    for hero in ("ember", "liu") for role in ("weapon1", "heavy")
})
PLAYABILITY_SELECTED = [
    ("DuelSourceControlsTests", "testBackStickRoutesHoldReleaseAndNeverCapturesCenter", "actual UIKit direction routing and shared physical-input adapter; no separate defense button"),
    ("DuelSourceControlsTests", "testAccessibilityDefenseCancelsOnPauseRotationAndShutdown", "VoiceOver shortcut lifetime without an on-screen defense button"),
    ("DuelSourceControlsTests", "testActualSourceSpritesLoadRenderAndRejectDecodableTampering", "authenticated source control sprites and actual UIKit rendering"),
    ("DuelWeaponGameplayTests", "testOriginalBackGuardReleasesAcrossPauseRestartAndControlReplacement", "actual equipment; local session control replacement and pause/restart"),
    ("DuelWeaponGameplayTests", "testLiuCanRefillAndCastShadowAgainBeforeKnockout", "actual source attacks; first shadow, recharge, cooldown and second Liu shadow in one fight"),
    ("DuelLifecycleTests", "testExternalBackGuardUsesLocalSeatAndPreservesAuthoritativeState", "host/guest seat-relative input; no local mutation of authoritative state"),
    ("DuelWeaponAssetTests", "testRealSourceIdleVerticesRemainAboveRailThroughRotationAndHeroSwitch", "actual body, head and weapon vertices; 72 hero/rotation/idle samples; larger-default comparison"),
    ("DuelWeaponAssetTests", "testRealNavigatedLobbyUsesExactStageCenterAndRailGeometry", "actual SwiftUI navigation, menus and larger fighter framing"),
]
PLAYABILITY_SELECTED += [
    ("DuelShadowPresentationTests", "testHostedControlsObserveShadowCostCooldownAndRestartForBothFighters", "actual resources; automatic refill and second physical pointer shadow press"),
    ("DuelLifecycleTests", "testTelevisionRenderBudgetCaps4KAndRestoresPhoneScale", "4K/1080p/portrait/phone render budget"),
    ("DuelLifecycleTests", "testTelevisionTransferPreservesSceneAndAuthoritativeState", "same renderer, clock and authoritative state"),
    ("DuelLifecycleTests", "testTelevisionDisconnectReturnsExistingRendererToPhone", "disconnect restoration"),
    ("DuelLifecycleTests", "testTelevisionTransferRearmsHeldControllerOnlyAfterNeutral", "controller transfer lifecycle"),
    ("DuelLifecycleTests", "testTelevisionRepeatedRoutingDoesNotRepeatedlyCancelPhoneControls", "routing stability"),
]
PLAYABILITY_ATTACHMENTS = {
    "source-native-controls-four-actions-back-defense-eight-directions": {
        "selector": "SiteTests/DuelSourceControlsTests/testActualSourceSpritesLoadRenderAndRejectDecodableTampering", "kind": "image"},
    "lobby-larger-navigated": {
        "selector": "SiteTests/DuelWeaponAssetTests/testRealNavigatedLobbyUsesExactStageCenterAndRailGeometry", "kind": "image"},
}
PLAYABILITY_ATTACHMENTS.update({
    f"lobby-{size}-{hero}": {
        "selector": "SiteTests/DuelWeaponAssetTests/testRealSourceIdleVerticesRemainAboveRailThroughRotationAndHeroSwitch", "kind": "image"}
    for size in ("larger", "previous-size") for hero in ("ember", "liu")
})
IMPACT_POOL_ATTACHMENTS = {
    label: {"selector": "SiteTests/DuelSourceEffectsTests/testActualHitAndBlockRenderFreezePauseAndRelease", "kind": "image"}
    for label in ("source-hit-first-simulation-step", "source-hit-original-six-layers", "source-block-original-nine-layers")
}
SCOPES = {
    "impact-pool": {
        "selected": [BASELINE_SELECTED[2],
            ("DuelSourceEffectsTests", "testPrewarmedImpactPoolReusesObjectsAndClearsRetiredState", "bounded repeated contacts; object identity, signed scale and release"),
            ("DuelLifecycleTests", "testNetworkEffectPreparationHasStableTemplatesAndNoRuntimeSideEffects", "prewarm identity and reset lifecycle"),
            ("DuelLifecycleTests", "testNetworkEffectRuntimeCopiesKeepPreparedMaterialUniformsIndependent", "isolated slot uniforms and weapon materials")],
        "methodCount": 4, "imageLabels": list(IMPACT_POOL_ATTACHMENTS), "dataLabels": [],
        "commitPrefix": "Capture fighter impact pool",
        "workflow": ".github/workflows/fighter-impact-pool.yml",
        "additionalSources": ["App/Services/DuelSourceEffects.swift", "Tests/SiteTests/DuelLifecycleTests+NetworkPreparation.swift"],
    },
    "playability-followup": {
        "selected": PLAYABILITY_SELECTED, "methodCount": 14,
        "imageLabels": list(PLAYABILITY_ATTACHMENTS), "dataLabels": [],
        "commitPrefix": "Capture fighter back guard and lobby",
        "workflow": ".github/workflows/fighter-playability-followup.yml",
        "additionalSources": ["App/Views/DuelWorld.swift", "App/Views/DuelTelevision.swift", "Tests/SiteTests/DuelLifecycleTests+Television.swift", "App/Views/DuelSourceControls.swift", "App/Views/DuelView.swift",
                              "App/Views/DuelLobbyPreview.swift", "App/Views/DuelHomeView.swift",
                              "Sources/ShiftCore/DuelWeaponInput.swift", "Sources/ShiftCore/DuelWeaponFight.swift",
                              "Sources/ShiftCore/DuelReplayState.swift", "Sources/ShiftCore/DuelLobbyFraming.swift",
                              "App/Services/DuelSourceWeaponTrails.swift", "App/Services/DuelWeaponAssets.swift",
                              "App/Services/DuelPresentationAssets.swift", "App/Services/GLTFModel.swift",
                              ".github/scripts/fighter_presentation_assets.py", ".github/scripts/fighter_source_trails.py"],
    },
    "source-skins-followup": {
        "selected": SOURCE_SKIN_SELECTED, "methodCount": 2,
        "imageLabels": list(SOURCE_SKIN_ATTACHMENTS), "dataLabels": [],
        "commitPrefix": "Capture source fighter skins",
        "workflow": ".github/workflows/fighter-source-skins-followup.yml",
        "additionalSources": ["App/Services/DuelSourceWeaponTrails.swift", "App/Services/DuelWeaponAssets.swift",
                              "App/Services/DuelWeaponEffects.swift", "App/Services/DuelNetworkCompatibilityIdentity.swift",
                              "App/Services/GLTFModel.swift", "App/Views/DuelWorld.swift",
                              ".github/scripts/fighter_presentation_assets.py", ".github/scripts/fighter_source_trails.py",
                              ".github/scripts/export_fighter_source_trails.py"],
    },
    "coverage-followup": {
        "selected": FOLLOWUP_SELECTED[2:], "methodCount": 2,
        "imageLabels": list(FOLLOWUP_ATTACHMENTS), "dataLabels": [],
        "commitPrefix": "Capture targeted fighter coverage",
        "workflow": ".github/workflows/fighter-coverage-followup.yml",
        "additionalSources": ["App/Services/DuelWeaponEffects.swift", "App/Services/DuelPresentationAssets.swift",
                              "App/Services/DuelWeaponAssets.swift", "App/Services/DuelSourceEffects.swift",
                              "App/Services/GLTFModel.swift", "App/Views/DuelWorld.swift",
                              ".github/scripts/fighter_presentation_assets.py"],
    },
    "baseline-11": {
        "selected": BASELINE_SELECTED, "methodCount": 11,
        "imageLabels": BASELINE_IMAGE_LABELS, "dataLabels": BASELINE_DATA_LABELS,
        "commitPrefix": "Capture current fighter visual acceptance",
        "workflow": ".github/workflows/fighter-visual-acceptance.yml", "additionalSources": [],
    },
    "trail-followup": {
        "selected": FOLLOWUP_SELECTED, "methodCount": 4,
        "imageLabels": [label for label, row in FOLLOWUP_ATTACHMENTS.items() if row["kind"] == "image"],
        "dataLabels": [label for label, row in FOLLOWUP_ATTACHMENTS.items() if row["kind"] == "data"],
        "commitPrefix": "Capture targeted fighter trail followup",
        "workflow": ".github/workflows/fighter-visual-followup.yml",
        "additionalSources": ["App/Services/DuelWeaponEffects.swift", "App/Services/DuelWeaponAssets.swift",
                              "App/Services/DuelSourceEffects.swift", "App/Services/GLTFModel.swift",
                              "App/Services/DuelDisplayedSkinBounds.swift", "App/Services/DuelStage.swift",
                              "App/Views/DuelWorld.swift", "App/Views/DuelView.swift"],
    },
    "presentation-followup": {
        "selected": PRESENTATION_SELECTED, "methodCount": 6,
        "imageLabels": [label for label, row in PRESENTATION_ATTACHMENTS.items() if row["kind"] == "image"],
        "dataLabels": [label for label, row in PRESENTATION_ATTACHMENTS.items() if row["kind"] == "data"],
        "commitPrefix": "Capture targeted fighter presentation",
        "workflow": ".github/workflows/fighter-presentation-followup.yml",
        "additionalSources": ["App/Services/DuelPresentationAssets.swift", "App/Services/DuelWeaponAssets.swift",
                              "App/Services/DuelSourceEffects.swift", "App/Services/GLTFModel.swift",
                              "App/Views/DuelWorld.swift", "App/Views/DuelLobbyPreview.swift",
                              ".github/scripts/fighter_presentation_assets.py"],
    },
}

SCOPES["impact-pool-lifecycle"] = {
    "selected": [SCOPES["impact-pool"]["selected"][1]], "methodCount": 1,
    "imageLabels": [], "dataLabels": [],
    "commitPrefix": "Verify fighter impact pool lifecycle",
    "workflow": ".github/workflows/fighter-impact-pool-lifecycle.yml",
    "additionalSources": ["App/Services/DuelSourceEffects.swift"],
}

def scope_settings(name):
    if name not in SCOPES:
        raise ValueError("Unknown bounded visual scope")
    return SCOPES[name]


SCOPE_NAME = os.environ.get("FIGHTER_VISUAL_SCOPE", "baseline-11")
SCOPE = scope_settings(SCOPE_NAME)
SELECTED = SCOPE["selected"]
SELECTORS = ["SiteTests/" + klass + "/" + method for klass, method, _ in SELECTED]
EXPECTED_NATIVE_COUNT = SCOPE["methodCount"]
IMAGE_LABELS = SCOPE["imageLabels"]
DATA_LABELS = SCOPE["dataLabels"]
EXPECTED_ATTACHMENTS = ({} if SCOPE_NAME == "impact-pool-lifecycle" else IMPACT_POOL_ATTACHMENTS if SCOPE_NAME == "impact-pool" else PLAYABILITY_ATTACHMENTS if SCOPE_NAME == "playability-followup" else SOURCE_SKIN_ATTACHMENTS if SCOPE_NAME == "source-skins-followup" else
                        PRESENTATION_ATTACHMENTS if SCOPE_NAME == "presentation-followup" else FOLLOWUP_ATTACHMENTS)
USES_SOURCE_SKINS = SCOPE_NAME in ("source-skins-followup", "playability-followup")
USES_PRESENTATION = SCOPE_NAME in ("impact-pool-lifecycle", "impact-pool", "presentation-followup", "coverage-followup", "source-skins-followup", "playability-followup")
if USES_SOURCE_SKINS:
    MANIFESTS.append(".github/private/fighter-source-trails/manifest.json")
if USES_PRESENTATION:
    MANIFESTS.append(".github/private/fighter-presentation/manifest.json")
    RECIPIENT = ROOT / ".github/public/fighter-presentation-20261113.public.pem"
    RECIPIENT_SPKI_SHA256 = "08e3294de08e37cc25a4a39332947c2208281f4b784a49561668a256e0c31779"


def work():
    value = Path(os.environ["FIGHTER_VISUAL_WORK"])
    if not value.is_absolute() or value.is_symlink():
        raise ValueError("Expected private absolute working directory")
    if os.environ.get("RUNNER_TEMP") and value != Path(os.environ["RUNNER_TEMP"]) / "fighter-visual-acceptance":
        raise ValueError("Unexpected runner working directory")
    return value


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def read_json(path):
    return json.loads(path.read_text())


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def regular(path, cap):
    if path.is_symlink() or not stat.S_ISREG(path.stat().st_mode) or not 0 < path.stat().st_size <= cap:
        raise ValueError("Evidence must be a bounded regular file")
    return path


def timing(label, started, code):
    path = work() / "timings.json"
    entries = read_json(path) if path.exists() else {}
    entries[label] = {"durationSeconds": round(time.monotonic() - started, 3), "exitCode": code}
    write_json(path, entries)


def run_logged(command, label, timeout):
    started = time.monotonic()
    code = None
    try:
        with (work() / (label + ".log")).open("w") as output:
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        code = result.returncode
        if code:
            raise subprocess.CalledProcessError(code, command)
    finally:
        timing(label, started, code)


def recipient_digest(data):
    if not data.startswith(b"-----BEGIN PUBLIC KEY-----\n") or b"PRIVATE KEY" in data:
        raise ValueError("Only a public recipient may be bundled")
    der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=data,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True).stdout
    return hashlib.sha256(der).hexdigest()


def selected_source_inventory(root=ROOT):
    """Bind only the selected methods, including their named Swift extensions."""
    hashes, sources = {}, {}
    directory = root / "Tests/SiteTests"
    for klass, method, _ in SELECTED:
        candidates = [directory / (klass + ".swift")] + sorted(directory.glob(klass + "+*.swift"))
        declarations = []
        for path in candidates:
            if not path.is_file():
                continue
            assert not path.is_symlink(), "Selected source must be a regular file"
            text = path.read_text()
            count = len(re.findall(r"^\s*func\s+" + re.escape(method) + r"\s*\(", text, re.M))
            if count:
                assert re.search(r"\b(?:class|extension)\s+" + re.escape(klass) + r"\b", text)
                declarations.extend([path] * count)
        assert len(declarations) == 1, "Missing or duplicate exact method: " + klass + "/" + method
        path = declarations[0]
        source = str(path.relative_to(root))
        hashes[source] = digest(path)
        sources["SiteTests/" + klass + "/" + method] = source
    return hashes, sources


def prepare():
    os.umask(0o077)
    assert os.environ["GITHUB_REPOSITORY"] == "wuyong9494-lab/kriswu"
    assert os.environ["GITHUB_REF"] == BRANCH and os.environ["GITHUB_EVENT_NAME"] == "push"
    expected = os.environ["GITHUB_SHA"]
    assert re.fullmatch("[a-f0-9]{40}", expected)
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    assert actual == expected, "Checkout/source SHA mismatch"
    event = read_json(Path(os.environ["GITHUB_EVENT_PATH"]))
    assert event["head_commit"]["message"].startswith(SCOPE["commitPrefix"])
    assert len(SELECTORS) == len(set(SELECTORS)) == EXPECTED_NATIVE_COUNT
    assert len(IMAGE_LABELS + DATA_LABELS) == len(set(IMAGE_LABELS + DATA_LABELS))
    if SCOPE_NAME != "baseline-11":
        assert os.environ["GITHUB_WORKFLOW_REF"] == "wuyong9494-lab/kriswu/" + SCOPE["workflow"] + "@" + BRANCH
        assert set(EXPECTED_ATTACHMENTS) == set(IMAGE_LABELS + DATA_LABELS)
        assert all(row["selector"] in SELECTORS for row in EXPECTED_ATTACHMENTS.values())
    assert recipient_digest(RECIPIENT.read_bytes()) == RECIPIENT_SPKI_SHA256
    hashes, method_sources = selected_source_inventory()
    for path in MANIFESTS + ["project.yml", ".github/scripts/fighter_visual_acceptance.py",
                             ".github/scripts/fighter_private_model.py", ".github/scripts/fighter_sf3_assets.py",
                             ".github/scripts/fighter_sf3_distinct.py", SCOPE["workflow"]] + SCOPE["additionalSources"]:
        hashes[path] = digest(ROOT / path)
    work().mkdir(mode=0o700, exist_ok=False)
    identity = {"sourceSha": actual, "ref": BRANCH, "beforeSha": event.get("before"),
                "scope": SCOPE_NAME, "workflowSource": SCOPE["workflow"],
                "runId": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"],
                "preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "selectedSourceSHA256": hashes, "resourceManifestReferences": MANIFESTS,
                "expectedNativeMethods": EXPECTED_NATIVE_COUNT,
                "selectors": [{"identifier": selector, "scenarioType": row[2], "sourceFile": method_sources[selector]}
                              for selector, row in zip(SELECTORS, SELECTED)],
                "expectedImageLabels": IMAGE_LABELS, "expectedDataLabels": DATA_LABELS,
                "expectedAttachments": EXPECTED_ATTACHMENTS if SCOPE_NAME != "baseline-11" else None,
                "recipientSPKISHA256": RECIPIENT_SPKI_SHA256,
                "wrappedKeyEncoding": "raw-32", "wrappedKeyEntropyBytes": 32,
                "keyWrapping": "RSA-OAEP-SHA256; same new envelope password to both recipients",
                "limitations": ["Simulator evidence, not physical-device acceptance or stable-60fps measurement",
                                "Original skill choreography and audible sound/music are not accepted by these methods",
                                "No SwiftPM/core107, old synthetic22, full resource suite or UI flow is rerun",
                                "This unsigned job does not change TestFlight/Release state or upload an app/source resource"]}
    write_json(work() / "identity.json", identity)
    print(f"Pinned source {actual}; scope {SCOPE_NAME}; {EXPECTED_NATIVE_COUNT} native methods; "
          f"{len(IMAGE_LABELS)} image labels and {len(DATA_LABELS)} data labels; unsigned simulator only.")


def resource_records():
    rows = []
    for manifest_path in MANIFESTS:
        manifest = read_json(ROOT / manifest_path)
        for row in manifest.get("assets", manifest.get("files", [])):
            rows.append({"file": row["file"], "bytes": row["bytes"], "sha256": row["sha256"],
                         "manifest": manifest_path,
                         "encryptedParts": row.get("parts", manifest.get("parts", [])),
                         "cipherSHA256": row.get("cipher_sha256", manifest.get("cipher_sha256"))})
    count = 73 if USES_SOURCE_SKINS else 72 if USES_PRESENTATION else 64
    assert len(rows) == count and len({row["file"] for row in rows}) == count
    return rows


def audit_resources(base, bundled):
    rows = resource_records()
    valid = True
    for row in rows:
        row["verificationLevel"] = "compiled bundle bytes/hash" if bundled else "authenticated staged bytes/hash"
        row["runtimeUse"] = "Only selected XCTest scenario assertions; not proof that every file was displayed or audible"
        matches = list(base.rglob(row["file"])) if bundled else [base / row["file"]]
        row["result"] = "failed"
        row["failureReason"] = "missing or duplicate compiled resource"
        if len(matches) == 1 and matches[0].is_file() and not matches[0].is_symlink():
            row["actualBytes"] = matches[0].stat().st_size
            row["actualSHA256"] = digest(matches[0])
            ok = row["actualBytes"] == row["bytes"] and row["actualSHA256"] == row["sha256"]
            row["result"] = "verified" if ok else "failed"
            row["failureReason"] = None if ok else "compiled size or digest mismatch"
        valid = valid and row["result"] == "verified"
    write_json(work() / ("compiled-resources.json" if bundled else "staged-resources.json"), rows)
    if not valid:
        raise ValueError("Resource integrity verification failed; encrypted evidence records individual failures")


def stage():
    # These unchanged readers authenticate existing ciphertext before publishing
    # any file. The secret is scoped to this step only and never copied.
    run_logged([sys.executable, ".github/scripts/fighter_sf3_assets.py"], "stage-scenery", 180)
    run_logged([sys.executable, ".github/scripts/fighter_sf3_distinct.py"], "stage-distinct", 180)
    if USES_PRESENTATION:
        run_logged([sys.executable, ".github/scripts/fighter_presentation_assets.py", "stage"], "stage-presentation", 60)
    if USES_SOURCE_SKINS:
        run_logged([sys.executable, ".github/scripts/fighter_source_trails.py", "stage"], "stage-source-skins", 60)
    audit_resources(ROOT / "App/Resources/FighterPrivate", bundled=False)
    print(str(len(resource_records())) + " character/scenery/feedback/presentation files authenticated and staged; no plaintext upload.")


def build():
    assert "FIGHTER_LIU_MODEL_KEY" not in os.environ, "Resource key must not enter build/test steps"
    assert "FIGHTER_PRESENTATION_KEY" not in os.environ, "Presentation key must not enter build/test steps"
    project = ROOT / "project.yml"
    source = project.read_text()
    original_hash = digest(project)
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    assert source.count(needle) == 1
    project.write_text(source.replace(needle, needle + '\n      commandLineArguments:\n        "-demo": true'))
    write_json(work() / "compiled-project.json", {"originalProjectSHA256": original_hash,
               "compiledProjectSHA256": digest(project), "demoArgumentEnabled": True,
               "onlyProjectConfigurationChange": "SiteTests scheme inherits existing -demo host launch path",
               "configuration": "Debug", "signingAllowed": False, "testBundle": "SiteTests"})
    run_logged([sys.executable, ".github/scripts/build_identity.py"], "build-identity", 60)
    run_logged(["xcodegen", "generate"], "project-generation", 120)
    run_logged(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj", "-scheme", "ShiftReminder",
                "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", str(work() / "derived"), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGN_IDENTITY="], "native-build", 1100)
    products = work() / "derived/Build/Products"
    runs = list(products.glob("*.xctestrun"))
    assert len(runs) == 1, "Ambiguous test products"
    data = plistlib.loads(runs[0].read_bytes())
    targets = [t for c in data.get("TestConfigurations", []) for t in c.get("TestTargets", [])]
    if "TestConfigurations" not in data:
        targets = [dict(v, BlueprintName=k) for k, v in data.items() if isinstance(v, dict) and k != "__xctestrun_metadata__"]
    assert len(targets) == 1 and targets[0].get("BlueprintName") == "SiteTests"
    assert "-demo" in targets[0].get("CommandLineArguments", [])
    assert not targets[0].get("IsUITestBundle", False) and not targets[0].get("SkipTestIdentifiers")
    (work() / "xctestrun-path.txt").write_text(str(runs[0]))
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    assert app.is_dir()
    audit_resources(app, bundled=True)
    assert not any(p.suffix in (".enc", ".pem", ".key") or "Model_Key" in p.name for p in app.rglob("*") if p.is_file())
    print("Unsigned SiteTests host built once; demo arguments and all " + str(len(resource_records())) + " compiled resource identities verified.")


def simulator():
    started = time.monotonic()
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"], text=True, timeout=60))
    runtimes = {r["identifier"]: r for r in catalog["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]}
    choices = [(tuple(map(int, re.findall(r"\d+", runtimes[r]["version"]))), r, d["deviceTypeIdentifier"])
               for r, devices in catalog["devices"].items() if r in runtimes
               for d in devices if d.get("isAvailable") and d.get("deviceTypeIdentifier", "").endswith(".iPhone-17-Pro-Max")]
    assert choices, "An installed iPhone 17 Pro Max/iOS runtime is required; no download/fallback authorized"
    _, runtime, dtype = max(choices)
    name = "Fighter visual " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]
    udid = subprocess.check_output(["xcrun", "simctl", "create", name, dtype, runtime], text=True, timeout=60).strip()
    assert re.fullmatch(r"[0-9A-Fa-f-]{36}", udid)
    write_json(work() / "simulator.json", {"udid": udid, "name": name, "runtime": runtime, "type": dtype,
                                         "osVersion": runtimes[runtime]["version"], "evidenceClass": "real-resource simulator"})
    run_logged(["xcrun", "simctl", "boot", udid], "simulator-boot", 120)
    run_logged(["xcrun", "simctl", "bootstatus", udid, "-b"], "simulator-ready", 480)
    timing("simulator-total", started, 0)
    print("Prepared one installed iPhone 17 Pro Max simulator on iOS " + runtimes[runtime]["version"])


def export_result(kind):
    with (work() / (kind + ".json")).open("w") as output, (work() / ("result-" + kind + ".log")).open("w") as errors:
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(work() / "selected.xcresult")],
                                stdout=output, stderr=errors, timeout=90)
    if result.returncode:
        raise ValueError("Result export incomplete")


def verify_scope_identity(identity):
    """A lost scope environment must not silently fall back to eleven tests."""
    assert identity.get("scope", "baseline-11") == SCOPE_NAME, "Prepared visual scope mismatch"
    assert identity["expectedNativeMethods"] == EXPECTED_NATIVE_COUNT
    assert [row["identifier"] for row in identity["selectors"]] == SELECTORS
    assert identity["expectedImageLabels"] == IMAGE_LABELS and identity["expectedDataLabels"] == DATA_LABELS


def verify_results(summary, data):
    for key, value in [("totalTestCount", EXPECTED_NATIVE_COUNT), ("passedTests", EXPECTED_NATIVE_COUNT), ("failedTests", 0), ("skippedTests", 0)]:
        assert type(summary.get(key)) is int and summary[key] == value, "Unexpected summary count"
    assert summary.get("result") == "Passed" and isinstance(data.get("testNodes"), list)
    seen = []
    def walk(nodes):
        for node in nodes:
            if node.get("nodeType") == "Test Case":
                raw = node.get("nodeIdentifier", "").removesuffix("()")
                matches = [s for s in SELECTORS if raw in (s, "/".join(s.split("/")[1:]))]
                assert len(matches) == 1 and node.get("result") == "Passed", "Unexpected native test result"
                seen.append(matches[0])
            else:
                walk(node.get("children", []))
    walk(data["testNodes"])
    assert collections.Counter(seen) == collections.Counter(SELECTORS), "Missing, extra or repeated selected test"


def test():
    assert "FIGHTER_LIU_MODEL_KEY" not in os.environ
    assert "FIGHTER_PRESENTATION_KEY" not in os.environ
    verify_scope_identity(read_json(work() / "identity.json"))
    device = read_json(work() / "simulator.json")
    command = ["xcodebuild", "test-without-building", "-xctestrun", (work() / "xctestrun-path.txt").read_text(),
               "-destination", "id=" + device["udid"], "-parallel-testing-enabled", "NO",
               "-resultBundlePath", str(work() / "selected.xcresult")]
    command += ["-only-testing:" + selector for selector in SELECTORS]
    code = 0
    try:
        run_logged(command, "selected-native", 990)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        code = error.returncode if isinstance(error, subprocess.CalledProcessError) else 124
    write_json(work() / "native-process.json", {"exitCode": code, "scope": SCOPE_NAME,
                                               "selectedCount": EXPECTED_NATIVE_COUNT, "iterations": 1})
    if (work() / "selected.xcresult/Info.plist").is_file():
        export_result("summary")
        export_result("tests")
    if code:
        raise SystemExit(code)
    verify_results(read_json(work() / "summary.json"), read_json(work() / "tests.json"))
    (work() / "native-ok.txt").write_text(f"{EXPECTED_NATIVE_COUNT} passed; 0 failed; 0 skipped; exact method inventory\n")
    print(f"Native results: {EXPECTED_NATIVE_COUNT} passed; 0 failed; 0 skipped; exact method inventory; no retries.")


def followup_attachment_inventory(root, expected_device=None):
    """Exact manifest ownership for the follow-up, never substring matching.

    The xcresult export manifest records both the XCTest method and generated
    filename. Only the seven named PNG payloads may satisfy this scope; a label
    mentioned in another JSON/log, an extra image or a repeated label fails.
    The encrypted partial archive is still available when this gate fails.
    """
    paths = sorted(root.rglob("*"))
    assert all(not path.is_symlink() for path in paths), "Symlink in exported evidence"
    files = [path for path in paths if path.is_file()]
    assert len(files) <= 160, "Attachment count exceeds bounded probe"
    for path in files:
        regular(path, 12 * 1024**2)
    manifest_path = root / "manifest.json"
    assert manifest_path in files, "Missing xcresult attachment manifest"
    manifest = read_json(manifest_path)
    assert isinstance(manifest, list), "Unexpected xcresult attachment manifest"
    seen_methods, seen_files, seen_labels, entries = set(), set(), set(), []
    image_matches = {label: [] for label in IMAGE_LABELS}
    data_matches = {label: [] for label in DATA_LABELS}
    for group in manifest:
        assert isinstance(group, dict) and isinstance(group.get("attachments"), list)
        identifier = group.get("testIdentifier", "").removesuffix("()")
        selectors = [selector for selector in SELECTORS if identifier in (selector, "/".join(selector.split("/")[1:]))]
        assert len(selectors) == 1 and selectors[0] not in seen_methods, "Unexpected or repeated attachment method"
        selector = selectors[0]
        seen_methods.add(selector)
        for attachment in group["attachments"]:
            name = attachment.get("exportedFileName", "")
            assert name and Path(name).name == name and "\\" not in name and ".." not in name, "Unsafe exported filename"
            path = root / name
            assert path in files and name not in seen_files, "Missing or repeated attachment file"
            seen_files.add(name)
            human = attachment.get("suggestedHumanReadableName", "")
            suffix = path.suffix.lower()
            matches = [label for label in EXPECTED_ATTACHMENTS
                       if re.fullmatch(re.escape(label) + r"_[0-9]+_[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}" + re.escape(suffix), human)]
            assert len(matches) == 1 and matches[0] not in seen_labels, "Unexpected or repeated exact attachment label"
            label = matches[0]
            seen_labels.add(label)
            expected = EXPECTED_ATTACHMENTS[label]
            assert expected["selector"] == selector, "Attachment belongs to the wrong selected method"
            if expected_device:
                assert attachment.get("deviceId") == expected_device["udid"] and attachment.get("deviceName") == expected_device["name"], "Attachment simulator identity mismatch"
            if expected["kind"] == "image":
                assert suffix == ".png", "Expected PNG evidence"
                with path.open("rb") as image:
                    assert image.read(8) == b"\x89PNG\r\n\x1a\n", "Invalid PNG attachment"
                image_matches[label].append(name)
            else:
                assert suffix in (".json", ".txt"), "Expected data evidence"
                data_matches[label].append(name)
            entries.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path),
                            "label": label, "selector": selector, "kind": expected["kind"]})
    assert seen_labels == set(EXPECTED_ATTACHMENTS), "Missing expected evidence labels"
    assert seen_files | {"manifest.json"} == {str(path.relative_to(root)) for path in files}, "Extra unreferenced attachment payload"
    entries.append({"file": "manifest.json", "bytes": manifest_path.stat().st_size,
                    "sha256": digest(manifest_path), "label": "xcresult attachment manifest", "kind": "manifest"})
    return {"scope": SCOPE_NAME, "imageCount": len(IMAGE_LABELS), "fileCount": len(files),
            "completeExpectedLabels": True, "exactMethodOwnership": True,
            "imageLabels": image_matches, "dataLabels": data_matches, "files": entries}


def attachment_inventory(root):
    if SCOPE_NAME != "baseline-11":
        return followup_attachment_inventory(root)
    files = sorted(p for p in root.rglob("*") if p.is_file() or p.is_symlink())
    assert len(files) <= 160, "Attachment count exceeds bounded probe"
    for path in files:
        regular(path, 12 * 1024**2)
        assert path.suffix.lower() in (".png", ".jpg", ".jpeg", ".json", ".txt"), "Unexpected attachment media type"
        if path.suffix.lower() == ".png":
            with path.open("rb") as image:
                assert image.read(8) == b"\x89PNG\r\n\x1a\n", "Invalid PNG attachment"
    labels = {str(p.relative_to(root)): p.name for p in files}
    for path in files:
        if path.suffix != ".json":
            continue
        data = read_json(path)
        def walk(value):
            if isinstance(value, dict):
                strings = " ".join(v for v in value.values() if isinstance(v, str))
                for name in labels:
                    if Path(name).name in strings:
                        labels[name] += " " + strings
                for v in value.values():
                    walk(v)
            elif isinstance(value, list):
                for v in value:
                    walk(v)
        walk(data)
    images = [p for p in files if p.suffix.lower() in (".png", ".jpg", ".jpeg")]
    assert len(images) <= 48, "Image count exceeds bounded probe"
    entries = [{"file": str(p.relative_to(root)), "bytes": p.stat().st_size, "sha256": digest(p),
                "label": labels[str(p.relative_to(root))]} for p in files]
    image_matches = {label: [str(p.relative_to(root)) for p in images if label in labels[str(p.relative_to(root))]] for label in IMAGE_LABELS}
    data_matches = {label: [str(p.relative_to(root)) for p in files if p.suffix.lower() in (".txt", ".json")
                           and label in labels[str(p.relative_to(root))]] for label in DATA_LABELS}
    complete = all(len(matches) == 1 for matches in image_matches.values()) and all(data_matches.values())
    return {"imageCount": len(images), "fileCount": len(files), "completeExpectedLabels": complete,
            "imageLabels": image_matches, "dataLabels": data_matches, "files": entries}


def export():
    verify_scope_identity(read_json(work() / "identity.json"))
    bundle = work() / "selected.xcresult"
    assert (bundle / "Info.plist").is_file(), "No finalized native results to export"
    attachments = work() / "attachments"
    attachments.mkdir(mode=0o700, exist_ok=False)
    run_logged(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", str(attachments)],
               "export-attachments", 240)
    result = (followup_attachment_inventory(attachments, read_json(work() / "simulator.json"))
              if SCOPE_NAME != "baseline-11" else attachment_inventory(attachments))
    write_json(work() / "attachment-inventory.json", result)
    assert result["completeExpectedLabels"], "Missing or duplicate expected evidence labels; keep encrypted partial evidence"
    print(f"Exported all {len(IMAGE_LABELS)} expected images and {len(DATA_LABELS)} data attachments; scope {SCOPE_NAME}.")


def wrap_key(key, public_data, path):
    public = path.with_suffix(".public.pem")
    try:
        public.write_bytes(public_data)
        result = subprocess.run(["openssl", "pkeyutl", "-encrypt", "-pubin", "-inkey", str(public),
                                 "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256"],
                                input=key, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
        path.write_bytes(result.stdout)
    finally:
        public.unlink(missing_ok=True)


def seal():
    assert "FIGHTER_LIU_MODEL_KEY" not in os.environ, "Resource key must not enter evidence sealing"
    assert "FIGHTER_PRESENTATION_KEY" not in os.environ, "Presentation key must not enter evidence sealing"
    verify_scope_identity(read_json(work() / "identity.json"))
    assert recipient_digest(RECIPIENT.read_bytes()) == RECIPIENT_SPKI_SHA256
    started = time.monotonic()
    published = work() / "published"
    published.mkdir(mode=0o700, exist_ok=False)
    archive = work() / "private-new-evidence.zip"
    try:
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_STORED) as output:
            total = 0
            excluded = []
            for path in sorted((work() / "attachments").rglob("*")) if (work() / "attachments").is_dir() else []:
                if path.is_dir():
                    assert not path.is_symlink()
                    continue
                regular(path, 12 * 1024**2)
                if path.suffix.lower() not in (".png", ".jpg", ".jpeg", ".json", ".txt"):
                    # Export remains a failed evidence gate. Preserve bounded
                    # diagnostics without uploading unexpected crash/media bytes.
                    excluded.append({"file": str(path.relative_to(work() / "attachments")),
                                     "bytes": path.stat().st_size, "reason": "attachment type not allowed"})
                    continue
                total += path.stat().st_size
                assert total <= 320 * 1024**2
                output.write(path, "attachments/" + str(path.relative_to(work() / "attachments")))
            write_json(work() / "excluded-attachments.json", {"files": excluded,
                       "effectOnAcceptance": "Exclusion never turns the strict export gate into a pass"})
            # Only bounded log tails and metadata at the private working root;
            # never recurse into source resources, app products or xcresult.
            for path in sorted(work().iterdir()):
                if path.suffix not in (".log", ".json", ".txt") or not path.is_file():
                    continue
                if path.stat().st_size == 0:
                    continue
                regular(path, 64 * 1024**2)
                with path.open("rb") as stream:
                    stream.seek(max(0, path.stat().st_size - 2 * 1024**2))
                    output.writestr("metadata/" + path.name, stream.read(2 * 1024**2))
            for name in MANIFESTS:
                output.write(ROOT / name, "asset-references/" + name.rsplit("/", 2)[1] + "-manifest.json")
        assert archive.stat().st_size <= 350 * 1024**2
        # Preserve the existing recipient convention: OAEP plaintext is 32 raw
        # random bytes; only the envelope process receives its hexadecimal form.
        key = secrets.token_bytes(32)
        wrap_key(key, EXISTING_RECIPIENT.encode(), published / "fighter-visual-evidence.key.enc")
        wrap_key(key, RECIPIENT.read_bytes(), published / "fighter-visual-evidence.session-key.enc")
        os.environ["FIGHTER_LIU_MODEL_KEY"] = key.hex()
        try:
            envelope.seal_evidence_file(archive, published / "fighter-visual-evidence.enc")
        finally:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
        files = sorted(published.glob("*.enc"))
        assert len(files) == 3
        (published / "fighter-visual-evidence.SHA256SUMS").write_text("".join(digest(path) + "  " + path.name + "\n" for path in files))
        timing("evidence-sealing", started, 0)
        print("New bounded evidence encrypted for both private recipients; only three ciphertexts and checksums may upload.")
    except BaseException:
        shutil.rmtree(published, ignore_errors=True)
        raise
    finally:
        archive.unlink(missing_ok=True)


def cleanup():
    device_path = work() / "simulator.json"
    try:
        if device_path.exists():
            device = read_json(device_path)
            catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], text=True, timeout=30))
            matches = [d for devices in catalog["devices"].values() for d in devices if d["udid"] == device["udid"]]
            assert len(matches) == 1 and matches[0]["name"] == device["name"], "Simulator cleanup ownership mismatch"
            if matches[0]["state"] != "Shutdown":
                run_logged(["xcrun", "simctl", "shutdown", device["udid"]], "simulator-shutdown", 90)
            run_logged(["xcrun", "simctl", "delete", device["udid"]], "simulator-delete", 60)
    finally:
        for path in (work() / "attachments", work() / "selected.xcresult", work() / "derived", ROOT / "App/Resources/FighterPrivate"):
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
        print("Only this run's simulator/products and staged plaintext cleaned; no repository resource changed.")


def report():
    identity = read_json(work() / "identity.json")
    verify_scope_identity(identity)
    result = {"sourceSha": identity["sourceSha"], "runId": identity["runId"], "scope": SCOPE_NAME,
              "expectedNativeMethods": EXPECTED_NATIVE_COUNT,
              "nativeExactSetPassed": (work() / "native-ok.txt").exists(), "expectedImages": len(IMAGE_LABELS),
              "timings": read_json(work() / "timings.json") if (work() / "timings.json").exists() else {},
              "physicalDeviceAcceptance": "NOT VERIFIED", "stable60fps": "NOT VERIFIED", "musicAudibility": "NOT TESTED"}
    if (work() / "attachment-inventory.json").exists():
        inventory = read_json(work() / "attachment-inventory.json")
        result.update({"exportedImageCount": inventory["imageCount"], "allExpectedLabelsPresent": inventory["completeExpectedLabels"]})
    print(json.dumps(result, indent=2))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
            output.write("### Bounded real-resource simulator evidence\n\n```json\n" + json.dumps(result, indent=2) + "\n```\n")


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("prepare", "stage", "build", "simulator", "test", "export", "seal", "cleanup", "report"))
    args = parser.parse_args()
    try:
        globals()[args.operation]()
    except Exception as error:
        if work().is_dir():
            write_json(work() / (args.operation + "-failure.json"), {"phase": args.operation, "errorType": type(error).__name__,
                                                                   "detail": str(error)[:4000]})
        print("Bounded visual phase failed: " + args.operation + "; detailed diagnostics stay in encrypted evidence.", file=sys.stderr)
        raise SystemExit(1) from None
