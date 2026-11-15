#!/usr/bin/env python3
"""New license-representation boundaries only; no real SDK/license/network IO.

Fixtures are already retrieved official catalogs, the approved original text,
and the already authenticated failed dialogue. No fixture is downloaded here.
Synthetic acceptance records live only in TemporaryDirectory test folders.
These methods do not run the previous 16 tests, Java, SDKmanager or an emulator.
"""

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET


SPEC = importlib.util.spec_from_file_location(
    "android_license_representation_review", Path(__file__).with_name("fighter_android_sdk_install.py"))
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)
RUNTIME_SPEC = importlib.util.spec_from_file_location(
    "android_license_runtime_review", Path(__file__).with_name("fighter_android_official_client.py"))
R = importlib.util.module_from_spec(RUNTIME_SPEC)
RUNTIME_SPEC.loader.exec_module(R)


class OfficialLicenseRepresentationBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = Path(os.environ["FIGHTER_ANDROID_REVIEW_LICENSE_TEXT"]).read_bytes()
        cls.catalogs = {
            "emulator": Path(os.environ["FIGHTER_ANDROID_REVIEW_MAIN_CATALOG"]).read_bytes(),
            "image": Path(os.environ["FIGHTER_ANDROID_REVIEW_IMAGE_CATALOG"]).read_bytes(),
        }
        raw = Path(os.environ["FIGHTER_ANDROID_REVIEW_LICENSE_DIALOGUE"]).read_bytes()
        pattern = re.compile(
            rb"(?:^|\n)(?:[0-9]+/[0-9]+: )?License android-sdk-license:\n"
            rb"-{39}\n(.*?)\n-{39}\nAccept\? \(y/N\): ?", re.DOTALL)
        matches = pattern.findall(raw)
        if len(matches) != 1:
            raise RuntimeError("authenticated_fixture_sdk_prompt_not_unique")
        cls.official = matches[0]

    def fixture_installer(self, directory, lines, *, inspected=True, mapping=True):
        """Synthetic fixture only; never instantiate an actual SDK Installer."""
        instance = S.Installer.__new__(S.Installer)
        instance.sdk = Path(directory) / "synthetic-sdk"
        license_dir = instance.sdk / "licenses"
        license_dir.mkdir(parents=True, mode=0o700)
        (license_dir / S.LICENSE_ID).write_text("\n" + "\n".join(lines))
        instance.license_before = {}
        instance.state = {
            "approvedTermsAccepted": False, "licenseAcceptedForExactText": False,
            "officialRegistrationBridge": {"inspected": inspected},
            "license": {
                "representationMapping": S.license_mapping_receipt(self.original) if mapping else None,
                "acceptanceResponses": 1,
                "decisions": [S.license_decision(S.LICENSE_ID, self.official,
                                                representation=S.OFFICIAL_REPRESENTATION)],
                "mutationPolicyPassed": False,
            },
        }
        return instance

    def test_exact_six_edits_reproduce_the_authenticated_cli_value(self):
        adapted = S.exact_official_license_bytes(self.original)
        self.assertTrue(adapted == self.official)
        self.assertEqual(len(adapted), 16960)
        self.assertEqual(hashlib.sha1(adapted).hexdigest(), S.OFFICIAL_LICENSE_SHA1)
        self.assertEqual(hashlib.sha256(adapted).hexdigest(), S.OFFICIAL_LICENSE_SHA256)
        receipt = S.license_mapping_receipt(self.original)
        self.assertEqual(len(receipt["edits"]), 6)
        self.assertFalse(receipt["originalBytesEqual"])
        self.assertFalse(receipt["arbitraryNormalizationAllowed"])

    def test_catalog_and_dialogue_representations_are_not_interchangeable(self):
        self.assertTrue(S.license_decision(S.LICENSE_ID, self.original)["accepted"])
        self.assertFalse(S.license_decision(S.LICENSE_ID, self.official)["accepted"])
        self.assertTrue(S.license_decision(S.LICENSE_ID, self.official,
                                          representation=S.OFFICIAL_REPRESENTATION)["accepted"])
        self.assertFalse(S.license_decision(S.LICENSE_ID, self.original,
                                           representation=S.OFFICIAL_REPRESENTATION)["accepted"])

    def test_additional_whitespace_punctuation_or_other_license_id_is_rejected(self):
        variants = (
            self.official + b"\n", self.official + b" ", self.official.replace(b"\n", b"\r\n"),
            self.official.replace(b"Terms and Conditions", b"Terms  and Conditions", 1),
            self.official.replace(b"Terms and Conditions", b"Terms and Conditions.", 1),
        )
        for value in variants:
            self.assertFalse(S.license_decision(S.LICENSE_ID, value,
                                               representation=S.OFFICIAL_REPRESENTATION)["accepted"])
        self.assertFalse(S.license_decision("android-sdk-preview-license", self.official,
                                           representation=S.OFFICIAL_REPRESENTATION)["accepted"])
        for value in (self.original + b"\n", self.original[:-1], self.official):
            with self.assertRaises(S.Blocked):
                S.exact_official_license_bytes(value)

    def test_both_existing_catalogs_keep_the_original_approval_pin(self):
        for kind, raw in self.catalogs.items():
            selected = S.selected_package(raw, kind)
            self.assertEqual(selected["license"]["sha1"], S.LICENSE_SHA1)
            self.assertEqual(selected["license"]["utf8Bytes"], 16962)
            root = ET.fromstring(raw)
            legal = next(item for item in root if S.local_tag(item) == "license"
                         and item.get("id") == S.LICENSE_ID)
            legal.text = self.official.decode("utf-8")
            with self.assertRaises(S.Blocked):
                S.selected_package(ET.tostring(root), kind)

    def test_local_package_xml_joins_known_raw_forms_to_official_effective_hash(self):
        source = ET.fromstring(self.catalogs["image"])
        remote = next(item for item in source if S.local_tag(item) == "remotePackage"
                      and item.get("path") == S.PACKAGES["image"]["path"])
        for raw, expected in ((self.original, S.ORIGINAL_REPRESENTATION),
                              (self.official, S.OFFICIAL_REPRESENTATION)):
            root = ET.Element("repository")
            legal = ET.SubElement(root, "license", {"id": S.LICENSE_ID, "type": "text"})
            legal.text = raw.decode("utf-8")
            local = copy.deepcopy(remote)
            local.tag = "localPackage"
            for item in list(local):
                if S.local_tag(item) in ("archives", "channelRef"):
                    local.remove(item)
            root.append(local)
            with tempfile.TemporaryDirectory(prefix="synthetic-license-xml-") as directory:
                path = Path(directory) / "package.xml"
                path.write_bytes(ET.tostring(root))
                result = S.registration_identity(path, "image")
                self.assertEqual(result["rawXMLLicenseRepresentation"], expected)
                self.assertEqual(result["officialAcceptanceHash"], S.OFFICIAL_LICENSE_SHA1)
                self.assertEqual(result["effectiveOfficialLicenseIdentity"]["sha256"], S.OFFICIAL_LICENSE_SHA256)
                legal.text += " "
                path.write_bytes(ET.tostring(root))
                with self.assertRaises(S.Blocked):
                    S.registration_identity(path, "image")

    def test_verified_official_hash_records_terms_acceptance_without_claiming_original_bytes(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-license-record-") as directory:
            instance = self.fixture_installer(directory, [S.OFFICIAL_LICENSE_SHA1])
            instance.observe_license_mutation()
            self.assertTrue(instance.state["approvedTermsAccepted"])
            self.assertTrue(instance.state["licenseAcceptedForExactText"])
            self.assertEqual(instance.state["license"]["acceptedRepresentation"], S.OFFICIAL_REPRESENTATION)
            self.assertEqual(instance.state["license"]["acceptedRecordSHA1"], S.OFFICIAL_LICENSE_SHA1)
            self.assertTrue(instance.state["license"]["mutationPolicyPassed"])
            instance.state["state"] = "blocked"  # A later unrelated failure cannot erase the actual receipt.
            instance.observe_license_mutation()
            self.assertTrue(instance.state["approvedTermsAccepted"])

    def test_original_hash_or_additional_acceptance_does_not_pass_the_mutation_gate(self):
        for lines, accepted in (([S.LICENSE_SHA1], False),
                                ([S.OFFICIAL_LICENSE_SHA1, S.LICENSE_SHA1], True)):
            with tempfile.TemporaryDirectory(prefix="synthetic-license-record-") as directory:
                instance = self.fixture_installer(directory, lines)
                instance.observe_license_mutation()
                self.assertIs(instance.state["approvedTermsAccepted"], accepted)
                self.assertFalse(instance.state["license"]["mutationPolicyPassed"])

    def test_missing_mapping_or_official_inspection_cannot_accept_or_start_sdkmanager(self):
        for mapping, inspected in ((False, True), (True, False)):
            with tempfile.TemporaryDirectory(prefix="synthetic-license-record-") as directory:
                instance = self.fixture_installer(directory, [S.OFFICIAL_LICENSE_SHA1],
                                                   mapping=mapping, inspected=inspected)
                instance.observe_license_mutation()
                self.assertFalse(instance.state["approvedTermsAccepted"])
                with patch.object(S.subprocess, "Popen") as process:
                    with self.assertRaises(S.Blocked):
                        instance.accept_only_approved_license(Path("/never-executed/sdkmanager"))
                    process.assert_not_called()

    def inspection_fixture(self):
        instance = S.Installer.__new__(S.Installer)
        instance.evidence = Path("/synthetic-not-read")
        instance.registration_bridge = {
            "java": "/never-executed/java", "directory": Path("/synthetic-not-read"),
            "classpath": Path("/synthetic-not-read/sdkmanager-classpath.jar")}
        instance.save = Mock()
        instance.state = {
            "archiveDownloadRequests": {"emulator": 0, "image": 0},
            "license": {"catalogRepresentationMatches": {"emulator": True, "image": True},
                        "representationMapping": S.license_mapping_receipt(self.original),
                        "acceptanceResponses": 0},
            "officialRegistrationBridge": {
                "compiled": True, "executed": False, "packageCalls": 0,
                "inspectionCalls": 0, "inspectionSuccesses": 0, "inspected": False,
                "inspectionResults": {},
            },
        }
        return instance

    def inspection_output(self, path):
        value = {
            "schema": "android-sdk-official-license-inspection-v1", "packagePath": path,
            "licenseId": S.LICENSE_ID, "utf8Bytes": S.OFFICIAL_LICENSE_BYTES,
            "sha1": S.OFFICIAL_LICENSE_SHA1, "sha256": S.OFFICIAL_LICENSE_SHA256,
            "representation": S.OFFICIAL_REPRESENTATION, "officialUnmarshalVerified": True,
            "writesPackageXML": False, "writesAcceptance": False,
        }
        return b"SDK_LICENSE_REPRESENTATION " + json.dumps(value).encode() + b"\n"

    def test_read_only_inspection_counts_are_separate_from_package_registration(self):
        instance = self.inspection_fixture()
        instance.command = Mock(side_effect=[self.inspection_output(S.PACKAGES[kind]["path"])
                                             for kind in ("emulator", "image")])
        instance.inspect_official_license_representations()
        bridge = instance.state["officialRegistrationBridge"]
        self.assertEqual((bridge["inspectionCalls"], bridge["inspectionSuccesses"]), (2, 2))
        self.assertTrue(bridge["inspected"])
        self.assertFalse(bridge["executed"])
        self.assertEqual(bridge["packageCalls"], 0)
        self.assertEqual(instance.command.call_count, 2)

    def test_wrong_java_inspection_identity_stops_before_acceptance_or_download(self):
        instance = self.inspection_fixture()
        raw = self.inspection_output(S.PACKAGES["emulator"]["path"])
        instance.command = Mock(return_value=raw.replace(S.OFFICIAL_LICENSE_SHA1.encode(), S.LICENSE_SHA1.encode()))
        with self.assertRaises(S.Blocked):
            instance.inspect_official_license_representations()
        bridge = instance.state["officialRegistrationBridge"]
        self.assertEqual((bridge["inspectionCalls"], bridge["inspectionSuccesses"]), (1, 0))
        self.assertFalse(bridge["inspected"])
        self.assertEqual(instance.state["license"]["acceptanceResponses"], 0)
        self.assertEqual(instance.state["archiveDownloadRequests"], {"emulator": 0, "image": 0})


class RuntimeLicenseRepresentationBoundaries(unittest.TestCase):
    def receipt(self):
        return {"approvedTermsAccepted":True, "licenseAcceptedForExactText":True,
            "licenseAcceptedForExactTextBasis":"official_adapted_identity_not_original_XML_bytes",
            "installedExactPackagesVerified":False,
            "license":{"approvedOriginal":S.license_identity(S.ORIGINAL_REPRESENTATION),
                "officialAdaptedIdentity":S.license_identity(S.OFFICIAL_REPRESENTATION),
                "originalBytesEqual":False, "approvedOriginalBytesAcceptedVerbatim":False,
                "acceptedRepresentation":S.OFFICIAL_REPRESENTATION,
                "acceptedRecordSHA1":S.OFFICIAL_LICENSE_SHA1}}

    def test_partial_install_failure_retains_acceptance_with_both_exact_identities(self):
        receipt = self.receipt()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"sdk-install-receipt.json").write_text(json.dumps(receipt))
            state = {"source":{}, "state":"blocked", "licenseAuthorization":{},
                "executed":{"apkDownloads":0,"emulatorBoots":0,"apkInstalls":0,"apkLaunches":0},
                "gates":{"licenseAcceptedForExactText":False,"sdkInstalled":False}}
            with patch.object(R, "evidence", return_value=root):
                R.merge_sdk_progress(state)
            public = R.public_summary(state)
            self.assertTrue(public["gates"]["licenseAcceptedForExactText"])
            self.assertFalse(public["gates"]["sdkInstalled"])
            self.assertEqual(public["executed"]["apkLaunches"], 0)
            projection = public["licenseAcceptance"]
            self.assertTrue(projection["approvedTermsAccepted"])
            self.assertFalse(projection["approvedOriginalBytesAcceptedVerbatim"])
            self.assertEqual(projection["approvedOriginal"]["sha256"], S.LICENSE_SHA256)
            self.assertEqual(projection["officialAdaptedIdentity"]["sha256"], S.OFFICIAL_LICENSE_SHA256)
            self.assertEqual(projection["acceptedRecordSHA1"], S.OFFICIAL_LICENSE_SHA1)

    def test_alias_alone_wrong_basis_or_original_hash_cannot_claim_acceptance(self):
        for location, key, value in (
            ("top","approvedTermsAccepted",False),
            ("top","licenseAcceptedForExactText",False),
            ("top","licenseAcceptedForExactTextBasis","original_XML_bytes"),
            ("license","acceptedRepresentation",S.ORIGINAL_REPRESENTATION),
            ("license","acceptedRecordSHA1",S.LICENSE_SHA1),
            ("license","approvedOriginalBytesAcceptedVerbatim",True),
            ("license","originalBytesEqual",True)):
            receipt = self.receipt()
            target = receipt if location == "top" else receipt["license"]
            target[key] = value
            self.assertFalse(R.license_acceptance_summary(receipt)["approvedTermsAccepted"])
        receipt = self.receipt()
        receipt["license"]["approvedOriginal"]["sha256"] = "0"*64
        self.assertFalse(R.license_acceptance_summary(receipt)["approvedTermsAccepted"])
        self.assertFalse(R.license_acceptance_summary()["approvedTermsAccepted"])


if __name__ == "__main__":
    unittest.main()
