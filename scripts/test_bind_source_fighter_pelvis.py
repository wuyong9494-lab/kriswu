#!/usr/bin/env python3
"""Synthetic checks for pelvis coordinates and non-destructive profile merges."""
import base64
import copy
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from bind_source_fighter_pelvis import bind, digest, pelvis_samples, without_pelvis
from sun_triad_assets import Writer


def fixture():
    writer = Writer()
    writer.g["nodes"] = [
        dict(name="actor", children=[1], translation=[3, 4, 5], scale=[.92, .92, .92]),
        dict(name="armature", children=[2]), dict(name="pelvis")]
    writer.g["scenes"][0]["nodes"] = [0]
    times = writer.acc([0, 1 / 30], "SCALAR")
    animation = dict(name="synthetic", channels=[], samplers=[],
                     extras=dict(sourceSHA256=digest(b"original synthetic motion"), sourceFrames=2))
    for node, kind, values, width in (
        (2, "translation", [[0, 1, 0], [0, 2, 0]], "VEC3"),
        (1, "rotation", [[0, 0, 0, 1], [0, 0, 1, 0]], "VEC4")):
        animation["channels"].append(dict(sampler=len(animation["samplers"]), target=dict(node=node, path=kind)))
        animation["samplers"].append(dict(input=times, output=writer.acc(values, width), interpolation="LINEAR"))
    writer.g["animations"] = [animation]
    return writer, animation


class PelvisTests(unittest.TestCase):
    def test_half_frame_uses_parent_rotation_actor_scale_and_right_basis(self):
        writer, animation = fixture()
        before = copy.deepcopy(writer.g)
        actual = pelvis_samples(writer.g, bytes(writer.b), animation, 2, 2)
        # At the half-frame, a 90-degree parent turn rotates the interpolated
        # 1.5m pelvis to -X before the single .92 scale and RIGHT projection.
        np.testing.assert_allclose(actual, [[-5, 4.92, 3], [-5, 4, 1.62], [-5, 2.16, 3]], atol=1e-7)
        self.assertEqual(writer.g, before)

    def test_antipodal_quaternions_do_not_collapse_the_half_frame(self):
        writer, animation = fixture()
        animation["samplers"][1]["output"] = writer.acc([[0, 0, 0, 1], [0, 0, 0, -1]], "VEC4")
        actual = pelvis_samples(writer.g, bytes(writer.b), animation, 2, 2)
        np.testing.assert_allclose(actual[1], [-5, 5.38, 3], atol=1e-7)

    def make_profiles(self, directory):
        root = Path(directory)
        writer, animation = fixture()
        model = root / "Synthetic.glb"
        pin = writer.save(model)
        clip = dict(name="synthetic", frames=2, sha256=animation["extras"]["sourceSHA256"], bundle="synthetic",
                    sourceBytesBase64=base64.b64encode(b"original synthetic motion").decode(),
                    tracks=dict(samplesPerSourceFrame=2, root=[[0, 0, 0]] * 3,
                                groundLift=[.1, .2, .3], centerOfMass=[[9, 8, 7]] * 3))
        source = dict(id="synthetic", resourceName="Synthetic", **pin, clips=[clip],
                      sourceBoneBindings=[dict(name="pelvis", targetNode=2, sourceID=0)])
        runtime = copy.deepcopy(source)
        runtime.pop("sourceBoneBindings")
        runtime["unrelatedRules"] = dict(marker="retain exactly", values=[1, None, False])
        source_path, runtime_path = root / "source.json", root / "runtime.json"
        source_path.write_text(json.dumps(source))
        runtime_path.write_text(json.dumps(runtime))
        return source_path, runtime_path, root / "receipt.json", model

    def test_merge_changes_only_pelvis_and_preserves_source_and_character_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            source, runtime, receipt, model = self.make_profiles(directory)
            old_source, old_model = source.read_bytes(), model.read_bytes()
            before = json.loads(runtime.read_text())
            summary = bind(source, runtime, receipt)
            after = json.loads(runtime.read_text())
            self.assertEqual(without_pelvis(after), before)
            self.assertEqual(after["clips"][0]["tracks"]["pelvis"][1], [-5, 4, 1.62])
            self.assertEqual(source.read_bytes(), old_source)
            self.assertEqual(model.read_bytes(), old_model)
            self.assertEqual(summary["samples"], 3)
            self.assertEqual(summary["runtimeProfileSHA256"], digest(runtime.read_bytes()))

    def test_changed_source_motion_or_existing_runtime_tracks_are_rejected_before_write(self):
        for changed_source in (True, False):
            with self.subTest(changed_source=changed_source), tempfile.TemporaryDirectory() as directory:
                source, runtime, receipt, _ = self.make_profiles(directory)
                path = source if changed_source else runtime
                document = json.loads(path.read_text())
                if changed_source:
                    document["clips"][0]["sourceBytesBase64"] = base64.b64encode(b"different motion").decode()
                else:
                    document["clips"][0]["tracks"]["centerOfMass"][0][1] = 999
                path.write_text(json.dumps(document))
                before = runtime.read_bytes()
                with self.assertRaises(ValueError):
                    bind(source, runtime, receipt)
                self.assertEqual(runtime.read_bytes(), before)
                self.assertFalse(receipt.exists())


if __name__ == "__main__":
    unittest.main()
