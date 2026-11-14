#!/usr/bin/env python3
"""Synthetic release checks; no original mesh, texture or character data."""
import copy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import build_sun_triad_release as release


def projected_fixture():
    return dict(
        complete=True,
        stage=dict(file="Synthetic.glb", bytes=128, sha256="a" * 64,
                   rootNode="stage", rootTranslation=[0, 0, 0], rootScale=[1, 1, 1]),
        receiver=dict(node="receiver", nodeIndex=1, ancestorChain=[
            dict(nodeIndex=1, name="receiver", translation=[0, 0, 0], rotation=[0, 0, 0, 1], scale=[1, 1, 1]),
            dict(nodeIndex=0, name="stage", translation=[0, 0, 0], rotation=[0, 0, 0, 1], scale=[1, 1, 1])],
            geometry=dict(positions=[[0, 0, 0], [1, 0, 0], [0, 0, 1]], indices=[0, 2, 1]),
            sourceMeshSHA256="b" * 64, sourceMaterialSHA256="c" * 64, renderQueue=2501),
        settings=dict(useAdaptiveShadowScale=False, targetTextureFill=.5, minCameraSize=10,
                      cinematic=False, useDynamicPositionBetweenPlayerAndEnemy=True),
        sourceLocation=dict(projectorPosition=[0, 2, 0], projectorRotationDegrees=[45, 0, 0],
                            shadowColor=[.25, .4, .5, 1]),
        camera=dict(orthographic=True, orthographicSize=10, nearClip=5, farClip=30, targetDistance=10,
                    projectionBiasColumnMajor=[.5, 0, 0, 0, 0, .5, 0, 0, 0, 0, .5, 0, .5, .5, .5, .5],
                    dividesProjectedUVByW=False, halfProjectionRows=True, halfProjectedUV=True, aspectSource="screen",
                    follow=dict(source="actorCenterOfMassWorldXYZ", midpoint=True, positionUsesPreviousForward=True,
                                rotationAfterPosition=True, initialRotationQuaternion=[0, 0, 0, 1])),
        map=dict(width=64, height=64, sourceFormatPriority=["R8", "RGB565", "ARGB32"], depthBits=0,
                 sampleCount=1, filter=1, wrapS=1, wrapT=1, clearColor=[1, 1, 1, 1], projectColorSpace=0,
                 drawOrder=["firstActor", "secondActor", "additionalModels", "extraRenderers"]),
        blur=dict(passes=1, offsets=[[-1, 1], [-.8, -.8], [0, 0], [.8, .8], [1, -1]],
                  weights=[.2] * 5, sampleChannel="red", replicateRedToRGBA=True),
        raster=dict(source=2, destination=0, zWrite=False, zTest=4, cull=2),
        evidence=["Synthetic projector fixture; not installed-source evidence."])


def contract_pin(value):
    payload = {key: row for key, row in value.items() if key != "evidence"}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"),
                                    ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def morph_fixture():
    owner = dict(id="sun_triad", sha256="d" * 64,
                 triadRules=dict(runtime=dict(configurationSHA256="e" * 64)),
                 clips=[dict(name="h17_stance_win", frames=162, sha256="f" * 64,
                             tracks=dict(pelvis=[[0, 1, 0]] * 323))])
    target = dict(id="liu_hammers", sha256="0" * 64, clips=[])
    materials = [
        dict(name="mat_arm__str_03_base", sourceItemType=2, actorBaseGeometry=False, tile=.2, edgeSize=.1,
             edgeStart=[0, 0, 0, 1], edgeEnd=[0, 87 / 255, 96 / 255, 1]),
        dict(name="mat_wpn__hammers_01_01_base", sourceItemType=3, actorBaseGeometry=False, tile=.1, edgeSize=.1,
             edgeStart=[0, 26 / 255, 146 / 255, 1], edgeEnd=[0, 237 / 255, 244 / 255, 1])]
    for name in ("Liu_Neck_Skin", "tripo_mat_c4757646"):
        materials.append(dict(name=name, sourceItemType=None, actorBaseGeometry=True, tile=.2, edgeSize=.1,
                              edgeStart=[0, 0, 0, 1], edgeEnd=[0, 87 / 255, 96 / 255, 1]))
    document = dict(version=2, ownerProfileID=owner["id"], ownerCharacterSHA256=owner["sha256"],
                    targetProfileID=target["id"], targetCharacterSHA256=target["sha256"],
                    sourceConfigurationSHA256=owner["triadRules"]["runtime"]["configurationSHA256"],
                    trigger=dict(clip="h17_stance_win", sourceClipSHA256="f" * 64,
                                 sourceFrame=36, triggerTick=70, transitionTicks=140, normalRenderBoundaries=1),
                    mask=copy.deepcopy(release.MORPH_MASK), materials=materials,
                    evidence=["Synthetic actor identity fixture."], projectedShadow=projected_fixture())
    return document, owner, target


def change(document, path, value):
    target = document
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value


class ProjectedShadowTests(unittest.TestCase):
    def test_bounded_fixture_is_valid_but_cannot_impersonate_palace_source(self):
        document = projected_fixture()
        release.validate_projected_shadow(document, require_palace=False)
        with self.assertRaisesRegex(ValueError, "Palace.*mismatch"):
            release.validate_projected_shadow(document)

    def test_incomplete_or_unsupported_shader_camera_and_sampler_are_rejected(self):
        cases = [
            (("complete",), False), (("complete",), 1),
            (("camera", "dividesProjectedUVByW"), True),
            (("camera", "halfProjectionRows"), False),
            (("camera", "aspectSource"), "shadowMap"),
            (("camera", "follow", "source"), "pelvis"),
            (("camera", "follow", "positionUsesPreviousForward"), False),
            (("camera", "follow", "rotationAfterPosition"), False),
            (("camera", "projectionBiasColumnMajor", 15), 1),
            (("map", "sourceFormatPriority"), ["ARGB32", "R8", "RGB565"]),
            (("map", "depthBits"), 24), (("map", "sampleCount"), 4),
            (("map", "filter"), 0), (("map", "wrapT"), 0),
            (("map", "filter"), True), (("map", "projectColorSpace"), 1),
            (("map", "clearColor"), [0, 0, 0, 0]),
            (("map", "drawOrder"), ["secondActor", "firstActor", "additionalModels", "extraRenderers"]),
            (("blur", "passes"), 2), (("blur", "sampleChannel"), "alpha"),
            (("blur", "offsets", 1), [-1, -1]),
            (("raster", "source"), 5), (("raster", "zWrite"), True)]
        for path, value in cases:
            with self.subTest(path=path, value=value):
                document = projected_fixture()
                change(document, path, value)
                with self.assertRaises(ValueError):
                    release.validate_projected_shadow(document, require_palace=False)

    def test_malformed_geometry_or_hierarchy_never_reaches_renderer(self):
        cases = [
            (("receiver", "geometry", "positions", 1, 0), float("nan")),
            (("receiver", "geometry", "positions", 1), [1, 0]),
            (("receiver", "geometry", "indices", 1), 3),
            (("receiver", "geometry", "indices", 1), -1),
            (("receiver", "geometry", "indices", 1), True),
            (("receiver", "ancestorChain", 1, "nodeIndex"), 1),
            (("receiver", "ancestorChain", 0, "scale"), [0, 1, 1]),
            (("receiver", "ancestorChain", 0, "rotation"), [0, 0, 0, 2]),
            (("receiver", "ancestorChain", 1, "translation"), [1, 0, 0]),
            (("stage", "file"), "../other.glb"),
            (("stage", "bytes"), True)]
        for path, value in cases:
            with self.subTest(path=path):
                document = projected_fixture()
                change(document, path, value)
                with self.assertRaises(ValueError):
                    release.validate_projected_shadow(document, require_palace=False)

    def test_source_digest_also_binds_vertices_winding_transforms_color_and_camera(self):
        source = projected_fixture()
        # Substitute only this fixture's authority pin. Its generic identities
        # cannot satisfy the unmodified production pin in the first test.
        with patch.object(release, "PALACE_PROJECTED_SHADOW_SHA256", contract_pin(source)):
            release.validate_projected_shadow(source)
            for path, value in [
                (("receiver", "geometry", "positions", 1, 0), .01),
                (("receiver", "geometry", "indices"), [0, 1, 2]),
                (("receiver", "ancestorChain", 0, "translation"), [5, 0, 0]),
                (("sourceLocation", "shadowColor"), [.5, .5, .5, 1]),
                (("camera", "targetDistance"), 12),
                (("settings", "targetTextureFill"), .6)]:
                with self.subTest(path=path):
                    changed = copy.deepcopy(source)
                    change(changed, path, value)
                    release.validate_projected_shadow(changed, require_palace=False)
                    with self.assertRaisesRegex(ValueError, "Palace.*mismatch"):
                        release.validate_projected_shadow(changed)

    def test_evidence_can_be_clarified_but_is_bounded_by_utf8_bytes(self):
        document = projected_fixture()
        with patch.object(release, "PALACE_PROJECTED_SHADOW_SHA256", contract_pin(document)):
            document["evidence"] = ["澄" * 341 + "a"]  # Exactly 1024 UTF-8 bytes.
            release.validate_projected_shadow(document)
            document["evidence"][0] += "a"
            with self.assertRaisesRegex(ValueError, "evidence"):
                release.validate_projected_shadow(document)

    def test_unknown_projector_fields_are_not_silently_ignored(self):
        document = projected_fixture()
        document["map"]["useMorphMask"] = True
        with self.assertRaisesRegex(ValueError, "map fields"):
            release.validate_projected_shadow(document, require_palace=False)


class MorphAssemblyTests(unittest.TestCase):
    def test_new_release_requires_complete_v2_while_history_can_be_read_explicitly(self):
        document, owner, target = morph_fixture()
        with patch.object(release, "PALACE_PROJECTED_SHADOW_SHA256", contract_pin(document["projectedShadow"])):
            release.validate_morph_document(document, owner, target)
            document["projectedShadow"]["complete"] = False
            with self.assertRaises(ValueError):
                release.validate_morph_document(document, owner, target)
        document.pop("projectedShadow")
        document["version"] = 1
        before = copy.deepcopy(document)
        with self.assertRaisesRegex(ValueError, "schema"):
            release.validate_morph_document(document, owner, target)
        release.validate_morph_document(document, owner, target, allow_legacy=True)
        self.assertEqual(document, before)

    def test_candidate_file_is_bounded_and_mask_bytes_are_authenticated(self):
        document, owner, target = morph_fixture()
        texture = b"synthetic texture bytes"
        mask = dict(document["mask"], bytes=len(texture), sha256=hashlib.sha256(texture).hexdigest())
        document["mask"] = mask
        with TemporaryDirectory() as directory, \
                patch.object(release, "PALACE_PROJECTED_SHADOW_SHA256", contract_pin(document["projectedShadow"])), \
                patch.object(release, "MORPH_MASK", mask):
            path = Path(directory) / "SF3_H17_Morph.json"
            path.write_text(json.dumps(document))
            texture_path = path.parent / mask["file"]
            texture_path.write_bytes(texture)
            self.assertEqual(release.read_morph_candidate(path, owner, target), document)
            texture_path.write_bytes(b"replacement texture")
            with self.assertRaisesRegex(ValueError, "mask bytes mismatch"):
                release.read_morph_candidate(path, owner, target)
            path.write_bytes(b"x" * (release.MORPH_DOCUMENT_MAX_BYTES + 1))
            with self.assertRaisesRegex(ValueError, "candidate file"):
                release.read_morph_candidate(path, owner, target)

    def test_historical_release_output_is_rejected_before_any_input_read_or_write(self):
        with TemporaryDirectory() as directory:
            output = Path(directory) / "release-history"
            output.mkdir()
            sentinel = output / "SF3_FighterRelease.json"
            sentinel.write_bytes(b"immutable previous release")
            with self.assertRaisesRegex(ValueError, "preserve historical releases"):
                release.build(SimpleNamespace(output=output))
            self.assertEqual(sentinel.read_bytes(), b"immutable previous release")
            self.assertEqual(list(output.iterdir()), [sentinel])

    def test_existing_receipt_is_rejected_before_release_assembly(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            receipt = root / "historical-receipt.json"
            receipt.write_bytes(b"immutable previous receipt")
            arguments = ["builder", "--candidate", str(root / "candidate"),
                         "--legacy-catalog", str(root / "baseline.json"),
                         "--output", str(root / "release"), "--receipt", str(receipt)]
            with patch("sys.argv", arguments), patch.object(release, "build") as build:
                with self.assertRaisesRegex(ValueError, "preserve historical receipts"):
                    release.main()
                build.assert_not_called()
            self.assertEqual(receipt.read_bytes(), b"immutable previous receipt")
            self.assertFalse((root / "release").exists())

    def test_invalid_morph_preflight_cannot_write_a_partial_catalog(self):
        document, owner, target = morph_fixture()
        document["version"] = 1
        document.pop("projectedShadow")
        with TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "candidate"
            (candidate / "runtime").mkdir(parents=True)
            (candidate / "shadow-recovery").mkdir()
            (candidate / "runtime/SF3_Triad_Profile.json").write_text(json.dumps(owner))
            (candidate / "runtime/SF3_Liu_Profile.json").write_text(json.dumps(target))
            (candidate / "shadow-recovery/SF3_H17_Morph.json").write_text(json.dumps(document))
            catalog = root / "baseline.json"
            catalog.write_text(json.dumps(dict(profiles=[target])))
            output = root / "fresh-release"
            with patch.object(release, "LEGACY_CATALOG_SHA256", release.digest(catalog)):
                with self.assertRaisesRegex(ValueError, "schema"):
                    release.build(SimpleNamespace(output=output, candidate=candidate, legacy_catalog=catalog))
            self.assertTrue(output.is_dir())
            self.assertEqual(list(output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
