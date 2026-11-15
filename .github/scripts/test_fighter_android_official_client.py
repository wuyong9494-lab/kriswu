#!/usr/bin/env python3
"""New offline boundary checks only; never installs or starts Android/Apple."""
import importlib.util
from pathlib import Path
import struct
import os
import stat
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

SPEC = importlib.util.spec_from_file_location("android_client_review", Path(__file__).with_name("fighter_android_official_client.py"))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
SDK_SPEC = importlib.util.spec_from_file_location("android_sdk_review", Path(__file__).with_name("fighter_android_sdk_install.py"))
S = importlib.util.module_from_spec(SDK_SPEC)
SDK_SPEC.loader.exec_module(S)


class OfficialClientBoundaries(unittest.TestCase):
    def test_cache_scope_rejects_parent_other_app_nested_and_shell_input(self):
        self.assertTrue(M.cache_name_allowed(M.CONFIG_ROOT+"/bundles_19221.bytes"))
        for suffix in ("/../bundles_19221.bytes", "/x/bundles_19221.bytes", "/bundles_1.bytes;id", "/bundles_1.bytes\n", "/bundles_android.bytes"):
            self.assertFalse(M.cache_name_allowed(M.CONFIG_ROOT+suffix))
        self.assertFalse(M.cache_name_allowed("/data/data/"+M.PACKAGE+"/files/bundles_19221.bytes"))
        self.assertFalse(M.cache_name_allowed(M.CONFIG_ROOT.replace(M.PACKAGE, "another.package")+"/bundles_1.bytes"))

    def test_visible_new_agreement_stops_without_grant(self):
        for text in ("Terms of Service", "Privacy policy", "用户协议", "隐私政策"):
            self.assertEqual(M.wall_reason('<hierarchy><node text="'+text+'"/></hierarchy>'), "new_terms_or_privacy_prompt")
        self.assertIsNone(M.wall_reason('<hierarchy><node text="Loading resources 40%"/></hierarchy>'))

    def test_login_permission_and_purchase_remain_separate_blockers(self):
        for text, expected in (("Sign in", "account_or_captcha_prompt"),
            ("Allow Shadow Fight 3 to access photos", "system_permission_prompt"),
            ("Buy now", "purchase_prompt")):
            self.assertEqual(M.wall_reason('<hierarchy><node text="'+text+'"/></hierarchy>'), expected)

    def test_targeted_acl_parser_preserves_mask_and_unrelated_named_user(self):
        raw="# file: /dev/kvm\nuser::rw-\nuser:1002:r--\ngroup::rw-\nmask::rw-\nother::---\n"
        parsed=M.effective_acl(raw)
        self.assertEqual(parsed[("user","1002")], "r--")
        self.assertEqual(parsed[("mask","")], "rw-")
        with self.assertRaises(M.Blocked):
            M.effective_acl("default:user::rwx\n")

    def test_pid_exec_is_allowed_but_pid_reuse_or_group_change_is_not(self):
        expected={"startTimeTicks":"123", "uid":1001, "processGroup":456, "commandSHA256":"before"}
        with patch.object(M, "proc_identity", return_value={**expected,"commandSHA256":"qemu"}):
            self.assertTrue(M.same_owned_process(456, expected))
        for field, value in (("startTimeTicks","124"),("uid",0),("processGroup",999)):
            with patch.object(M,"proc_identity",return_value={**expected,field:value}):
                self.assertFalse(M.same_owned_process(456,expected))

    def test_immutable_central_directory_shape_not_just_zip_magic(self):
        offset=5000
        size=293445
        raw=struct.pack("<4s4H2IH",b"PK\x05\x06",0,0,3119,3119,size,offset,0)
        self.assertEqual(M.central_directory(raw, offset+size+22),(offset,size))
        modified=struct.pack("<4s4H2IH",b"PK\x05\x06",0,0,3119,3120,size,offset,0)
        with self.assertRaises(M.Blocked):
            M.central_directory(modified,offset+size+22)

    def test_guest_accounting_excludes_loopback_includes_both_directions(self):
        raw="lo: 100 0 0 0 0 0 0 0 100 0 0 0 0 0 0 0\nwlan0: 300 0 0 0 0 0 0 0 400 0 0 0 0 0 0 0\n"
        self.assertEqual(M.guest_bytes(raw),700)

    def test_launch_and_catalog_are_not_d19_or_device_acceptance(self):
        result=M.public_summary({"source":{},"state":"launched_without_readable_catalog",
            "gates":{"normalLaunchObserved":True,"readableBootstrapCatalogObtained":False},
            "executed":{"apkLaunches":1},"licenseAuthorization":{},"cache":{"files":[]}})
        self.assertEqual(result["d19FilesRecovered"],0)
        self.assertEqual(result["appleTests"],0)
        self.assertEqual(result["testFlightUploads"],0)
        self.assertFalse(result["gates"]["readableBootstrapCatalogObtained"])


class FixedSDKAuthorizationBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # These are already retrieved official metadata fixtures. This test
        # performs no request, installation, license write or process spawn.
        cls.main = Path(os.environ["FIGHTER_ANDROID_REVIEW_MAIN_CATALOG"]).read_bytes()
        cls.image = Path(os.environ["FIGHTER_ANDROID_REVIEW_IMAGE_CATALOG"]).read_bytes()
        cls.legal = Path(os.environ["FIGHTER_ANDROID_REVIEW_LICENSE_TEXT"]).read_bytes()

    def test_recorded_official_catalogs_select_only_the_two_approved_archives(self):
        for kind, raw in (("emulator",self.main),("image",self.image)):
            selection = S.selected_package(raw,kind)
            self.assertEqual(selection["archiveURL"],S.PACKAGES[kind]["url"])
            self.assertTrue(selection["license"]["matchesApprovedText"])
            self.assertNotIn("accepted",selection["license"])

    def test_license_requires_exact_id_and_every_original_byte(self):
        self.assertEqual(S.license_decision(S.LICENSE_ID,self.legal)["response"],"y")
        for raw in (self.legal+b"\n",self.legal.strip(),self.legal.replace(b"\n",b"\r\n"),self.legal[:-1],b""):
            if raw != self.legal:
                self.assertEqual(S.license_decision(S.LICENSE_ID,raw)["response"],"n")
        self.assertEqual(S.license_decision("android-sdk-preview-license",self.legal)["response"],"n")

    def test_candidate_archive_drift_is_rejected_before_download(self):
        root=ET.fromstring(self.main)
        package=next(x for x in root if S.local_tag(x)=="remotePackage" and x.get("path")=="emulator"
            and S.child(x,"channelRef").get("ref")=="channel-0")
        S.child(S.child(package,"revision"),"micro").text="14"
        with self.assertRaises(S.Blocked):
            S.selected_package(ET.tostring(root),"emulator")

    def test_license_definition_change_is_rejected_before_legal_response(self):
        root=ET.fromstring(self.image)
        legal=next(x for x in root if S.local_tag(x)=="license" and x.get("id")==S.LICENSE_ID)
        legal.text += "\nAdditional condition"
        with self.assertRaises(S.Blocked):
            S.selected_package(ET.tostring(root),"image")

    def test_partial_archive_or_changed_hash_is_not_the_approved_package(self):
        root=ET.fromstring(self.image)
        package=next(x for x in root if S.local_tag(x)=="remotePackage" and x.get("path")==S.PACKAGES["image"]["path"])
        complete=S.child(S.child(S.child(package,"archives"),"archive"),"complete")
        S.child(complete,"checksum").text="0"*40
        with self.assertRaises(S.Blocked):
            S.selected_package(ET.tostring(root),"image")

    def test_zip_rejects_escape_and_case_alias_before_extract(self):
        for names in (("emulator/../../outside",),("emulator/File","emulator/file")):
            with tempfile.TemporaryDirectory() as directory:
                path=Path(directory)/"synthetic.zip"
                with zipfile.ZipFile(path,"w") as out:
                    for name in names:out.writestr(name,b"fixture")
                with self.assertRaises(S.Blocked):S.zip_inventory(path,"emulator")

    def test_zip_allows_internal_link_but_rejects_external_and_cycles(self):
        for target, allowed in (("real",True),("../../outside",False),("link",False)):
            with tempfile.TemporaryDirectory() as directory:
                path=Path(directory)/"synthetic.zip"
                with zipfile.ZipFile(path,"w") as out:
                    out.writestr("emulator/real",b"fixture")
                    link=zipfile.ZipInfo("emulator/link")
                    link.create_system=3;link.external_attr=(stat.S_IFLNK|0o777)<<16
                    out.writestr(link,target)
                if allowed:self.assertEqual(S.zip_inventory(path,"emulator")["links"],{"emulator/link":"real"})
                else:
                    with self.assertRaises(S.Blocked):S.zip_inventory(path,"emulator")

    def test_image_dependency_drift_cannot_expand_installation(self):
        root=ET.fromstring(self.image)
        package=next(x for x in root if S.local_tag(x)=="remotePackage" and x.get("path")==S.PACKAGES["image"]["path"])
        dependency=S.child(S.child(package,"dependencies"),"dependency")
        dependency.set("path","extra-unapproved-package")
        with self.assertRaises(S.Blocked):S.selected_package(ET.tostring(root),"image")


if __name__ == "__main__":
    unittest.main()
