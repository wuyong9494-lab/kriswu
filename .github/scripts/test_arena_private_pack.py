import copy
import gzip
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import traceback
import unittest
from unittest.mock import patch
import urllib.error
import zlib

import arena_private_pack as release

SOURCE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("pack_builder", SOURCE / "scripts/assets/build_resource_pack.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def synthetic_png(width=2, height=3, optimized=False, pixel=b"\xff\0\0\xff"):
    def chunk(kind, content):
        return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content) & 0xffffffff)
    pixels = zlib.compress((b"\0" + pixel * width) * height)
    return (b"\x89PNG\r\n\x1a\n" + (chunk(b"CgBI", b"\x50\0\x20\x02") if optimized else b"")
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", pixels) + chunk(b"IEND", b""))


def existing_asset_fixture(root, app):
    source = root / "asset-source"
    vendor = source / "App/ArenaVendor"
    vendor.mkdir(parents=True)
    app.mkdir(parents=True, exist_ok=True)
    files = []
    for index in range(104):
        name = f"vendor_{index}.png" if index < 9 else f"vendor_{index}.bin"
        content = synthetic_png() if index < 9 else f"synthetic asset {index}".encode()
        (vendor / name).write_bytes(content)
        (app / name).write_bytes(synthetic_png(optimized=True) if index < 9 else content)
        files.append({"file": name, "pack": f"pack-{index % 11}", "bytes": len(content),
                      "sha256": hashlib.sha256(content).hexdigest()})
    canonical = b"synthetic canonical ranger"
    (source / "App/Arena3D").mkdir()
    (source / "App/Arena3D/Ranger_FaceSample.glb").write_bytes(canonical)
    (app / "Ranger_FaceSample.glb").write_bytes(canonical)
    configuration = {"canonicalRanger": {"file": "Ranger_FaceSample.glb", "sha256": hashlib.sha256(canonical).hexdigest()}}
    for folder in (vendor, app):
        (folder / "arena-vendor-runtime.json").write_text(json.dumps({"packCount": 11, "files": files}))
        (folder / "arena-asset-configuration.json").write_text(json.dumps(configuration))
    for relative in release.OPAQUE_TEXTURE_SOURCES:
        path = source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(synthetic_png())
        (app / path.name).write_bytes(path.read_bytes())
    (source / "App/Info.plist").write_bytes(plistlib.dumps({"ArenaResourcePackRequiredForPromotion": True}))
    (source / "scripts/assets").mkdir(parents=True)
    shutil.copyfile(SOURCE / "scripts/assets/build_resource_pack.py", source / "scripts/assets/build_resource_pack.py")
    return source


class DownloadResponse(io.BytesIO):
    def __init__(self, data, *, short_read=None, content_length=True):
        super().__init__(data)
        self.short_read = short_read
        self.headers = ({} if content_length is None else
                        {"Content-Length": str(len(data) if content_length is True else content_length)})

    def read(self, size=-1):
        if self.short_read is not None:
            size = min(size, self.short_read)
        return super().read(size)

    def geturl(self):
        return "https://private.invalid/file?token=do-not-log-this-token"


class PrivatePackReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "note.txt").write_bytes(b"synthetic test data")
        payload = self.root / "note.txt"
        manifest = {
            "schemaVersion": 1, "id": "synthetic", "title": "Synthetic", "sourceDescription": "Test data",
            "sourceSHA256": "0" * 64, "heroes": [], "themes": [], "music": [], "maps": [], "musicBindings": {},
            "files": [{"path": "note.txt", "kind": "notice", "bytes": payload.stat().st_size,
                       "sha256": builder.sha_file(payload)}],
        }
        header = self.root / "manifest.json"
        header.write_text(json.dumps(manifest))
        self.pack = self.root / release.PACK_NAME
        builder.build(header, self.root, self.pack)
        self.expected = {"id": "synthetic", "bytes": self.pack.stat().st_size, "sha256": builder.sha_file(self.pack)}

    def tearDown(self):
        self.temporary.cleanup()

    def testArchiveContainsExactVerifiedPayload(self):
        archive = self.root / "build.xcarchive"
        app = archive / "Products/Applications/ShiftReminder.app"
        app.mkdir(parents=True)
        source = existing_asset_fixture(self.root, app)
        shutil.copyfile(self.pack, app / release.PACK_NAME)
        report = release.archive(self.expected, source, archive)
        self.assertTrue(report["all_payload_hashes_verified"])
        self.assertTrue(report["canonical_ranger_verified"])
        self.assertTrue(report["asset_configuration_verified"])
        self.assertEqual(report["vendor_runtime_file_count"], 104)
        self.assertEqual(report["vendor_pack_count"], 11)
        self.assertTrue(report["opaque_textures_verified"])
        self.assertEqual(report["opaque_texture_count"], 6)
        self.assertNotIn("path", report)
        self.assertEqual(report["sha256"], self.expected["sha256"])
        texture = app / "hexagons_medieval.png"
        original = texture.read_bytes()
        texture.write_bytes(synthetic_png(optimized=True))
        with self.assertRaises(ValueError):
            release.archive(self.expected, source, archive)
        texture.write_bytes(original)
        (app / "duplicate").mkdir()
        shutil.copyfile(self.pack, app / "duplicate" / release.PACK_NAME)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            release.archive(self.expected, source, archive)

    def testArchiveCLIProducesOnlyIdentityAndVerificationMetadata(self):
        archive = self.root / "report.xcarchive"
        app = archive / "Products/Applications/ShiftReminder.app"
        source = existing_asset_fixture(self.root, app)
        shutil.copyfile(self.pack, app / release.PACK_NAME)
        request = {"private_resource_pack": self.expected, "source_sha": "a" * 40,
                   "source_run_id": 123, "build_number": "999", "version": "1.2"}
        path = self.root / "request.json"
        path.write_text(json.dumps(request))
        subprocess.run([sys.executable, str(SOURCE / ".github/scripts/arena_private_pack.py"), "archive",
                        str(path), "--source", str(source), "--archive", str(archive)],
                       cwd=self.root, check=True, capture_output=True)
        report = json.loads((self.root / release.ARCHIVE_REPORT).read_text())
        self.assertEqual(report["source_sha"], request["source_sha"])
        self.assertEqual(report["sha256"], self.expected["sha256"])
        self.assertEqual(report["vendor_runtime_file_count"], 104)
        self.assertTrue(report["canonical_ranger_verified"])
        self.assertFalse(any("url" in key or "payload" in key and key != "all_payload_hashes_verified" for key in report))
        self.assertEqual(report["opaque_texture_count"], 6)
        self.assertTrue(report["opaque_textures_verified"])

    def testEvenRehashedOuterFileCannotConcealBadInternalPayload(self):
        data = bytearray(self.pack.read_bytes())
        data[-1] ^= 1
        self.pack.write_bytes(data)
        expected = {**self.expected, "sha256": hashlib.sha256(data).hexdigest()}
        with self.assertRaises(AssertionError):
            release.verify(self.pack, expected, SOURCE)

    def testPackInsideWidgetCannotPassMainAppValidation(self):
        archive = self.root / "misplaced.xcarchive"
        widget = archive / "Products/Applications/ShiftReminder.app/PlugIns/ShiftWidget.appex"
        widget.mkdir(parents=True)
        shutil.copyfile(self.pack, widget / release.PACK_NAME)
        with self.assertRaisesRegex(ValueError, "bundle root"):
            release.archive(self.expected, SOURCE, archive)

    def testChangedPackOrIdentityCannotReachUpload(self):
        with self.assertRaisesRegex(ValueError, "digest"):
            release.verify(self.pack, {**self.expected, "sha256": "0" * 64}, SOURCE)
        with self.assertRaisesRegex(ValueError, "identity"):
            release.verify(self.pack, {**self.expected, "id": "another-pack"}, SOURCE)

    def testRequestCannotContainPrivateURL(self):
        self.assertIsNone(release.specification({}))
        self.assertEqual(release.specification({"private_resource_pack": self.expected}), self.expected)
        with self.assertRaises(ValueError):
            release.specification({"private_resource_pack": {**self.expected, "url": "https://private.invalid/key"}})

    def testResourceSourceVersionCannotOmitPackMetadata(self):
        source = self.root / "source"
        (source / "App").mkdir(parents=True)
        (source / "App/Info.plist").write_bytes(plistlib.dumps({"ArenaResourcePackRequiredForPromotion": True}))
        with self.assertRaisesRegex(ValueError, "requires private_resource_pack"):
            release.required_specification({}, source)
        self.assertEqual(release.required_specification({"private_resource_pack": self.expected}, source), self.expected)


    def install_response(self, data, *, expected=None, transport=None, **response_options):
        source = self.root / "source"
        scripts = source / "scripts/assets"
        scripts.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE / "scripts/assets/build_resource_pack.py", scripts / "build_resource_pack.py")
        response = DownloadResponse(data, **response_options)
        with patch.dict(os.environ, {"ARENA_PRIVATE_PACK_URL": response.geturl()}), \
                patch.object(release.urllib.request, "build_opener") as opener:
            opener.return_value.open.return_value = response
            return release.install(expected or self.expected, source, transport)

    @staticmethod
    def transport(data, encoding="gzip"):
        return {"encoding": encoding, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    def testRawAndGzipInstallPreserveTheExactOriginalPack(self):
        original = self.pack.read_bytes()
        compressed = gzip.compress(original, mtime=0)
        for data, transport, options in (
                (original, None, {}),
                (compressed, self.transport(compressed), {}),
                (compressed, self.transport(compressed), {"short_read": 1, "content_length": None}),
                (compressed, None, {"content_length": None})):
            with self.subTest(transport=transport, options=options):
                report = self.install_response(data, transport=transport, **options)
                self.assertEqual(report["sha256"], self.expected["sha256"])
                self.assertTrue(report["all_payload_hashes_verified"])
                self.assertEqual(report["transport_sha256"], hashlib.sha256(data).hexdigest())
                self.assertEqual(report["transport_encoding"], "raw" if data == original else "gzip")
                self.assertEqual((self.root / "source/App/Resources" / release.PACK_NAME).read_bytes(), original)

    def testCorruptTruncatedAndConcatenatedGzipCannotReplaceExistingPack(self):
        compressed = gzip.compress(self.pack.read_bytes(), mtime=0)
        bad_crc = bytearray(compressed)
        bad_crc[-8] ^= 1
        output = self.root / "source/App/Resources" / release.PACK_NAME
        output.parent.mkdir(parents=True)
        output.write_bytes(b"previous installed data")
        for data in (compressed[:-1], compressed[:-8], compressed[:len(compressed) // 2],
                     bytes(bad_crc), compressed + b"garbage", compressed + gzip.compress(b"", mtime=0)):
            for short_read in (None, 1):
                with self.subTest(size=len(data), short_read=short_read):
                    with self.assertRaisesRegex(RuntimeError, "Private resource preparation failed"):
                        self.install_response(data, transport=self.transport(data), short_read=short_read)
                    self.assertEqual(output.read_bytes(), b"previous installed data")
                    self.assertFalse(output.with_suffix(".partial").exists())

    def testTransportAndOriginalIdentitiesAreIndependentlyRequired(self):
        compressed = gzip.compress(self.pack.read_bytes(), mtime=0)
        transport = self.transport(compressed)
        for metadata in ({**transport, "bytes": len(compressed) - 1},
                         {**transport, "bytes": len(compressed) + 1},
                         {**transport, "sha256": "0" * 64}, {**transport, "encoding": "raw"}):
            with self.subTest(metadata=metadata), self.assertRaises(RuntimeError):
                self.install_response(compressed, transport=metadata, content_length=None)
        for expected in ({**self.expected, "bytes": self.expected["bytes"] - 1},
                         {**self.expected, "bytes": self.expected["bytes"] + 1},
                         {**self.expected, "sha256": "0" * 64}, {**self.expected, "id": "different"}):
            with self.subTest(expected=expected), self.assertRaises(RuntimeError):
                self.install_response(compressed, expected=expected, transport=transport)

    def testDecompressionNeverWritesBeyondTheDeclaredBound(self):
        compressed = gzip.compress(b"Z" * 500_000, mtime=0)
        destination = io.BytesIO()
        with patch.object(release, "TRANSFER_CHUNK", 64), self.assertRaisesRegex(ValueError, "exceeded"):
            release.download_payload(DownloadResponse(compressed, content_length=None), destination,
                                     {"bytes": 1024})
        self.assertEqual(len(destination.getvalue()), 1024)

    def testMissingContentLengthDoesNotRemoveTransferLimits(self):
        original = self.pack.read_bytes()
        compressed = gzip.compress(original, mtime=0)
        for data, expected, transport in (
                (original + b"unexpected", self.expected, None),
                (compressed, self.expected, {**self.transport(compressed), "bytes": len(compressed) - 1})):
            with self.subTest(encoding=transport), self.assertRaises(RuntimeError):
                self.install_response(data, expected=expected, transport=transport, content_length=None)
        with patch.object(release, "MAX_TRANSPORT_BYTES", 8), self.assertRaises(RuntimeError):
            self.install_response(compressed, content_length=None)
        with self.assertRaises(RuntimeError):
            self.install_response(compressed, content_length=len(compressed) + 1)

    def testTransportSchemaCannotExposePrivateURLsOrAcceptUnboundedSizes(self):
        transport = self.transport(gzip.compress(self.pack.read_bytes(), mtime=0))
        request = {"private_resource_pack": self.expected, "private_resource_pack_transport": transport}
        self.assertEqual(release.transport_specification(request), transport)
        for invalid in ({**transport, "url": "https://private.invalid/key"},
                        {**transport, "bytes": True}, {**transport, "bytes": 0},
                        {**transport, "bytes": release.MAX_TRANSPORT_BYTES + 1},
                        {**transport, "encoding": "zip"}, {**transport, "sha256": None}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                release.transport_specification({**request, "private_resource_pack_transport": invalid})
        with self.assertRaises(ValueError):
            release.transport_specification({"private_resource_pack_transport": transport})

    def testFailureTracebackDoesNotExposeThePrivateDownloadURL(self):
        source = self.root / "source"
        url = "https://private.invalid/file?token=do-not-log-this-token"
        with patch.dict(os.environ, {"ARENA_PRIVATE_PACK_URL": url}), \
                patch.object(release.urllib.request, "build_opener") as opener:
            opener.return_value.open.side_effect = urllib.error.URLError(url)
            try:
                release.install(self.expected, source)
            except RuntimeError as error:
                self.assertNotIn(url, str(error))
                self.assertNotIn("do-not-log-this-token", traceback.format_exc())
            else:
                self.fail("Download failure must stop installation")
        self.assertFalse((source / "App/Resources" / release.PACK_NAME).with_suffix(".partial").exists())


class DeferredSourceTests(unittest.TestCase):
    def setUp(self):
        self.request = {
            "source_sha": "a" * 40, "build_number": "999", "source_run_id": 123,
            "bundle_id": "com.kriswu.shiftreminder", "version": "1.2",
            "ranger_sha256": "0" * 64, "notes": release.DEFERRED_NOTE,
            "private_resource_pack": {"id": "synthetic", "bytes": 100, "sha256": "0" * 64},
            "source_validation": {"mode": release.DEFERRED_MODE, "resource_run_id": 456},
        }
        self.run = {
            "id": 123, "head_sha": "a" * 40, "run_number": 999, "path": ".github/workflows/ios.yml",
            "status": "completed", "conclusion": "success", "event": "push", "head_branch": release.SOURCE_BRANCH,
            "head_commit": {"message": "Synthetic release [defer-arena-validation]"},
        }
        self.jobs = [{"name": name, "status": "completed", "conclusion": conclusion} for name, conclusion in
                     (("build", "success"), ("core-tests-linux", "success"), ("arena-look", "skipped"))]
        self.resource_run = {**self.run, "id": 456, "run_number": 50,
                             "path": ".github/workflows/arena-resource-validation.yml"}
        self.resource_jobs = [{"name": "resource-runtime", "status": "completed", "conclusion": "success"}]

    def validate(self, **changes):
        arguments = {"request": self.request, "run": self.run, "jobs": self.jobs,
                     "resource_run": self.resource_run, "resource_jobs": self.resource_jobs}
        release.validate_deferred_source(**{**arguments, **changes})

    def testBothCIWorkflowsMustVerifyExactlyTheRequestedSource(self):
        self.validate()
        for name, original in (("run", self.run), ("resource_run", self.resource_run)):
            for key, value in (("id", 789), ("head_sha", "b" * 40), ("path", "other.yml"),
                               ("status", "in_progress"), ("conclusion", "failure"),
                               ("event", "workflow_dispatch"), ("head_branch", "main")):
                with self.subTest(run=name, key=key), self.assertRaises(ValueError):
                    self.validate(**{name: {**original, key: value}})
        with self.assertRaisesRegex(ValueError, "number"):
            self.validate(run={**self.run, "run_number": 1000})
        with self.assertRaisesRegex(ValueError, "explicitly defer"):
            self.validate(run={**self.run, "head_commit": {"message": "No deferral"}})

    def testReleaseRequestRemainsCompatibleWithTheExistingASCLoader(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "request.json"
            path.write_text(json.dumps(self.request))
            self.assertEqual(release.promotion.load_request(path), self.request)

    def testSkippedMissingDuplicateOrFailedRequiredChecksCannotPass(self):
        for name, original in (("jobs", self.jobs), ("resource_jobs", self.resource_jobs)):
            for index, job in enumerate(original):
                bad_conclusions = ("success", "failure", "cancelled") if job["name"] == "arena-look" else ("skipped", "failure", "cancelled")
                variants = [original[:index] + original[index + 1:], original + [job],
                            [dict(item, status="in_progress") if i == index else item for i, item in enumerate(original)]]
                variants.extend([dict(item, conclusion=conclusion) if i == index else item for i, item in enumerate(original)]
                                for conclusion in bad_conclusions)
                for jobs in variants:
                    with self.subTest(check=job["name"], jobs=jobs), self.assertRaises(ValueError):
                        self.validate(**{name: jobs})

    def testDeferralRequiresExplicitMetadataNotesAndPositiveRunIDs(self):
        for field in ("source_run_id", "resource_run_id"):
            for invalid in (True, False, 0, -1, "123"):
                request = copy.deepcopy(self.request)
                if field == "source_run_id":
                    request[field] = invalid
                else:
                    request["source_validation"][field] = invalid
                with self.subTest(field=field, value=invalid), self.assertRaises(ValueError):
                    release.validation_specification(request)
        for request in ({**self.request, "private_resource_pack": None},
                        {**self.request, "notes": "Everything passed"},
                        {**self.request, "source_validation": {"mode": "unknown", "resource_run_id": 456}},
                        {**self.request, "source_validation": {"mode": release.DEFERRED_MODE}}):
            with self.subTest(request=request), self.assertRaises(ValueError):
                release.validation_specification(request)

    def testLegacyStrictGateIsPreservedWithoutAutomaticFallback(self):
        request = {key: value for key, value in self.request.items() if key != "source_validation"}
        with patch.object(release.promotion, "preflight") as strict:
            release.preflight(request)
            strict.assert_called_once_with(request)
        with patch.object(release.promotion, "preflight", side_effect=AssertionError("arena-look skipped")), \
                patch.object(release.promotion, "find_build") as find_build, self.assertRaises(AssertionError):
            release.preflight(request)
        find_build.assert_not_called()
        with patch.object(release.promotion, "preflight") as strict, self.assertRaises(ValueError):
            release.preflight({**self.request, "source_validation": {"mode": "unknown", "resource_run_id": 456}})
        strict.assert_not_called()

    def testPreflightReportsDeferralAndRetainsDuplicateUploadProtection(self):
        for build in (None, {"id": "existing", "attributes": {"processingState": "VALID"}}):
            with self.subTest(existing=bool(build)), \
                    patch.object(release.promotion, "github", side_effect=[{"object": {"sha": self.request["source_sha"]}}, self.run, {"jobs": self.jobs},
                                                                          self.resource_run, {"jobs": self.resource_jobs}]), \
                    patch.object(release.promotion, "find_build", return_value=build), \
                    patch.object(release.promotion, "output") as output, \
                    patch.object(release.promotion, "save_report") as report:
                release.preflight(self.request)
                output.assert_any_call("upload_required", "false" if build else "true")
                output.assert_any_call("source_sha", self.request["source_sha"])
                output.assert_any_call("build_number", self.request["build_number"])
                values = report.call_args.kwargs
                self.assertEqual(values["gameplay_validation"], "deferred")
                self.assertEqual(values["arena_look_conclusion"], "skipped")
                self.assertEqual(values["resource_run_id"], 456)
                self.assertEqual(values["upload_required"], build is None)


    def testSupersededSourceOrChangedCIStopsPreflightBeforeAppleAccess(self):
        with patch.object(release.promotion, "github", return_value={"object": {"sha": "b" * 40}}) as github, \
                patch.object(release.promotion, "find_build") as find_build, \
                self.assertRaisesRegex(ValueError, "superseded"):
            release.preflight(self.request)
        github.assert_called_once_with("/git/ref/heads/" + release.SOURCE_BRANCH)
        find_build.assert_not_called()
        with patch.object(release.promotion, "github", side_effect=[{"object": {"sha": "a" * 40}}, self.run,
                          {"jobs": self.jobs}, {**self.resource_run, "conclusion": "failure"}, {"jobs": self.resource_jobs}]), \
                patch.object(release.promotion, "find_build") as find_build, self.assertRaises(ValueError):
            release.preflight(self.request)
        find_build.assert_not_called()

    def testArchiveEntryRechecksHeadAndCIBeforeReadingPrivatePayload(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            request_path = root / "request.json"
            request_path.write_text(json.dumps(self.request))
            (root / "App").mkdir()
            (root / "App/Info.plist").write_bytes(plistlib.dumps({"ArenaResourcePackRequiredForPromotion": True}))
            arguments = ["arena_private_pack", "archive", str(request_path), "--source", str(root), "--archive", str(root / "archive")]
            with patch.object(sys, "argv", arguments), \
                    patch.object(release.promotion, "github", return_value={"object": {"sha": "b" * 40}}), \
                    patch.object(release, "archive") as archive, self.assertRaisesRegex(ValueError, "superseded"):
                release.main()
            archive.assert_not_called()


class ExistingResourceArchiveTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.app = self.root / "ShiftReminder.app"
        self.source = existing_asset_fixture(self.root, self.app)
        self.vendor = self.source / "App/ArenaVendor"

    def testOpaqueTexturesReportAllSixExactSourceHashes(self):
        report = release.verify_opaque_textures(self.source, self.app)
        self.assertTrue(report["opaque_textures_verified"])
        self.assertEqual(report["opaque_texture_count"], 6)
        self.assertEqual(report["opaque_texture_verification"], "standard-png-exact-source-sha256")
        self.assertEqual({entry["file"] for entry in report["opaque_textures"]}, {
            "hexagons_medieval.png", "skeleton_texture.png", "vendor_axe_texture.png",
            "vendor_knight_texture.png", "vendor_mage_texture.png", "vendor_rogue_texture.png"})
        for entry in report["opaque_textures"]:
            original = (self.source / entry["source_file"]).read_bytes()
            self.assertEqual(entry["sha256"], hashlib.sha256(original).hexdigest())
            self.assertEqual(entry["bytes"], len(original))
            self.assertEqual((entry["width"], entry["height"]), (2, 3))

    def testOpaqueTexturesRejectCgBIAndChangedPixelsWithTheSameDimensions(self):
        for relative in release.OPAQUE_TEXTURE_SOURCES:
            path = self.app / Path(relative).name
            original = path.read_bytes()
            for content in (synthetic_png(optimized=True), synthetic_png(pixel=b"\0\xff\0\xff")):
                with self.subTest(file=path.name, cgbi=b"CgBI" in content):
                    self.assertEqual(release.png_dimensions(original), release.png_dimensions(content))
                    path.write_bytes(content)
                    with self.assertRaises(ValueError):
                        release.verify_opaque_textures(self.source, self.app)
                    path.write_bytes(original)

    def testOpaqueTexturesRejectMissingDuplicateAndExtensionOnlyCopies(self):
        copies = self.app / "Copies"
        widget = self.app / "PlugIns/Widget.appex"
        copies.mkdir()
        widget.mkdir(parents=True)
        for relative in release.OPAQUE_TEXTURE_SOURCES:
            path = self.app / Path(relative).name
            original = path.read_bytes()
            path.unlink()
            with self.subTest(file=path.name, case="missing"), self.assertRaisesRegex(ValueError, "main-app"):
                release.verify_opaque_textures(self.source, self.app)
            path.write_bytes(original)
            for name in (path.name, path.name.upper()):
                duplicate = copies / name
                duplicate.write_bytes(original)
                with self.subTest(file=path.name, case=name), self.assertRaisesRegex(ValueError, "ambiguous"):
                    release.verify_opaque_textures(self.source, self.app)
                duplicate.unlink()
            extension = widget / path.name
            path.rename(extension)
            with self.subTest(file=path.name, case="widget-only"), self.assertRaisesRegex(ValueError, "main-app"):
                release.verify_opaque_textures(self.source, self.app)
            extension.rename(path)

    def testOpaqueTextureSourceMustBeStandardPNGEvenWhenArchiveBytesMatch(self):
        relative = release.OPAQUE_TEXTURE_SOURCES[0]
        source = self.source / relative
        archived = self.app / source.name
        for content in (synthetic_png(optimized=True), synthetic_png()[:-1], b"not PNG"):
            with self.subTest(content_length=len(content)):
                source.write_bytes(content)
                archived.write_bytes(content)
                with self.assertRaises(ValueError):
                    release.verify_opaque_textures(self.source, self.app)

    def testVerifiedSourceDeterminesResourceCountsAndAcceptsXcodePNGEncoding(self):
        report = release.verify_existing_resources(self.source, self.app)
        self.assertEqual(report["vendor_runtime_file_count"], 104)
        self.assertEqual(report["vendor_pack_count"], 11)
        self.assertEqual(report["vendor_png_count"], 9)
        self.assertTrue(report["vendor_runtime_verified"])
        self.assertTrue(report["asset_configuration_verified"])
        self.assertTrue(report["canonical_ranger_verified"])
        self.assertNotEqual((self.vendor / "vendor_0.png").read_bytes(), (self.app / "vendor_0.png").read_bytes())

    def testMissingChangedDuplicateOrExtensionOnlyAssetsCannotPass(self):
        path = self.app / "vendor_10.bin"
        original = path.read_bytes()
        for content in (None, b"changed"):
            with self.subTest(content=content):
                if content is None:
                    path.unlink()
                else:
                    path.write_bytes(content)
                with self.assertRaises(ValueError):
                    release.verify_existing_resources(self.source, self.app)
                path.write_bytes(original)
        extension = self.app / "PlugIns/Widget.appex"
        extension.mkdir(parents=True)
        shutil.copyfile(path, extension / path.name)
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            release.verify_existing_resources(self.source, self.app)
        path.unlink()
        with self.assertRaisesRegex(ValueError, "main-app"):
            release.verify_existing_resources(self.source, self.app)

    def testSourceResourceSizeDigestAndPackCountsCannotBeInvented(self):
        original = (self.vendor / "vendor_10.bin").read_bytes()
        (self.vendor / "vendor_10.bin").write_bytes(original + b"changed")
        with self.assertRaisesRegex(ValueError, "Source vendor resource"):
            release.verify_existing_resources(self.source, self.app)
        (self.vendor / "vendor_10.bin").write_bytes(original)
        manifest = json.loads((self.vendor / "arena-vendor-runtime.json").read_text())
        for transform in (lambda value: value.update(packCount=10),
                          lambda value: value["files"].append(value["files"][0]),
                          lambda value: value["files"][0].update(file="../outside.png"),
                          lambda value: value["files"][0].update(bytes=True),
                          lambda value: value["files"][0].update(sha256="0" * 64)):
            changed = copy.deepcopy(manifest)
            transform(changed)
            for folder in (self.vendor, self.app):
                (folder / "arena-vendor-runtime.json").write_text(json.dumps(changed))
            with self.assertRaises(ValueError):
                release.verify_existing_resources(self.source, self.app)

    def testPNGCorruptionOrWrongDimensionsCannotPass(self):
        for content in (synthetic_png(width=3), synthetic_png()[:-1], b"not PNG"):
            (self.app / "vendor_0.png").write_bytes(content)
            with self.subTest(content_length=len(content)), self.assertRaises(ValueError):
                release.verify_existing_resources(self.source, self.app)

    def testManifestConfigurationAndCanonicalRangerAreAllRequired(self):
        for name in ("arena-vendor-runtime.json", "arena-asset-configuration.json", "Ranger_FaceSample.glb"):
            path = self.app / name
            content = path.read_bytes()
            for replacement in (None, content + b"changed"):
                with self.subTest(name=name, missing=replacement is None):
                    if replacement is None:
                        path.unlink()
                    else:
                        path.write_bytes(replacement)
                    with self.assertRaises(ValueError):
                        release.verify_existing_resources(self.source, self.app)
                    path.write_bytes(content)
        (self.source / "App/Arena3D/Ranger_FaceSample.glb").write_bytes(b"changed source model")
        with self.assertRaisesRegex(ValueError, "Source canonical ranger"):
            release.verify_existing_resources(self.source, self.app)


if __name__ == "__main__":
    unittest.main()
