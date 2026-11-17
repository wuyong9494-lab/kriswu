"""Bounded recovery-scope and publication regressions; no original resource keys."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import fighter_base_recovery as recovery


class RecoveryScopeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        # macOS TMPDIR can use /var -> /private/var. Resolve the fixture's
        # trusted parent while keeping every production symlink check strict.
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.head = "1" * 40
        self.env = dict(GITHUB_REPOSITORY=recovery.REPOSITORY, GITHUB_REF=recovery.BRANCH,
                        GITHUB_EVENT_NAME="push", GITHUB_RUN_ATTEMPT="1",
                        GITHUB_SHA=self.head, GITHUB_WORKFLOW_SHA=self.head,
                        GITHUB_WORKFLOW_REF=recovery.REPOSITORY + "/" + recovery.WORKFLOW + "@" + recovery.BRANCH)
        self.event = dict(repository=dict(full_name=recovery.REPOSITORY), ref=recovery.BRANCH,
                          before=recovery.PARENT_SHA, after=self.head, deleted=False, forced=False,
                          head_commit=dict(id=self.head, message=recovery.COMMIT_TITLE),
                          commits=[dict(id=self.head, message=recovery.COMMIT_TITLE)])

    def check(self, env=None, event=None, parents=None, changed=None):
        recovery.validate_event(env or self.env, event or self.event, self.head,
                                parents if parents is not None else [recovery.PARENT_SHA],
                                recovery.COMMIT_TITLE,
                                changed if changed is not None else recovery.ALLOWED_CHANGES)

    def test_one_exact_nonforced_push_is_accepted(self):
        self.check()

    def test_other_events_attempts_workflows_or_repositories_are_rejected(self):
        for key, value in (("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_EVENT_NAME", "workflow_dispatch"),
                           ("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_REF", "refs/heads/main"),
                           ("GITHUB_REPOSITORY", "other/repository"), ("GITHUB_WORKFLOW_SHA", "0" * 40),
                           ("GITHUB_WORKFLOW_REF", "unreviewed-workflow")):
            with self.subTest(key=key, value=value), self.assertRaises(recovery.RecoveryError):
                self.check(env=dict(self.env, **{key: value}))

    def test_extra_commit_changed_app_or_wrong_parent_are_rejected(self):
        for parents in ([], ["2" * 40], [recovery.PARENT_SHA, "3" * 40]):
            with self.subTest(parents=parents), self.assertRaises(recovery.RecoveryError):
                self.check(parents=parents)
        with self.assertRaisesRegex(recovery.RecoveryError, "commit-scope"):
            self.check(changed=set(recovery.ALLOWED_CHANGES) | {"App/Views/DuelWorld.swift"})
        with self.assertRaisesRegex(recovery.RecoveryError, "commit-scope"):
            self.check(changed={recovery.HELPER})
        for field, value in (("forced", True), ("deleted", True), ("before", "0" * 40),
                             ("commits", self.event["commits"] * 2)):
            with self.subTest(field=field), self.assertRaises(recovery.RecoveryError):
                self.check(event=dict(self.event, **{field: value}))

    def test_source_bytes_and_regular_file_identity_are_required(self):
        file = self.root / "source"
        file.write_bytes(b"reviewed")
        self.assertEqual(recovery.checked(file, recovery.sha(b"reviewed"), 8), b"reviewed")
        with self.assertRaises(recovery.RecoveryError):
            recovery.checked(file, "0" * 64, 8)
        link = self.root / "link"
        link.symlink_to(file)
        with self.assertRaisesRegex(recovery.RecoveryError, "symlink-input"):
            recovery.raw_file(link)

    def test_json_duplicates_and_nonfinite_numbers_are_rejected(self):
        for raw in (b'{"a":1,"a":2}', b'{"a":NaN}'):
            with self.assertRaises(recovery.RecoveryError):
                recovery.unique_json(raw)

    def test_resource_keys_are_not_inherited_by_unrelated_subprocesses(self):
        with patch.dict(os.environ, {"FIGHTER_LIU_MODEL_KEY": "synthetic", "ASC_KEY_P8": "synthetic"}), \
                patch.object(recovery.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"ok", b"")) as called:
            self.assertEqual(recovery.run(["synthetic-command"]), b"ok")
            child_env = called.call_args.kwargs["env"]
            self.assertNotIn("FIGHTER_LIU_MODEL_KEY", child_env)
            self.assertNotIn("ASC_KEY_P8", child_env)
            with self.assertRaisesRegex(recovery.RecoveryError, "resource-key-outside-stage"):
                recovery.no_resource_keys()

    def test_resource_environment_retains_only_its_needed_key(self):
        with patch.dict(os.environ, {"FIGHTER_H17_D19_KEY": "other-synthetic", "ASC_KEY_P8": "synthetic"}):
            with recovery.resource_environment({"FIGHTER_LIU_MODEL_KEY": "single-synthetic"}):
                self.assertEqual(os.environ["FIGHTER_LIU_MODEL_KEY"], "single-synthetic")
                self.assertNotIn("FIGHTER_H17_D19_KEY", os.environ)
                self.assertNotIn("ASC_KEY_P8", os.environ)
            self.assertEqual(os.environ["FIGHTER_H17_D19_KEY"], "other-synthetic")

    def fixture_payload(self):
        payload = self.root / "payload"
        (payload / "FighterPrivate").mkdir(parents=True)
        (payload / "FighterPrivate/synthetic.glb").write_bytes(b"reviewed")
        receipt = dict(recoveredReleaseSHA256=recovery.OLD_RELEASE_SHA,
                       equalsLaterD15Base=False, productionReady=False)
        (payload / "base-recovery-receipt-private.json").write_text(json.dumps(receipt))
        return payload

    def scoped_inventory(self, payload):
        with patch.object(recovery, "PAYLOADS", {"synthetic.glb": (8, recovery.sha(b"reviewed"))}), \
                patch.object(recovery, "PROVENANCE", {}), \
                patch.object(recovery, "AUTHENTICATED_EXTRA", {}):
            return recovery.selected_inventory(payload)

    def test_only_selected_payloads_and_receipt_can_be_sealed(self):
        payload = self.fixture_payload()
        self.assertEqual(len(self.scoped_inventory(payload)), 2)
        (payload / "unexpected-private-material.key").write_text("synthetic")
        with self.assertRaisesRegex(recovery.RecoveryError, "payload-allowlist"):
            self.scoped_inventory(payload)

    def test_changed_payloads_and_false_new_release_claims_are_rejected(self):
        payload = self.fixture_payload()
        file = payload / "FighterPrivate/synthetic.glb"
        file.write_bytes(b"modified")
        with self.assertRaisesRegex(recovery.RecoveryError, "payload-changed"):
            self.scoped_inventory(payload)
        file.write_bytes(b"reviewed")
        receipt = payload / "base-recovery-receipt-private.json"
        document = json.loads(receipt.read_text())
        document["equalsLaterD15Base"] = True
        receipt.write_text(json.dumps(document))
        with self.assertRaisesRegex(recovery.RecoveryError, "receipt-boundary-changed"):
            self.scoped_inventory(payload)

    def test_authenticated_delta_document_cannot_be_replaced(self):
        payload = self.fixture_payload()
        (payload / "provenance").mkdir()
        name = "provenance/authenticated-delta-manifest.json"
        (payload / name).write_bytes(b"reviewed-delta")
        with patch.object(recovery, "PAYLOADS", {"synthetic.glb": (8, recovery.sha(b"reviewed"))}), \
                patch.object(recovery, "PROVENANCE", {}), \
                patch.object(recovery, "AUTHENTICATED_EXTRA", {name: recovery.sha(b"reviewed-delta")}):
            self.assertEqual(len(recovery.selected_inventory(payload)), 3)
            (payload / name).write_bytes(b"modified-delta")
            with self.assertRaisesRegex(recovery.RecoveryError, "source-extra-changed"):
                recovery.selected_inventory(payload)

    def test_payload_symlink_is_rejected(self):
        payload = self.fixture_payload()
        (payload / "escape").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(recovery.RecoveryError, "payload-symlink"):
            self.scoped_inventory(payload)

    def test_phase_is_single_use_and_cleanup_preserves_only_encrypted_output(self):
        with patch.dict(os.environ, RUNNER_TEMP=str(self.root)):
            work = recovery.work()
            work.mkdir()
            (work / "private").mkdir()
            (work / "private/plaintext").write_text("synthetic private input")
            (work / "published").mkdir()
            (work / "published/recovered-inputs.cms").write_bytes(b"synthetic ciphertext")
            recovery.once("stage")
            with self.assertRaises(recovery.RecoveryError):
                recovery.once("stage")
            recovery.cleanup()
            self.assertFalse((work / "private").exists())
            self.assertFalse((work / "stage.started").exists())
            self.assertTrue((work / "published/recovered-inputs.cms").exists())

    def test_embedded_recipient_and_authenticated_encryption_parameters(self):
        binary = recovery.openssl_path()
        certificate = self.root / "recipient.crt"
        certificate.write_bytes(recovery.CERTIFICATE_PEM)
        self.assertEqual(hashlib.sha256(certificate.read_bytes()).hexdigest(), recovery.CERTIFICATE_SHA)
        recovery.validate_recipient(binary, certificate)
        clear, cipher = self.root / "probe", self.root / "probe.cms"
        clear.write_bytes(b"public synthetic recovery probe")
        output = recovery.cms_encrypt(binary, clear, certificate, cipher)
        self.assertNotIn(clear.read_bytes(), output)
        structure = recovery.run([binary, "cms", "-cmsout", "-print", "-inform", "DER", "-in", str(cipher)])
        self.assertIn(b"aes-256-gcm", structure.lower())
        self.assertIn(b"rsaesoaep", structure.lower())
        self.assertIn(b"sha256", structure.lower())
        with self.assertRaisesRegex(recovery.RecoveryError, "envelope-not-new"):
            recovery.cms_encrypt(binary, clear, certificate, cipher)


if __name__ == "__main__":
    unittest.main()
