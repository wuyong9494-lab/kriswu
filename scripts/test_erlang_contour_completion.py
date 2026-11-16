"""Real private-input checks for source-preserving D15 contour integration."""
import argparse
import copy
import gzip
import io
import json
import os
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

from bind_erlang_personal_neck import bind, RECOVERED_PROFILE_SHA
from build_erlang_source_assets import sha
from recover_erlang_source_audio import NECK_PROFILE_SHA, NECK_CHARACTER_SHA
from rebind_erlang_contour_media import CONTOUR_PROFILE_SHA, CONTOUR_CHARACTER_SHA, INPUTS, equivalent_profiles
from sun_triad_assets import accessor_read, glb_read, world_poses


class ErlangContourCompletionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        old, work = os.getenv('FIGHTER_ERLANG_RECOVERY_ROOT'), os.getenv('FIGHTER_ERLANG_WORK_ROOT')
        if not old or not work:
            raise unittest.SkipTest('Real authenticated recovered actor and media are required')
        cls.work = Path(work)
        cls.original_profile_path = Path(old)/'work-products/erlang-runtime-v3/SF3_Erlang_Recovered_Runtime_Profile.json'
        cls.original_profile = json.loads(cls.original_profile_path.read_bytes())
        cls.directory = cls.work/'erlang-neck-v2-final'
        cls.profile = json.loads((cls.directory/'SF3_Erlang_Profile.json').read_bytes())
        cls.prior = json.loads((cls.work/'erlang-neck-v1/SF3_Erlang_Profile.json').read_bytes())
        cls.g0, cls.b0 = glb_read(cls.original_profile_path.parent/(cls.original_profile['resourceName']+'.glb'))
        cls.g1, cls.b1 = glb_read(cls.directory/(cls.profile['resourceName']+'.glb'))
        cls.receipt = json.loads((cls.directory/'erlang-personal-neck-bridge-private.json').read_bytes())
        cls.proof = cls.receipt['material']
        cls.primitive = cls.g1['meshes'][-1]['primitives'][0]
        cls.positions = accessor_read(cls.g1, cls.b1, cls.primitive['attributes']['POSITION'])
        cls.joints = accessor_read(cls.g1, cls.b1, cls.primitive['attributes']['JOINTS_0'])
        cls.weights = accessor_read(cls.g1, cls.b1, cls.primitive['attributes']['WEIGHTS_0'])
        cls.placement = np.asarray(cls.receipt['generatedGeometry']['bridgeToOriginalActorBindSpace'])
        cls.head_space = (np.c_[cls.positions, np.ones(len(cls.positions))] @ np.linalg.inv(cls.placement).T)[:, :3]

    def test_all_original_portrait_bytes_skin_and_62_animations_are_immutable(self):
        self.assertEqual(sha(self.original_profile_path.read_bytes()), RECOVERED_PROFILE_SHA)
        self.assertEqual(sha((self.directory/'SF3_Erlang_Profile.json').read_bytes()), CONTOUR_PROFILE_SHA)
        self.assertEqual(self.profile['sha256'], CONTOUR_CHARACTER_SHA)
        length = self.g0['buffers'][0]['byteLength']
        self.assertEqual(length, 16324652)
        self.assertEqual(self.b1[:length], self.b0[:length])
        for field in ('accessors', 'bufferViews', 'meshes', 'materials', 'images', 'textures', 'samplers'):
            self.assertEqual(self.g1[field][:len(self.g0[field])], self.g0[field])
        self.assertEqual(self.g1['animations'], self.g0['animations'])
        self.assertEqual(len(self.g1['animations']), 62)
        self.assertEqual(self.g1['skins'], self.g0['skins'])
        self.assertEqual(self.g1['nodes'][87], self.g0['nodes'][87])
        self.assertEqual(self.g0['accessors'][43]['count'], 59878)
        for field in ('clips', 'roles', 'ordinaryThrows', 'combatRules', 'erlangRules', 'summonTracks'):
            self.assertEqual(self.profile[field], self.original_profile[field])

    def test_every_authentic_head_edge_is_closed_without_quantized_topology(self):
        original = self.g0['meshes'][self.g0['nodes'][87]['mesh']]['primitives'][0]
        vertices = accessor_read(self.g0, self.b0, original['attributes']['POSITION'])
        faces = accessor_read(self.g0, self.b0, original['indices']).reshape(-1, 3)
        unique, inverse = np.unique(vertices, axis=0, return_inverse=True)
        triangles = inverse[faces]
        all_edges = np.sort(np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]]), axis=1)
        edges, counts = np.unique(all_edges, axis=0, return_counts=True)
        boundary = edges[counts == 1]
        self.assertEqual(len(boundary), 182)
        self.assertEqual(len(np.unique(boundary)), 181)
        distance, mapped = cKDTree(unique).query(self.head_space)
        actual = set()
        for primitive in self.g1['meshes'][-1]['primitives']:
            for face in accessor_read(self.g1, self.b1, primitive['indices']).reshape(-1, 3):
                for a, b in zip(face, np.roll(face, -1)):
                    if distance[a] < 2e-6 and distance[b] < 2e-6:
                        actual.add(tuple(sorted((int(mapped[a]), int(mapped[b])))))
        self.assertTrue(set(map(tuple, boundary)).issubset(actual))
        self.assertFalse(self.proof['contour']['positionQuantizationUsed'])
        self.assertEqual(self.proof['opening']['mainOpeningHalfEdges'], 172)
        self.assertEqual(self.proof['opening']['localHoleHalfEdges'], 10)
        self.assertEqual(self.proof['opening']['localHoleTriangles'], 8)
        self.assertTrue(self.proof['opening']['localHoleUsesOriginalPortraitMaterialAndUV'])

    def test_real_collar_boundary_copies_complete_source_skin_attributes(self):
        original = self.g0['meshes'][self.g0['nodes'][80]['mesh']]['primitives'][0]
        attrs = {name: accessor_read(self.g0, self.b0, accessor) for name, accessor in original['attributes'].items()}
        self.assertEqual(self.proof['collar']['sourceBoundaryVertices'], 15)
        source_edges = self.proof['collar']['sourceEdges']
        self.assertEqual(len(source_edges), 15)
        source_faces = accessor_read(self.g0, self.b0, original['indices']).reshape(-1, 3)
        for edge in source_edges:
            self.assertTrue(set(edge['sourceVertexIndices']).issubset(source_faces[edge['triangle']]))
        for row in self.proof['bodyBoundarySourceCopies']:
            new, old = row['vertex'], row['sourceVertex']
            np.testing.assert_array_equal(self.positions[new], attrs['POSITION'][old])
            np.testing.assert_array_equal(self.joints[new], attrs['JOINTS_0'][old])
            np.testing.assert_array_equal(self.weights[new], attrs['WEIGHTS_0'][old])
        np.testing.assert_allclose(self.weights.sum(axis=1), 1, atol=1e-7)
        self.assertTrue((self.weights >= 0).all())
        self.assertLess(self.proof['maximumDiscardedCollarWeight'], .01)
        # The construction row is not rendered. Every rendered interior ring
        # progresses toward the original opening without a vertical fold.
        rows = self.head_space[:3096].reshape(9, 344, 3)
        self.assertTrue((np.diff(rows[:, :, 1], axis=0) >= -2e-7).all())

    def test_source_head_normals_and_both_sides_of_uv_islands_are_preserved(self):
        start, count = self.proof['topRingOffset'], self.proof['ringVertexCount']
        self.assertEqual((start, count), (2752, 344))
        normals = accessor_read(self.g1, self.b1, self.primitive['attributes']['NORMAL'])[start:start+count] @ self.placement[:3, :3]
        normals /= np.linalg.norm(normals, axis=1)[:, None]
        expected = np.asarray(self.proof['sourceHeadNormals'])
        expected = np.stack([expected, np.roll(expected, -1, axis=0)], axis=1).reshape(-1, 3)
        np.testing.assert_allclose(normals, expected, atol=2e-6)
        self.assertTrue((self.joints[start:start+count, 0] == 6).all())
        self.assertTrue((self.weights[start:start+count, 0] == 1).all())
        def pixels(g, binary, texture_index):
            definition = g['images'][g['textures'][texture_index]['source']]
            view = g['bufferViews'][definition['bufferView']]; offset = view.get('byteOffset', 0)
            return np.asarray(Image.open(io.BytesIO(binary[offset:offset+view['byteLength']])).convert('RGB'), dtype=float)/255
        source_material = self.g0['materials'][3]['pbrMetallicRoughness']
        source = pixels(self.g0, self.b0, source_material['baseColorTexture']['index'])
        source = np.where(source <= .04045, source/12.92, ((source+.055)/1.055)**2.4)
        original_uv = np.stack([self.proof['sourceHeadUV'], self.proof['sourceHeadEdgeEndUV']], axis=1).reshape(-1, 2)
        xy = original_uv*np.array([source.shape[1], source.shape[0]])-.5
        ij = np.floor(xy).astype(int); delta = xy-ij
        a, b = ij[:, 0] % source.shape[1], ij[:, 1] % source.shape[0]
        c, d = (ij[:, 0]+1) % source.shape[1], (ij[:, 1]+1) % source.shape[0]
        expected = ((source[b, a]*(1-delta[:, 0, None])+source[b, c]*delta[:, 0, None])*(1-delta[:, 1, None]) +
                    (source[d, a]*(1-delta[:, 0, None])+source[d, c]*delta[:, 0, None])*delta[:, 1, None])
        expected = np.where(expected <= .0031308, expected*12.92, 1.055*expected**(1/2.4)-.055)
        material = self.g1['materials'][self.primitive['material']]['pbrMetallicRoughness']
        atlas = pixels(self.g1, self.b1, material['baseColorTexture']['index'])
        uv = accessor_read(self.g1, self.b1, self.primitive['attributes']['TEXCOORD_0'])[start:start+count]
        indices = np.round(uv*np.array([atlas.shape[1], atlas.shape[0]])-.5).astype(int)
        actual = atlas[indices[:, 1], indices[:, 0]]
        self.assertLessEqual(float(np.max(abs(expected-actual))), 1/255)
        self.assertEqual(self.proof['originalUVIslandJunctions'], 15)

    def test_actual_62_animations_have_matching_head_and_body_boundaries(self):
        receipt = json.loads((self.directory/'source-boundary-poses-private.json').read_bytes())
        self.assertEqual(receipt['characterSHA256'], CONTOUR_CHARACTER_SHA)
        self.assertEqual((receipt['sourceAnimations'], receipt['evaluatedPoses']), (62, 186))
        self.assertLess(receipt['maximumHeadDistanceMeters'], 2e-6)
        self.assertEqual(receipt['maximumBodyDistanceMeters'], 0)
        self.assertFalse(receipt['originalObjectTransformsManuallyChanged'])
        self.assertFalse(receipt['nativeMetalOrFinalAppearanceAcceptance'])

    def test_equivalent_media_keep_all_original_bytes_clocks_and_omissions(self):
        runtime = self.work/'erlang-runtime-contour-v2'
        equivalent_profiles(self.prior, self.profile)
        for kind, (directory, name, digest, count) in INPUTS.items():
            raw = (self.work/directory/name).read_bytes(); self.assertEqual(sha(raw), digest)
            prior = json.loads(gzip.decompress(raw) if name.endswith('.gz') else raw)
            current = json.loads((runtime/name.removesuffix('.gz')).read_bytes())
            self.assertEqual(current['characterSHA256'], CONTOUR_CHARACTER_SHA)
            current['characterSHA256'] = prior['characterSHA256']
            if kind == 'audio':
                self.assertEqual(current['profileSHA256'], CONTOUR_PROFILE_SHA)
                current['profileSHA256'] = prior['profileSHA256']
            self.assertEqual(current, prior)
            self.assertEqual(len(prior['files']), count)
            for row in prior['files']:
                data = (runtime/row['name']).read_bytes()
                self.assertEqual(data, (self.work/directory/row['name']).read_bytes())
                self.assertEqual((len(data), sha(data)), (row['bytes'], row['sha256']))
        changed = copy.deepcopy(self.profile)
        changed['summonTracks'][0]['root'][0][0] += .001
        with self.assertRaises(ValueError): equivalent_profiles(self.prior, changed)
        changed = copy.deepcopy(self.profile)
        changed['personalNeckBridge']['dynamicBodyVertexAttributesPreserved'] = False
        with self.assertRaises(ValueError): equivalent_profiles(self.prior, changed)

    def test_legacy_neck_entry_still_produces_exact_v1_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary)/'candidate'
            bind(argparse.Namespace(profile=self.original_profile_path, profile_sha256=RECOVERED_PROFILE_SHA,
                output=destination, recovered_source=True, source_contour=False))
            self.assertEqual(sha((destination/'SF3_Erlang_Profile.json').read_bytes()), NECK_PROFILE_SHA)
            self.assertEqual(sha((destination/(self.profile['resourceName']+'.glb')).read_bytes()), NECK_CHARACTER_SHA)


if __name__ == '__main__':
    unittest.main()
