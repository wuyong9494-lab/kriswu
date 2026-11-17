"""Synthetic archive integrity, real-path and incomplete-resource regressions."""
import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import audit_fighter_continuation as audit


def encoded(obj):
    return json.dumps(obj, separators=(",", ":")).encode()


def reference(name, raw):
    return {"file": name, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def fixture(bottle_present=True):
    files = {}
    for kind, directory in (("Cloud", "serpent-cloud-runtime-v2"), ("Bottle", "serpent-rain-runtime-v1")):
        root = "reused-inputs/work-products/" + directory + "/"
        model = (kind + " PRIVATE_MEDIA_BYTES").encode()
        if kind != "Bottle" or bottle_present:
            files[root + kind + ".glb"] = model
        files[root + "SF3_D13_" + kind + "_Motion_Binding.json"] = encoded(
            dict(modelBytes=len(model), modelSHA256=audit.digest(model), samples=[{}, {}]))
    root = "continued-20261116/serpent-abilities-models-v1/"
    files[root + "Vines.glb"] = b"PRIVATE_VINE_BYTES"
    files[root + "receipt-private.json"] = encoded(dict(
        sourceOnly=True, runtimeBound=False, nativeOrAppExecuted=False,
        products=[reference("Vines.glb", files[root + "Vines.glb"])]))
    root = "continued-20261116/serpent-match-v2/"
    files[root + "Profile.json"] = encoded({"private": "PRIVATE_RULE_BYTES"})
    files[root + "match-integration-receipt-private.json"] = encoded(dict(
        profile=reference("Profile.json", files[root + "Profile.json"]),
        boundaries={"runtimeBound": False, "nativeRenderingVerified": False}))
    root = audit.CURRENT_CONTOUR + "/"
    files[root + "Profile.json"] = encoded({"private": "PRIVATE_D15_RULES"})
    files[root + "Character.glb"] = b"PRIVATE_D15_GEOMETRY"
    groups, unique = [], []
    for kind in ("audio", "hound", "stomp", "sword", "skill"):
        name = kind + (".wav" if kind == "audio" else ".png")
        files[root + name] = (kind + " PRIVATE_PCM_OR_TEXTURE").encode()
        item = reference(name, files[root + name])
        unique.append(item)
        manifest = dict(characterSHA256=audit.digest(files[root + "Character.glb"]),
                        profileSHA256=audit.digest(files[root + "Profile.json"]), files=[item])
        plain = encoded(manifest)
        filename = kind + ".json"
        files[root + filename] = plain
        group = dict(kind=kind, manifest=reference(filename, plain))
        if kind != "audio":
            files[root + filename + ".gz"] = gzip.compress(plain, mtime=0)
            group["compressedManifest"] = reference(filename + ".gz", files[root + filename + ".gz"])
        groups.append(group)
    receipt = dict(profile=reference("Profile.json", files[root + "Profile.json"]),
                   character=reference("Character.glb", files[root + "Character.glb"]), groups=groups,
                   referencedMediaFiles=len(unique), uniqueMediaFiles=len(unique),
                   uniqueMediaBytes=sum(r["bytes"] for r in unique), productionPinsChanged=False,
                   nativeRenderingVerified=False, nativePlaybackVerified=False)
    files[root + "erlang-contour-media-binding-private.json"] = encoded(receipt)
    root = "continued-20261116/xuxiao-founder-source-v2/"
    files[root + "xuxiao-required-resources-v1.json"] = encoded(dict(
        sourceOnly=True, runtimeBound=False, productionActivated=False,
        equipment=[dict(symbol="SYNTHETIC_EQUIPMENT", model="Top100/synthetic", sourceBundles=[])],
        motions=[dict(sourceFile="unique_moves/sets_d20/synthetic.bin", sourceBundles=[])]))
    return files


def pack(base, files, mutate_manifest=None):
    rows = [dict(path=name, bytes=len(raw), sha256=audit.digest(raw)) for name, raw in files.items()]
    blobs = {audit.digest(raw): raw for raw in files.values()}
    cp = dict(format="rift-private-continuation-v1", files=rows,
              logicalFileCount=len(rows), uniqueBlobCount=len(blobs),
              logicalBytes=sum(len(raw) for raw in files.values()),
              uniqueBytes=sum(len(raw) for raw in blobs.values()))
    if mutate_manifest:
        mutate_manifest(cp)
    path = base / "checkpoint.zip"
    with zipfile.ZipFile(path, "w") as target:
        target.writestr("README.txt", b"Synthetic fixture; not game assets.")
        target.writestr("checkpoint.json", encoded(cp))
        for sha, raw in blobs.items():
            target.writestr("blobs/" + sha, raw)
    return path, audit.digest(path.read_bytes())


def prior_pack(base, files):
    path = base / "prior.zip"
    with zipfile.ZipFile(path, "w") as target:
        for name, raw in files.items():
            target.writestr(name, raw)
    return path, audit.digest(path.read_bytes())


class ContinuationAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def run_audit(self, files, mutate_manifest=None, restored=None):
        path, sha = pack(self.base, files, mutate_manifest)
        return audit.audit(path, sha, restored)

    def test_resolves_cloud_and_bottle_from_reused_inputs_and_preserves_gates(self):
        result = self.run_audit(fixture())
        self.assertTrue(result["integrityVerified"])
        self.assertTrue(result["D13"]["resourceClosureComplete"])
        self.assertTrue(result["D15"]["contourMediaClosureComplete"])
        self.assertEqual(result["D15"]["uniqueMediaFiles"], 5)
        for binding in result["D13"]["bindings"]:
            self.assertTrue(binding["binding"]["path"].startswith("reused-inputs/"))
            self.assertFalse(binding["modelPresenceInferredFromBinding"])
        for key in ("productionReady", "nativeTestsExecuted", "deviceAcceptancePerformed",
                    "productionPinsChanged", "testFlightUploaded", "resourceClosureComplete"):
            self.assertFalse(result[key])
        text = json.dumps(result)
        self.assertNotIn("PRIVATE_MEDIA_BYTES", text)
        self.assertNotIn("PRIVATE_D15_RULES", text)

    def test_binding_does_not_substitute_for_missing_model_bytes(self):
        result = self.run_audit(fixture(bottle_present=False))
        self.assertFalse(result["D13"]["resourceClosureComplete"])
        bottle = next(b for b in result["D13"]["bindings"] if b["kind"] == "bottle")
        self.assertEqual(bottle["model"]["status"], "missing-from-checkpoint")
        self.assertTrue(result["D15"]["contourMediaClosureComplete"])

    def test_prior_checkpoint_resolves_exact_bottle_and_preserves_current_bindings(self):
        path, sha = pack(self.base, fixture(bottle_present=False))
        supplement = prior_pack(self.base, {
            "old/Bottle.glb": b"Bottle PRIVATE_MEDIA_BYTES",
            "old/SF3_D13_Bottle_Motion_Binding.json": encoded(dict(modelSHA256="0" * 64)),
        })
        result = audit.audit(path, sha, supplemental_archives=[supplement])
        bottle = next(b for b in result["D13"]["bindings"] if b["kind"] == "bottle")
        self.assertEqual(bottle["model"]["status"], "verified")
        self.assertEqual(bottle["model"]["paths"], ["supplements/0/old/Bottle.glb"])
        self.assertTrue(bottle["binding"]["path"].startswith("reused-inputs/"))
        self.assertEqual(result["supplementalArchives"][0]["files"], 2)
        self.assertEqual(result["archive"]["logicalFiles"], len(fixture(bottle_present=False)))
        self.assertTrue(result["D13"]["resourceClosureComplete"])
        self.assertFalse(result["productionReady"])

    def test_prior_checkpoint_name_is_not_a_resource_identity(self):
        path, sha = pack(self.base, fixture(bottle_present=False))
        supplement = prior_pack(self.base, {"old/Bottle.glb": b"unrelated geometry"})
        result = audit.audit(path, sha, supplemental_archives=[supplement])
        self.assertFalse(result["D13"]["resourceClosureComplete"])
        with self.assertRaisesRegex(audit.AuditError, "Archive SHA"):
            audit.audit(path, sha, supplemental_archives=[(supplement[0], "0" * 64)])

    def test_prior_checkpoint_cannot_supply_traversal_or_symlink(self):
        path, sha = pack(self.base, fixture())
        supplement = prior_pack(self.base, {"../outside": b"private"})
        with self.assertRaisesRegex(audit.AuditError, "Unsafe checkpoint path"):
            audit.audit(path, sha, supplemental_archives=[supplement])
        with zipfile.ZipFile(supplement[0], "w") as target:
            info = zipfile.ZipInfo("link")
            info.create_system = 3
            info.external_attr = 0o120777 << 16
            target.writestr(info, "outside")
        with self.assertRaisesRegex(audit.AuditError, "Unsupported supplemental ZIP entry"):
            audit.audit(path, sha, supplemental_archives=[(supplement[0], audit.digest(supplement[0].read_bytes()))])

    def test_rejects_changed_media_even_when_outer_checkpoint_is_valid(self):
        files = fixture()
        files[audit.CURRENT_CONTOUR + "/audio.wav"] = b"DIFFERENT_VALID_CHECKPOINT_BLOB"
        with self.assertRaisesRegex(audit.AuditError, "local reference"):
            self.run_audit(files)

    def test_stale_actor_binding_is_not_a_complete_contour(self):
        files = fixture()
        root = audit.CURRENT_CONTOUR + "/"
        manifest = json.loads(files[root + "audio.json"])
        manifest["characterSHA256"] = "0" * 64
        files[root + "audio.json"] = encoded(manifest)
        receipt = json.loads(files[root + "erlang-contour-media-binding-private.json"])
        receipt["groups"][0]["manifest"] = reference("audio.json", files[root + "audio.json"])
        files[root + "erlang-contour-media-binding-private.json"] = encoded(receipt)
        with self.assertRaisesRegex(audit.AuditError, "stale character"):
            self.run_audit(files)

    def test_gzip_peer_must_match_plain_manifest(self):
        files = fixture()
        root = audit.CURRENT_CONTOUR + "/"
        files[root + "hound.json.gz"] = gzip.compress(b"{}", mtime=0)
        receipt = json.loads(files[root + "erlang-contour-media-binding-private.json"])
        receipt["groups"][1]["compressedManifest"] = reference("hound.json.gz", files[root + "hound.json.gz"])
        files[root + "erlang-contour-media-binding-private.json"] = encoded(receipt)
        with self.assertRaisesRegex(audit.AuditError, "gzip and plain"):
            self.run_audit(files)

    def test_restored_tree_is_verified_independently(self):
        files, directory = fixture(), self.base / "restored"
        for name, raw in files.items():
            target = directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        result = self.run_audit(files, restored=directory)
        self.assertTrue(result["restoredFilesVerified"])
        (directory / audit.CURRENT_CONTOUR / "audio.wav").write_bytes(b"changed after restore")
        with self.assertRaisesRegex(audit.AuditError, "Restored bytes differ"):
            self.run_audit(files, restored=directory)

    def test_rejects_duplicate_or_traversal_manifest_paths(self):
        for mutate in (lambda cp: cp["files"].append(cp["files"][0]),
                       lambda cp: cp["files"][0].update(path="../outside")):
            with self.subTest(mutate=mutate), self.assertRaises(audit.AuditError):
                self.run_audit(fixture(), mutate)

    def test_rejects_bad_archive_pin_and_invalid_blob(self):
        path, sha = pack(self.base, fixture())
        with self.assertRaisesRegex(audit.AuditError, "Archive SHA"):
            audit.audit(path, "0" * 64)
        def corrupt(cp):
            cp["files"][0]["bytes"] += 1
        with self.assertRaisesRegex(audit.AuditError, "blob differs"):
            self.run_audit(fixture(), corrupt)

    def test_d20_catalog_name_and_text_are_not_real_resource_closure(self):
        files = fixture()
        root = "continued-20261116/xuxiao-founder-source-v2/"
        doc = json.loads(files[root + "xuxiao-required-resources-v1.json"])
        doc["motions"][0]["sourceBundles"] = [reference("candidate.bin", b"actual source bundle")]
        files[root + "xuxiao-required-resources-v1.json"] = encoded(doc)
        files["reused-inputs/candidate.bin"] = b"filename exists but wrong bytes"
        files["reused-inputs/archive.bytes"] = b"D20 D20 D20 bundlesConfig_android"
        result = self.run_audit(files)["D20"]
        self.assertFalse(result["resourceClosureComplete"])
        self.assertFalse(result["authenticatedDynamicIndexRecoveredByThisAudit"])
        self.assertEqual(result["catalogBundleReferences"][0]["status"], "missing-from-checkpoint")
        self.assertEqual(result["missingMotionFiles"], [])
        self.assertEqual(result["motionsWithoutVerifiedBundleBytes"], 1)
        self.assertTrue(result["resources"]["motions"][0]["catalogMappingPresent"])
        self.assertFalse(result["resources"]["motions"][0]["allReferencedBundleBytesVerified"])
        self.assertEqual(result["indexFileCandidates"], [])
        self.assertEqual(len(result["configArchiveFiles"]), 1)

    def test_prior_d20_bundle_is_byte_proof_but_not_decoded_object_or_runtime_acceptance(self):
        files = fixture()
        name = "continued-20261116/xuxiao-founder-source-v2/xuxiao-required-resources-v1.json"
        doc = json.loads(files[name])
        raw = b"actual original motion bundle"
        doc["motions"][0]["sourceBundles"] = [reference("source.bin", raw)]
        files[name] = encoded(doc)
        path, sha = pack(self.base, files)
        supplement = prior_pack(self.base, {"bundles/source.bin": raw})
        result = audit.audit(path, sha, supplemental_archives=[supplement])["D20"]
        self.assertEqual(result["motionsWithoutVerifiedBundleBytes"], 0)
        self.assertTrue(result["resources"]["motions"][0]["allReferencedBundleBytesVerified"])
        self.assertFalse(result["resources"]["motions"][0]["decodedSourceObjectVerifiedByThisAudit"])
        self.assertFalse(result["resourceClosureComplete"])

    def test_companion_must_bind_current_actor_and_identical_profile_track(self):
        files = fixture()
        root = audit.CURRENT_CONTOUR + "/"
        profile = json.loads(files[root + "Profile.json"])
        profile["summonTracks"] = [dict(role="erlangSummon_hound", root=[0, 1, 2])]
        files[root + "Profile.json"] = encoded(profile)
        receipt = json.loads(files[root + "erlang-contour-media-binding-private.json"])
        receipt["profile"] = reference("Profile.json", files[root + "Profile.json"])
        for group in receipt["groups"]:
            name = group["manifest"]["file"]
            document = json.loads(files[root + name])
            document["profileSHA256"] = audit.digest(files[root + "Profile.json"])
            files[root + name] = encoded(document)
            group["manifest"] = reference(name, files[root + name])
            if "compressedManifest" in group:
                files[root + name + ".gz"] = gzip.compress(files[root + name], mtime=0)
                group["compressedManifest"] = reference(name + ".gz", files[root + name + ".gz"])
        files[root + "erlang-contour-media-binding-private.json"] = encoded(receipt)
        companion = dict(profileID="wuyong_erlang", characterSHA256=audit.digest(files[root + "Character.glb"]),
                         models=[dict(file=reference("hound.glb", b"hound geometry"),
                                      track=profile["summonTracks"][0])])
        files["bound/SF3_D15_Companions.json"] = encoded(companion)
        files["bound/hound.glb"] = b"hound geometry"
        result = self.run_audit(files)["D15"]
        self.assertEqual(result["additionalRuntimeManifests"][0]["status"], "verified-current-actor-model-and-track")
        self.assertFalse(result["completeAppCandidateVerified"])
        companion["models"][0]["track"]["root"] = [999]
        files["bound/SF3_D15_Companions.json"] = encoded(companion)
        with self.assertRaisesRegex(audit.AuditError, "companion and profile tracks differ"):
            self.run_audit(files)

    def test_source_receipt_claims_are_not_current_native_acceptance(self):
        files = fixture()
        name = audit.CURRENT_CONTOUR + "/erlang-contour-media-binding-private.json"
        receipt = json.loads(files[name])
        receipt["nativeRenderingVerified"] = True
        files[name] = encoded(receipt)
        result = self.run_audit(files)
        self.assertTrue(result["D15"]["recordedState"]["nativeRenderingVerified"])
        self.assertFalse(result["nativeTestsExecuted"])
        self.assertFalse(result["productionReady"])


if __name__ == "__main__":
    unittest.main()
