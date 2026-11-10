"""Synthetic-only audit tests. No private resources, credentials, or network."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import audit_fighter_shadow_sources as audit


def raw_clip(frames=3, ids=(1, 2), expanded=False):
    packed = 8 + 2 * len(ids) + 12 * frames * len(ids)
    declared = 8 + 2 * len(ids) + (28 if expanded else 12) * frames * len(ids)
    header = struct.pack("<QHQQ", audit.MAGIC, 2, declared, declared)
    block = struct.pack("<II", frames, len(ids)) + struct.pack("<" + "H" * len(ids), *ids)
    block += bytes(12 * frames * len(ids))
    assert len(block) == packed
    return header + block + block


def set_raw(clip, raw):
    clip["sourceBytesBase64"] = base64.b64encode(raw).decode("ascii")
    clip["sha256"] = hashlib.sha256(raw).hexdigest()


def fixture():
    profiles = []
    for name, sides in (("sun_katana", ["left"]), ("liu_hammers", ["left", "right"])):
        tracks = {key: [[0.0, 0.0, 0.0] for _ in range(5)] for key in audit.TRACK_NAMES}
        if "right" not in sides:
            tracks["weaponBaseR"] = []
            tracks["weaponTipR"] = []
        tracks.update({"samplesPerSourceFrame": 2, "groundLift": [0.0] * 5})
        tracks["root"][2:] = [[8.4594, 0.0, 0.0] for _ in range(3)]
        clip = {"name": name + "_synthetic_shadow", "frames": 3, "bundle": "synthetic.bin",
                "sourcePathID": 2**60 + 1, "sourceArrayCount": 2, "sourceBoneIDs": [1, 2], "tracks": tracks}
        set_raw(clip, raw_clip())
        profiles.append({"id": name, "activeWeaponSides": sides,
                         "roles": {"shadow": clip["name"]}, "clips": [clip]})
    return {"schemaVersion": 1, "previewFramesPerSecond": 30, "sourceFramesPerSecond": None,
            "coordinateSpace": "actor_facing_right_metres", "profiles": profiles,
            "provenance": {"contactWindowsRecovered": False, "gameRulesRecovered": False}}


def run(catalog):
    data = json.dumps(catalog).encode("utf-8")
    return audit.audit_catalog(data, audit.digest(data))


class ShadowSourceAuditTests(unittest.TestCase):
    def test_preserves_inputs_and_provenance_without_claiming_events(self):
        catalog = fixture()
        before = copy.deepcopy(catalog)
        report = run(catalog)
        self.assertEqual(catalog, before)
        self.assertFalse(report["permitsGameplayEnablement"])
        self.assertFalse(report["authoritativeEventSemanticsRecoveredByThisAudit"])
        self.assertFalse(report["sourceTimingVerifiedByThisAudit"])
        self.assertIsNone(report["catalogSourceFramesPerSecond"])
        clip = report["profiles"][0]
        self.assertEqual(clip["sourcePathID"], 2**60 + 1)
        self.assertEqual(clip["rawLayout"]["trailingByteCount"], 0)
        self.assertEqual(clip["rawLayout"]["boneCount"], 2)
        self.assertEqual(len(clip["rawLayout"]["arrays"]), 2)
        self.assertNotIn("sourceBytesBase64", clip)
        self.assertNotIn(catalog["profiles"][0]["clips"][0]["sourceBytesBase64"], json.dumps(report))

    def test_flags_intervals_in_source_frames_without_inventing_event_windows(self):
        report = run(fixture())
        track = report["profiles"][0]["tracks"]["root"]
        self.assertEqual(track["reviewThresholdExceedances"], 1)
        step = track["largestIntervals"][0]
        self.assertEqual((step["sampleFrom"], step["sampleTo"]), (1, 2))
        self.assertEqual((step["sourceFrameFrom"], step["sourceFrameTo"]), (0.5, 1.0))
        self.assertAlmostEqual(step["distanceMetres"], 8.4594)
        self.assertEqual(report["profiles"][0]["tracks"]["weaponTipR"]["samples"], 0)

    def test_accepts_both_preexisting_declared_array_size_forms(self):
        catalog = fixture()
        set_raw(catalog["profiles"][0]["clips"][0], raw_clip(expanded=True))
        layout = run(catalog)["profiles"][0]["rawLayout"]
        self.assertEqual(layout["arrays"][0]["declaredSizeForm"], "expanded")
        self.assertGreater(layout["arrays"][0]["declaredBytes"], layout["arrays"][0]["packedBytes"])

    def test_preserves_canonical_decimal_string_path_ids_without_float_conversion(self):
        for value in ("1198749689987741031", "1152929322118614009", "0",
                      str(-(2**63)), str(2**63 - 1)):
            with self.subTest(value=value):
                catalog = fixture()
                catalog["profiles"][0]["clips"][0]["sourcePathID"] = value
                self.assertEqual(run(catalog)["profiles"][0]["sourcePathID"], value)
        for value in ("", "-0", "+1", "01", "-01", " 1", "1 ", "1.0", "1e3",
                      "١", str(2**63), str(-(2**63) - 1), "1" * 100, True):
            with self.subTest(value=value):
                catalog = fixture()
                catalog["profiles"][0]["clips"][0]["sourcePathID"] = value
                with self.assertRaises(audit.AuditError):
                    run(catalog)

    def test_rejects_catalog_or_clip_hash_mismatch(self):
        data = json.dumps(fixture()).encode()
        with self.assertRaises(audit.AuditError):
            audit.audit_catalog(data, "0" * 64)
        catalog = fixture()
        catalog["profiles"][0]["clips"][0]["sha256"] = "0" * 64
        with self.assertRaises(audit.AuditError):
            run(catalog)

    def test_rejects_malformed_raw_buffers_without_reading_past_end(self):
        valid = raw_clip()
        cases = [b"", valid[:25], valid[:30], valid[:-1], valid + b"event?",
                 b"\x00" * 8 + valid[8:]]
        modified = bytearray(valid)
        struct.pack_into("<I", modified, 26, 2**32 - 1)
        cases.append(bytes(modified))
        modified = bytearray(valid)
        struct.pack_into("<Q", modified, 10, 2**64 - 1)
        cases.append(bytes(modified))
        for raw in cases:
            with self.subTest(length=len(raw)):
                catalog = fixture()
                set_raw(catalog["profiles"][0]["clips"][0], raw)
                with self.assertRaises(audit.AuditError):
                    run(catalog)

    def test_rejects_invalid_raw_evidence_fields(self):
        cases = [("sourceBytesBase64", "!!!"), ("sourceArrayCount", True),
                 ("sourceArrayCount", 3), ("sourceBoneIDs", [2, 1]),
                 ("sourceBoneIDs", [1, 1]), ("sourceBoneIDs", [1, 65536]),
                 ("frames", True), ("frames", 2001), ("sourcePathID", float(2**60))]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                catalog = fixture()
                catalog["profiles"][0]["clips"][0][key] = value
                with self.assertRaises(audit.AuditError):
                    run(catalog)

    def test_rejects_nonfinite_bad_lengths_phantom_sides_and_overflow(self):
        mutations = [lambda t: t["root"].pop(),
                     lambda t: t["root"][0].append(0),
                     lambda t: t["root"][0].__setitem__(0, float("inf")),
                     lambda t: t["root"][0].__setitem__(0, 10**400),
                     lambda t: t["root"].__setitem__(0, [-1e308, -1e308, 0]),
                     lambda t: t.__setitem__("weaponTipR", [[0, 0, 0]] * 5),
                     lambda t: t.__setitem__("samplesPerSourceFrame", True),
                     lambda t: t["groundLift"].__setitem__(0, -0.1)]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                catalog = fixture()
                mutate(catalog["profiles"][0]["clips"][0]["tracks"])
                if index == 4:
                    catalog["profiles"][0]["clips"][0]["tracks"]["root"][1] = [1e308, 1e308, 0]
                with self.assertRaises(audit.AuditError):
                    run(catalog)

    def test_rejects_duplicate_json_keys_and_clip_names(self):
        data = b'{"schemaVersion": 1, "schemaVersion": 1}'
        with self.assertRaises(audit.AuditError):
            audit.audit_catalog(data, audit.digest(data))
        catalog = fixture()
        catalog["profiles"][0]["clips"].append(copy.deepcopy(catalog["profiles"][0]["clips"][0]))
        with self.assertRaises(audit.AuditError):
            run(catalog)

    def test_does_not_treat_new_event_metadata_or_source_fps_as_verified(self):
        catalog = fixture()
        catalog["sourceFramesPerSecond"] = 60
        catalog["profiles"][0]["clips"][0]["events"] = [{"frame": 2, "kind": "teleport"}]
        report = run(catalog)
        self.assertIn("events", report["profiles"][0]["clipFieldsPresent"])
        self.assertNotIn("events", report["profiles"][0])
        self.assertFalse(report["permitsGameplayEnablement"])
        self.assertFalse(report["sourceTimingVerifiedByThisAudit"])

    def test_requires_explicit_boolean_false_recovery_provenance(self):
        for field in ("contactWindowsRecovered", "gameRulesRecovered"):
            for value in (True, None, "false", 0, [], {}):
                with self.subTest(field=field, value=value):
                    catalog = fixture()
                    catalog["provenance"][field] = value
                    with self.assertRaises(audit.AuditError):
                        run(catalog)
            catalog = fixture()
            del catalog["provenance"][field]
            with self.assertRaises(audit.AuditError):
                run(catalog)
        catalog = fixture()
        del catalog["provenance"]
        with self.assertRaises(audit.AuditError):
            run(catalog)
        self.assertEqual(run(fixture())["catalogRecoveryProvenance"],
                         {"contactWindowsRecovered": False, "gameRulesRecovered": False})

    def test_cli_creates_report_without_overwriting_source_or_existing_report(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "synthetic.json"
            output = Path(root) / "report.json"
            data = json.dumps(fixture()).encode()
            source.write_bytes(data)
            args = ["--catalog", str(source), "--expected-sha256", audit.digest(data), "--output", str(output)]
            with patch("builtins.print"):
                self.assertEqual(audit.main(args), 0)
            original_report = output.read_bytes()
            with self.assertRaises(SystemExit), patch("sys.stderr"):
                audit.main(args)
            self.assertEqual(output.read_bytes(), original_report)
            self.assertEqual(source.read_bytes(), data)
            with self.assertRaises(SystemExit), patch("sys.stderr"):
                audit.main(args[:-1] + [str(source)])
            self.assertEqual(source.read_bytes(), data)

    def test_cli_refuses_symlink_catalog_or_output(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "synthetic.json"
            alias = Path(root) / "alias.json"
            output = Path(root) / "report.json"
            data = json.dumps(fixture()).encode()
            source.write_bytes(data)
            alias.symlink_to(source)
            args = ["--catalog", str(alias), "--expected-sha256", audit.digest(data), "--output", str(output)]
            with self.assertRaises(SystemExit), patch("sys.stderr"):
                audit.main(args)
            self.assertFalse(output.exists())
            output.symlink_to(source)
            args[1] = str(source)
            with self.assertRaises(SystemExit), patch("sys.stderr"):
                audit.main(args)
            self.assertEqual(source.read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
