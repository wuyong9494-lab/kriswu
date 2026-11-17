"""Narrow source-contract checks; no native binary, App, or GPU is executed.

Original-input checks require ERLANG_EFFECT_STOP_NATIVE_DIR and/or
ERLANG_EFFECT_STOP_SWORD_RECEIPT. Missing inputs are explicit skips.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import tempfile
import unittest

from erlang_effect_stop_source_state import (
    FrameStopJob, RendererObservation, SetFloat, SetInactive, SourceNullReference,
    SWORD_EFFECTS, callback_transparency, load_sword_stop_contract, request_stop,
)


EVIDENCE = json.loads((Path(__file__).with_name(
    "erlang_effect_stop_source_evidence_20261117.json")).read_text())
LIVE = (RendererObservation("renderer-1", True, "material-1"),)


def bits(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


def schedule(frames=10, at=100, count=1, alive=True):
    return request_stop(effect_object_id="effect-1", frames=frames,
                        renderer_count=count, effect_object_alive=alive,
                        observed_frame=at)


def evaluate(job, frame, renderers=LIVE, alive=True):
    return job.evaluate(observed_frame=frame, renderers=renderers,
                        effect_object_alive=alive)


class IntegerFrameStopChecks(unittest.TestCase):
    def test_enqueue_has_no_uniform_write_or_invented_first_callback(self):
        request = schedule()
        self.assertEqual(request.commands, ())
        first = evaluate(request.job, 103)
        self.assertEqual(first.observed_frame, 103)
        self.assertEqual(bits(first.transparency), 0x3F333333)
        self.assertFalse(first.completed)
        self.assertEqual(first.commands, (SetFloat("renderer-1", "material-1", "_Transparent", first.transparency),))

    def test_repeated_observed_frame_does_not_advance_or_suppress_callback(self):
        job = schedule().job
        result = evaluate(job, 103)
        for _ in range(10):
            self.assertEqual(evaluate(job, 103), result)
        self.assertEqual(job.start_frame, 100)
        self.assertEqual(job.end_frame, 110)

    def test_two_float32_subtractions_are_not_replaced_with_a_ratio(self):
        result = evaluate(schedule().job, 109)
        self.assertEqual(bits(result.progress), 0x3F666666)
        self.assertEqual(bits(result.transparency), 0x3DCCCCD0)
        self.assertNotEqual(bits(result.transparency), bits(0.1))

    def test_signed_int_to_float32_rounding_precedes_division(self):
        job = schedule(frames=(1 << 24) + 1).job
        result = evaluate(job, 101)
        # SCVTF rounds both 16777217 and 16777216 to Float32 16777216.
        self.assertEqual(result.progress, 0.0)
        self.assertEqual(result.transparency, 1.0)
        self.assertFalse(result.completed)

    def test_final_write_precedes_deactivation_and_overshoot_is_not_clamped(self):
        job = schedule().job
        final = evaluate(job, 110)
        self.assertTrue(final.completed)
        self.assertEqual(final.commands, (
            SetFloat("renderer-1", "material-1", "_Transparent", 0.0),
            SetInactive("effect-1"),
        ))
        late = evaluate(job, 112)
        self.assertTrue(late.completed)
        self.assertEqual(bits(late.transparency), 0xBE4CCCD0)
        self.assertIsInstance(late.commands[0], SetFloat)
        self.assertEqual(late.commands[-1], SetInactive("effect-1"))

    def test_earlier_explicit_frame_is_not_saturated_or_reinterpreted(self):
        result = evaluate(schedule().job, 98)
        self.assertFalse(result.completed)
        self.assertEqual(bits(result.transparency), 0x3F99999A)

    def test_zero_and_negative_frames_do_not_divide_or_require_a_clock(self):
        for duration in (0, -1, -(1 << 31)):
            with self.subTest(duration=duration):
                result = schedule(frames=duration, at=None)
                self.assertIsNone(result.job)
                self.assertEqual(result.commands, (SetInactive("effect-1"),))
                self.assertEqual(schedule(frames=duration, at=None, alive=False).commands, ())
        with self.assertRaises(ValueError):
            FrameStopJob("effect-1", 100, 0)

    def test_empty_collection_stops_but_dead_entries_still_schedule(self):
        for count in (None, 0):
            result = schedule(count=count, at=None)
            self.assertIsNone(result.job)
            self.assertEqual(result.commands, (SetInactive("effect-1"),))
        job = schedule(count=1).job
        dead = (RendererObservation("destroyed", False, None),)
        self.assertEqual(evaluate(job, 105, dead).commands, ())
        self.assertEqual(evaluate(job, 110, dead).commands, (SetInactive("effect-1"),))

    def test_only_exact_particle_renderer_adds_its_live_trail_material(self):
        observed = (
            RendererObservation("ordinary", True, "body", False, "not-selected", True),
            RendererObservation("particle", True, "head", True, "trail", True),
            RendererObservation("dead-trail", True, "head-2", True, "dead", False),
            RendererObservation("dead-renderer", False, "unused", True, "unused-trail", True),
        )
        commands = evaluate(schedule(count=4).job, 105, observed).commands
        self.assertEqual([c.material_id for c in commands], ["body", "head", "trail", "head-2"])
        self.assertEqual({c.property_name for c in commands}, {"_Transparent"})
        self.assertTrue(all(c.value == 0.5 for c in commands))

    def test_same_material_in_two_native_getters_is_not_deduplicated(self):
        renderer = RendererObservation("particle", True, "shared", True, "shared", True)
        result = evaluate(schedule().job, 105, (renderer,))
        self.assertEqual(len(result.commands), 2)
        self.assertEqual(result.commands[0], result.commands[1])

    def test_dead_effect_does_not_skip_live_material_writes_or_invent_deactivate(self):
        result = evaluate(schedule().job, 110, alive=False)
        self.assertTrue(result.completed)
        self.assertEqual(result.commands, (SetFloat("renderer-1", "material-1", "_Transparent", 0.0),))

    def test_native_null_branches_are_not_silently_ignored(self):
        job = schedule().job
        with self.assertRaises(SourceNullReference):
            evaluate(job, 110, (RendererObservation("live", True, None),))
        with self.assertRaises(SourceNullReference):
            evaluate(job, 110, None)

    def test_int32_add_sub_and_signed_completion_are_retained_at_wrap(self):
        start = (1 << 31) - 4
        job = schedule(at=start).job
        self.assertEqual(job.end_frame, -(1 << 31) + 6)
        result = evaluate(job, start)
        self.assertEqual(result.transparency, 1.0)
        # Source compares signed values after wrapping, even at this boundary.
        self.assertTrue(result.completed)
        self.assertEqual(result.commands[-1], SetInactive("effect-1"))

    def test_nan_float_bool_and_out_of_range_values_are_not_integer_clocks(self):
        for value in (math.nan, math.inf, -math.inf, 100.0, True, 1 << 31, -(1 << 31) - 1):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    schedule(at=value)
                with self.assertRaises(ValueError):
                    schedule(frames=value)
                with self.assertRaises(ValueError):
                    evaluate(schedule().job, value)

    def test_direct_float32_callback_preserves_nonfinite_classification(self):
        self.assertTrue(math.isnan(callback_transparency(math.nan)))
        self.assertEqual(callback_transparency(math.inf), -math.inf)
        self.assertEqual(callback_transparency(-math.inf), math.inf)
        self.assertEqual(callback_transparency(1.5), -0.5)


@unittest.skipUnless(os.environ.get("ERLANG_EFFECT_STOP_NATIVE_DIR"),
                     "Pinned original native/metadata directory was not supplied")
class OriginalNativeReadbackChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = Path(os.environ["ERLANG_EFFECT_STOP_NATIVE_DIR"])

    def test_original_binary_hashes_method_ranges_and_registered_pointers(self):
        for key in ("native", "metadata"):
            record = EVIDENCE[key]
            path = self.directory / record["file"]
            self.assertEqual(path.stat().st_size, record["bytes"])
            with path.open("rb") as file:
                self.assertEqual(hashlib.file_digest(file, "sha256").hexdigest(), record["sha256"])
        with (self.directory / "UnityFramework").open("rb") as native, \
                (self.directory / "global-metadata.dat").open("rb") as metadata:
            for method in EVIDENCE["methods"]:
                with self.subTest(method=method["methodIndex"]):
                    native.seek(method["fileOffset"])
                    self.assertEqual(hashlib.sha256(native.read(method["bytes"])).hexdigest(), method["codeSHA256"])
                    cell = method["methodPointerCell"]
                    native.seek(cell["fileOffset"]); raw = native.read(cell["bytes"])
                    self.assertEqual(hashlib.sha256(raw).hexdigest(), cell["sha256"])
                    self.assertEqual(struct.unpack("<Q", raw)[0] & ((1 << 36) - 1), int(method["virtualAddress"], 16))
                    record = method["metadataRecord"]
                    metadata.seek(record["fileOffset"])
                    self.assertEqual(hashlib.sha256(metadata.read(record["bytes"])).hexdigest(), record["sha256"])
            for region in EVIDENCE["selectedGenericRanges"]:
                native.seek(region["fileOffset"])
                self.assertEqual(hashlib.sha256(native.read(region["bytes"])).hexdigest(), region["codeSHA256"])
            for binding in EVIDENCE["nativeAPIBindings"]:
                with self.subTest(api=binding["managedType"] + "." + binding["managedMethod"]):
                    cell = binding["methodPointerCell"]
                    native.seek(cell["fileOffset"]); raw = native.read(cell["bytes"])
                    self.assertEqual(hashlib.sha256(raw).hexdigest(), cell["sha256"])
                    self.assertEqual(struct.unpack("<Q", raw)[0] & ((1 << 36) - 1), int(binding["virtualAddress"], 16))
                    record = binding["metadataRecord"]
                    metadata.seek(record["fileOffset"])
                    self.assertEqual(hashlib.sha256(metadata.read(record["bytes"])).hexdigest(), record["sha256"])

    def test_exact_original_material_property_literal_and_usage_cell(self):
        material = EVIDENCE["materialProperty"]
        raw = (self.directory / "global-metadata.dat").read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), EVIDENCE["metadata"]["sha256"])
        self.assertEqual(struct.unpack_from("<II", raw), (0xFAB11BAF, 39))
        positions, _, count = struct.unpack_from("<III", raw, 8)
        data, size, _ = struct.unpack_from("<III", raw, 20)
        index = material["metadataLiteralIndex"]
        self.assertLess(index + 1, count)
        start, end = struct.unpack_from("<II", raw, positions + index * 4)
        self.assertTrue(0 <= start < end <= size)
        self.assertEqual(raw[data + start:data + end], b"_Transparent")
        with (self.directory / "UnityFramework").open("rb") as native:
            native.seek(material["metadataUsageFileOffset"])
            usage = native.read(material["metadataUsageBytes"])
        self.assertEqual(hashlib.sha256(usage).hexdigest(), material["metadataUsageSHA256"])
        word = struct.unpack("<Q", usage)[0]
        self.assertEqual((word >> 29) & 7, 5)
        self.assertEqual((word & 0x1FFFFFFF) >> 1, index)


@unittest.skipUnless(os.environ.get("ERLANG_EFFECT_STOP_SWORD_RECEIPT"),
                     "Pinned recovered sword source receipt was not supplied")
class OriginalSwordReceiptChecks(unittest.TestCase):
    def test_exact_receipt_keeps_ten_and_five_frame_actions_and_separate_delete(self):
        actions = load_sword_stop_contract(Path(os.environ["ERLANG_EFFECT_STOP_SWORD_RECEIPT"]))
        self.assertEqual(len(actions), 8)
        for index, frames, deletes in ((11, 10, False), (12, 5, True)):
            selected = [a for a in actions if a.source_trigger == index]
            self.assertEqual(tuple(a.effect_name for a in selected), SWORD_EFFECTS)
            self.assertEqual([a.source_action_index for a in selected], [0, 1, 2, 3])
            self.assertEqual({a.duration_frames for a in selected}, {frames})
            self.assertEqual({a.has_separate_model_delete_action for a in selected}, {deletes})

    def test_same_size_altered_receipt_cannot_change_duration_or_effect_identity(self):
        raw = Path(os.environ["ERLANG_EFFECT_STOP_SWORD_RECEIPT"]).read_bytes()
        changed = raw.replace(b"D15_HIDE_SWORDS", b"D15_FAKE_SWORDS", 1)
        self.assertNotEqual(raw, changed)
        self.assertEqual(len(raw), len(changed))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "changed.json"; path.write_bytes(changed)
            with self.assertRaisesRegex(ValueError, "identity differs"):
                load_sword_stop_contract(path)


if __name__ == "__main__":
    unittest.main()
