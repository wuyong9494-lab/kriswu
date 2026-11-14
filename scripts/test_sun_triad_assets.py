#!/usr/bin/env python3
"""Synthetic regressions for exact bone/capsule binding and glTF skin layout."""
import copy
import tempfile
import unittest
from pathlib import Path
import numpy as np
from sun_triad_source_bones import parse_bones_data, merge_bone_ids, capsule_binding
from sun_triad_assets import Writer, capsule_point, skin_slots, validate_container, private_output, REPOSITORY
from sun_triad_materials import paint_rgba

XML = b'''<BonesData><Bones><Bone Name="left_blade" ID="200"/>
<Bone Name="left_tip" ID="201"/></Bones>
<Mirroring><Bone Name="left_blade" ID="999"/></Mirroring>
<Vertexes><Vertex Name="a" BoneName="left_blade" LocalPosition="10 20 30"/>
<Vertex Name="b" BoneName="left_tip" LocalPosition="0 0 0"/></Vertexes>
<Capsules><Capsule Name="Synthetic_edge_l" Vertex1="a" Vertex2="b" Radius="4" Defense="HeadDefense"/></Capsules></BonesData>'''


class SourceBonesTests(unittest.TestCase):
    def test_mirror_instructions_do_not_reassign_motion_ids(self):
        source=parse_bones_data(XML)
        self.assertEqual(source['bones'],{200:'left_blade',201:'left_tip'})
        self.assertEqual(capsule_binding(source['capsules'][0],'attack'),
            dict(id='Synthetic_edge_l',radiusMillimeters=40,side='left'))
        self.assertEqual(capsule_binding(source['capsules'][0],'hurt')['defense'],'head')

    def test_duplicate_ids_and_cross_source_conflicts_fail_closed(self):
        with self.assertRaisesRegex(ValueError,'Duplicate'):
            parse_bones_data(XML.replace(b'ID="201"',b'ID="200"'))
        source=parse_bones_data(XML)
        with self.assertRaisesRegex(ValueError,'conflict'):
            merge_bone_ids(source,dict(bones={200:'unrelated_bone'}))

    def test_bad_source_vertex_and_entity_are_rejected(self):
        for invalid in (XML.replace(b'Vertex2="b"',b'Vertex2="missing"'),
                        XML.replace(b'10 20 30',b'10 nan 30'),
                        b'<!DOCTYPE BonesData [<!ENTITY x SYSTEM "file:///tmp/absent">]>'+XML):
            with self.assertRaises(ValueError):parse_bones_data(invalid)

    def test_capsule_uses_exact_local_endpoint_and_coordinate_basis(self):
        vertex=parse_bones_data(XML)['capsules'][0]['base']
        world=np.eye(4)[None,:,:];world[0,:3,3]=[1,2,3]
        # cm->m, Unity z reflection, then the same right-facing basis as limb tracks.
        np.testing.assert_allclose(capsule_point(vertex,world,{'left_blade':0}),[-2.7,2.2,1.1])


class ExportStructureTests(unittest.TestCase):
    def test_three_source_influences_are_preserved_with_one_zero_lane(self):
        joints,weights=skin_slots(np.array([[4,7,9]]),np.array([[.25,.5,.25]]))
        self.assertEqual(joints.tolist(),[[4,7,9,0]])
        self.assertEqual(weights.tolist(),[[.25,.5,.25,0.]])
        writer=Writer();index=writer.acc(joints,'VEC4',5123)
        self.assertEqual(writer.g['bufferViews'][writer.g['accessors'][index]['bufferView']]['byteLength'],8)

    def test_writer_rejects_three_lane_vec4_and_nonfinite_accessor(self):
        writer=Writer()
        with self.assertRaisesRegex(ValueError,'shape'):writer.acc([[1,2,3]],'VEC4',5123)
        with self.assertRaisesRegex(ValueError,'nonfinite'):writer.acc([[1,float('nan'),3]],'VEC3')

    def test_container_rejects_external_resource_and_short_accessor(self):
        writer=Writer();writer.acc([[1.,2.,3.]],'VEC3');writer.g['buffers']=[dict(byteLength=len(writer.b))]
        validate_container(writer.g,writer.b)
        broken=copy.deepcopy(writer.g);broken['buffers'][0]['uri']='../outside.bin'
        with self.assertRaisesRegex(ValueError,'self contained'):validate_container(broken,writer.b)
        broken=copy.deepcopy(writer.g);broken['accessors'][0]['count']=2
        with self.assertRaisesRegex(ValueError,'exceeds'):validate_container(broken,writer.b)

    def test_private_output_rejects_repository_and_symlink(self):
        with self.assertRaisesRegex(ValueError,'outside'):private_output(REPOSITORY/'private-test-output')
        with tempfile.TemporaryDirectory() as d:
            link=Path(d)/'linked';link.symlink_to(Path(d))
            with self.assertRaisesRegex(ValueError,'symlink'):private_output(link)


class SourcePaletteTests(unittest.TestCase):
    def test_overlapping_source_paints_are_ordered_and_preserve_alpha(self):
        # Three masks overlap on one texel, including a half-strength second
        # paint. Their coverage must not replace or darken texture alpha.
        image=np.array([[[.8,.6,.4,.3]]])
        masks=[np.array([[1.]]),np.array([[.5]]),np.array([[.25]])]
        palette=[[.5,1,1,1],[1,.5,1,1],[1,1,0,1]]
        np.testing.assert_allclose(paint_rgba(image,masks,palette),[[[.4,.45,.3,.3]]])
        np.testing.assert_allclose(image,[[[.8,.6,.4,.3]]])

    def test_bad_paint_data_fails_before_embedding(self):
        image=np.ones((2,2,4));palette=[[1,1,1,1]]
        for mask in (np.ones((1,2)),np.full((2,2),float('nan')),np.full((2,2),1.1)):
            with self.assertRaisesRegex(ValueError,'mask'):paint_rgba(image,[mask],palette)
        with self.assertRaisesRegex(ValueError,'palette'):
            paint_rgba(image,[np.zeros((2,2))],[[1,1,float('nan'),1]])


if __name__=='__main__':
    unittest.main()
