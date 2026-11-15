#!/usr/bin/env python3
"""New registration-preflight boundaries, with every Java/network call mocked.

Uses only the already retrieved two catalogs and approved license text as
fixtures. It never executes Java, SDKmanager, an installer, emulator, or any
earlier successful test method. Actual SDK Common/marshal compatibility is a
separate real-run gate; these checks do not claim to exercise the Java APIs.
"""

import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET


SPEC = importlib.util.spec_from_file_location(
    "android_sdk_registration_preflight_review",
    Path(__file__).with_name("fighter_android_sdk_install.py"))
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)


class OfficialRegistrationPreflightBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        original = Path(os.environ["FIGHTER_ANDROID_REVIEW_LICENSE_TEXT"]).read_bytes()
        official = S.exact_official_license_bytes(original)
        cls.package_xml = {}
        for kind, environment in (
            ("emulator", "FIGHTER_ANDROID_REVIEW_MAIN_CATALOG"),
            ("image", "FIGHTER_ANDROID_REVIEW_IMAGE_CATALOG"),
        ):
            raw = Path(os.environ[environment]).read_bytes()
            S.selected_package(raw, kind)
            catalog = ET.fromstring(raw)
            matches = []
            for item in catalog:
                if S.local_tag(item) != "remotePackage" or item.get("path") != S.PACKAGES[kind]["path"]:
                    continue
                revision = S.child(item, "revision")
                if S.child(revision, "preview", optional=True) is not None:
                    continue
                if S.xml_revision(revision) != S.PACKAGES[kind]["revision"]:
                    continue
                channel = S.child(item, "channelRef", optional=True)
                if channel is not None and channel.get("ref") != "channel-0":
                    continue
                matches.append(item)
            if len(matches) != 1:
                raise RuntimeError("synthetic_fixture_pinned_stable_package_not_unique")
            remote = matches[0]
            root = ET.Element("repository")
            legal = ET.SubElement(root, "license", {"id": S.LICENSE_ID, "type": "text"})
            legal.text = official.decode("utf-8")
            local = copy.deepcopy(remote)
            local.tag = "localPackage"
            for child in list(local):
                if S.local_tag(child) in ("archives", "channelRef"):
                    local.remove(child)
            root.append(local)
            cls.package_xml[kind] = ET.tostring(root)

    def fixture(self, directory):
        instance = S.Installer.__new__(S.Installer)
        instance.run_dir = Path(directory)
        instance.sdk = instance.run_dir / "synthetic-sdk"
        instance.user = instance.run_dir / "synthetic-user"
        instance.evidence = instance.run_dir / "synthetic-evidence"
        for path in (instance.sdk, instance.user, instance.evidence):
            path.mkdir(mode=0o700)
        instance.registration_bridge = {
            "java": "/never-executed/java", "directory": instance.evidence / "bridge",
            "classpath": instance.evidence / "never-read-sdkmanager-classpath.jar",
        }
        instance.save = Mock()
        instance.license_snapshot = Mock()
        instance.state = {
            "approvedTermsAccepted": False, "licenseAcceptedForExactText": False,
            "installedExactPackagesVerified": False,
            "archiveDownloadRequests": {kind: 0 for kind in S.PACKAGES},
            "license": {"reviewResponses": 0, "acceptanceResponses": 0},
            "packages": {},
            "officialRegistrationBridge": {
                "compiled": True, "inspected": True, "executed": False, "packageCalls": 0,
                "actualExistingSDKAPIsCompiledAndExecuted": False,
                "registrationPreflight": S.registration_preflight_state(),
            },
        }
        return instance

    def command(self, instance, *, fail_kind=None, change_report=None, change_xml=None):
        def invoke(args, label, timeout):
            kind = next(name for name in S.PACKAGES if label.endswith("-" + name))
            if kind == fail_kind:
                raise S.Blocked("synthetic_official_marshal_failure")
            self.assertEqual(args[-1], "--marshal-preflight")
            destination = Path(args[7])
            self.assertNotIn(instance.sdk, destination.parents)
            self.assertEqual(timeout, 60)
            raw = self.package_xml[kind]
            if change_xml:
                raw = change_xml(raw, kind)
            (destination / "package.xml").write_bytes(raw)
            result = {
                "schema": S.REGISTRATION_PREFLIGHT_SCHEMA,
                "packagePath": S.PACKAGES[kind]["path"],
                "revision": ".".join(map(str, S.PACKAGES[kind]["revision"])), "stable": True,
                "licenseId": S.LICENSE_ID, "utf8Bytes": S.OFFICIAL_LICENSE_BYTES,
                "sha1": S.OFFICIAL_LICENSE_SHA1, "sha256": S.OFFICIAL_LICENSE_SHA256,
                "representation": S.OFFICIAL_REPRESENTATION,
                "sdkCommonModuleRegistered": True, "officialMarshalCompleted": True,
                "canonicalLicenseObjectVerified": True, "temporaryMetadataOnly": True,
                "writesAcceptance": False, "installedPackageRegistration": False,
                "outputXMLBytes": len(raw), "outputXMLSHA256": S.sha256(raw),
            }
            if change_report:
                change_report(result, kind)
            return b"SDK_REGISTRATION_PREFLIGHT " + json.dumps(result).encode() + b"\n"
        return Mock(side_effect=invoke)

    def assert_not_installed_or_accepted(self, instance):
        bridge = instance.state["officialRegistrationBridge"]
        self.assertFalse(bridge["executed"])
        self.assertFalse(bridge["actualExistingSDKAPIsCompiledAndExecuted"])
        self.assertEqual(bridge["packageCalls"], 0)
        self.assertFalse(instance.state["approvedTermsAccepted"])
        self.assertFalse(instance.state["installedExactPackagesVerified"])
        self.assertEqual(instance.state["license"]["acceptanceResponses"], 0)
        self.assertEqual(instance.state["archiveDownloadRequests"], {"emulator": 0, "image": 0})

    def test_two_temporary_marshals_are_separate_from_real_registration_and_acceptance(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
            instance = self.fixture(directory)
            instance.command = self.command(instance)
            instance.preflight_official_registration()
            result = instance.state["officialRegistrationBridge"]["registrationPreflight"]
            self.assertEqual((result["calls"], result["successes"]), (2, 2))
            self.assertTrue(result["passed"])
            self.assertTrue(result["temporaryDirectoryRemoved"])
            self.assertFalse((instance.user / "sdk-registration-preflight").exists())
            self.assertEqual(list(instance.sdk.iterdir()), [])
            for kind in S.PACKAGES:
                row = result["results"][kind]
                self.assertEqual(row["officialResult"]["outputXMLSHA256"],
                                 row["temporaryMetadataIdentity"]["sha256"])
            instance.require_registration_preflight()
            self.assert_not_installed_or_accepted(instance)

    def test_first_marshal_failure_keeps_zero_success_and_cleans_temporary_xml(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
            instance = self.fixture(directory)
            instance.command = self.command(instance, fail_kind="emulator")
            with self.assertRaisesRegex(S.Blocked, "synthetic_official_marshal_failure"):
                instance.preflight_official_registration()
            result = instance.state["officialRegistrationBridge"]["registrationPreflight"]
            self.assertEqual((result["calls"], result["successes"]), (1, 0))
            self.assertFalse(result["passed"])
            self.assertTrue(result["temporaryDirectoryRemoved"])
            self.assertEqual(result["results"], {})
            self.assert_not_installed_or_accepted(instance)

    def test_second_marshal_failure_preserves_only_first_receipt_and_does_not_pass(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
            instance = self.fixture(directory)
            instance.command = self.command(instance, fail_kind="image")
            with self.assertRaises(S.Blocked):
                instance.preflight_official_registration()
            result = instance.state["officialRegistrationBridge"]["registrationPreflight"]
            self.assertEqual((result["calls"], result["successes"]), (2, 1))
            self.assertEqual(set(result["results"]), {"emulator"})
            self.assertFalse(result["passed"])
            self.assertTrue(result["temporaryDirectoryRemoved"])
            self.assert_not_installed_or_accepted(instance)

    def test_report_identity_and_actual_xml_digest_must_join_exactly(self):
        for key, value in (("sha1", S.LICENSE_SHA1), ("sdkCommonModuleRegistered", False),
                           ("outputXMLSHA256", "0" * 64), ("stable", 1)):
            with self.subTest(field=key), tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
                instance = self.fixture(directory)
                instance.command = self.command(instance, change_report=lambda report, kind: report.update({key: value}))
                with self.assertRaisesRegex(S.Blocked, "official_registration_preflight_identity_changed"):
                    instance.preflight_official_registration()
                result = instance.state["officialRegistrationBridge"]["registrationPreflight"]
                self.assertEqual(result["successes"], 0)
                self.assertFalse(result["passed"])
                self.assertTrue(result["temporaryDirectoryRemoved"])

    def test_written_xml_package_identity_is_validated_before_accepting_the_report(self):
        def change(raw, kind):
            root = ET.fromstring(raw)
            package = next(item for item in root if S.local_tag(item) == "localPackage")
            package.set("path", "unapproved-package")
            return ET.tostring(root)
        with tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
            instance = self.fixture(directory)
            instance.command = self.command(instance, change_xml=change)
            with self.assertRaisesRegex(S.Blocked, "local_package_identity_changed"):
                instance.preflight_official_registration()
            result = instance.state["officialRegistrationBridge"]["registrationPreflight"]
            self.assertFalse(result["passed"])
            self.assertTrue(result["temporaryDirectoryRemoved"])
            self.assert_not_installed_or_accepted(instance)

    def test_any_prior_yes_or_archive_request_refuses_preflight_before_commands(self):
        for section, key in (("license", "reviewResponses"), ("license", "acceptanceResponses"),
                             ("archiveDownloadRequests", "image")):
            with self.subTest(counter=key), tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
                instance = self.fixture(directory)
                instance.state[section][key] = 1
                instance.command = Mock()
                with self.assertRaisesRegex(S.Blocked, "registration_preflight_too_late"):
                    instance.preflight_official_registration()
                instance.command.assert_not_called()
                self.assertFalse((instance.user / "sdk-registration-preflight").exists())

    def test_missing_or_unclean_preflight_blocks_license_archive_and_registration_io(self):
        for field, value in (("passed", False), ("temporaryDirectoryRemoved", False),
                             ("sdkCommonModuleRegistered", False), ("successes", 1)):
            with self.subTest(field=field), tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
                instance = self.fixture(directory)
                instance.command = self.command(instance)
                instance.preflight_official_registration()
                instance.state["officialRegistrationBridge"]["registrationPreflight"][field] = value
                instance.command.reset_mock()
                with patch.object(S.subprocess, "Popen") as process, patch.object(S.urllib.request, "build_opener") as opener:
                    with self.assertRaisesRegex(S.Blocked, "official_registration_preflight_not_passed"):
                        instance.accept_only_approved_license(Path("/never-executed/sdkmanager"))
                    with self.assertRaisesRegex(S.Blocked, "official_registration_preflight_not_passed"):
                        instance.fetch(S.PACKAGES["emulator"]["url"], Path(directory) / "never-created.zip", "emulator")
                    with self.assertRaisesRegex(S.Blocked, "official_registration_preflight_not_passed"):
                        instance.register_missing_packages()
                    process.assert_not_called()
                    opener.assert_not_called()
                instance.command.assert_not_called()
                instance.license_snapshot.assert_not_called()

    def test_existing_temporary_destination_is_preserved_and_never_reused(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
            instance = self.fixture(directory)
            destination = instance.user / "sdk-registration-preflight"
            destination.mkdir()
            marker = destination / "existing.txt"
            marker.write_bytes(b"preserve")
            instance.command = Mock()
            with self.assertRaisesRegex(S.Blocked, "registration_preflight_destination_not_fresh"):
                instance.preflight_official_registration()
            self.assertEqual(marker.read_bytes(), b"preserve")
            instance.command.assert_not_called()

    def test_cleanup_failure_retains_two_metadata_receipts_without_passing_the_gate(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
            instance = self.fixture(directory)
            instance.command = self.command(instance)
            with patch.object(S.shutil, "rmtree", side_effect=OSError("synthetic cleanup failure")):
                with self.assertRaisesRegex(S.Blocked, "registration_preflight_cleanup_failed"):
                    instance.preflight_official_registration()
            result = instance.state["officialRegistrationBridge"]["registrationPreflight"]
            self.assertEqual((result["calls"], result["successes"]), (2, 2))
            self.assertFalse(result["passed"])
            self.assertFalse(result["temporaryDirectoryRemoved"])
            with self.assertRaises(S.Blocked):
                instance.require_registration_preflight()
            self.assert_not_installed_or_accepted(instance)

    def test_initial_receipt_failure_still_cleans_the_fresh_temporary_directory(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-sdk-preflight-") as directory:
            instance = self.fixture(directory)
            instance.save = Mock(side_effect=[OSError("synthetic receipt failure"), None])
            instance.command = Mock()
            with self.assertRaisesRegex(OSError, "synthetic receipt failure"):
                instance.preflight_official_registration()
            result = instance.state["officialRegistrationBridge"]["registrationPreflight"]
            self.assertTrue(result["temporaryDirectoryRemoved"])
            self.assertFalse(result["passed"])
            self.assertEqual(result["calls"], 0)
            instance.command.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
