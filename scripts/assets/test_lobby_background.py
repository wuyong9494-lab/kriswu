"""Authored timeline cases, independent of the private client resources."""
import unittest

from export_lobby_background import certify_background
from source_flash import FormatError


def fixture():
    return {'exports':{'background':{'objectID':1,'status':'requires_layout_text_and_state_bindings'}},
            'sourceSCSHA256':'a'*64,'exclusions':[], 'matrices':[[1,0,0,1,200,0], [1,0,0,1,0,0]],
            'objects': {
                '1': {'commands':[], 'fps':60, 'frameCount':1,
                      'children':[{'objectID':2,'blendMode':64}],
                      'frames':[{'repeat':1,'elements':[[0,0,-1]]}]},
                '2': {'commands':[], 'fps':60, 'frameCount':2,
                      'children':[{'objectID':3,'blendMode':0}],
                      'frames':[{'repeat':1,'elements':[[0,-1,-1]]},
                                {'repeat':1,'elements':[[0,1,-1]]}]},
                '3': {'commands':[{'vertices':[[0,0,0,0],[10,0,0,0],[0,10,0,0]]}]}}}


class BackgroundProofTests(unittest.TestCase):
    def certify(self, scene):
        return certify_background(scene, 'background', [-50,-50,50,50], [100,100])

    def test_complete_clock_is_bound_to_exact_source_viewport_and_instance(self):
        scene = self.certify(fixture())
        proof = scene['exclusions'][0]
        self.assertEqual(proof['periodFrames'],2)
        self.assertEqual(proof['parentObjectID'],1)
        self.assertEqual(proof['childIndex'],0)
        self.assertEqual(proof['sourceRect'],[-50,-50,50,50])
        self.assertEqual(proof['sourceSCSHA256'],'a'*64)
        self.assertEqual(scene['exports']['background']['status'],'ready')
        self.assertEqual(len(scene['objects']),3)

    def test_later_frame_entering_viewport_is_not_excluded(self):
        scene = fixture(); scene['matrices'][1][4] = -200
        with self.assertRaisesRegex(FormatError,'enters viewport'):
            self.certify(scene)
        self.assertEqual(scene['exclusions'],[])
        self.assertNotIn('excludedByProof',scene['objects']['1']['children'][0])

    def test_reused_instance_requires_every_transform_to_stay_outside(self):
        scene = fixture()
        scene['objects']['1']['frames'][0]['elements'].append([0,1,-1])
        with self.assertRaisesRegex(FormatError,'enters viewport'):
            self.certify(scene)

    def test_descendant_clocks_use_full_common_period(self):
        scene = fixture()
        scene['objects']['3'] = {'commands':[], 'fps':60,'frameCount':3,
            'children':[{'objectID':4,'blendMode':0}],
            'frames':[{'repeat':3,'elements':[[0,-1,-1]]}]}
        scene['objects']['4'] = fixture()['objects']['3']
        self.assertEqual(self.certify(scene)['exclusions'][0]['periodFrames'],6)

    def test_motion_unknown_blends_unbound_text_and_unsupported_clock_fail(self):
        variants=[]
        a=fixture(); a['objects']['1']['frameCount']=2; a['objects']['1']['frames'][0]['repeat']=2;variants.append(a)
        a=fixture(); a['objects']['1']['children'][0]['blendMode']=99;variants.append(a)
        a=fixture(); a['objects']['2']['fps']=30;variants.append(a)
        a=fixture(); a['objects']['3']['textField']={'text':'unbound'};variants.append(a)
        a=fixture(); a['objects']['3']['commands']=[];variants.append(a)
        for scene in variants:
            with self.subTest(scene=scene), self.assertRaises(FormatError): self.certify(scene)

    def test_unknown_descendant_in_a_later_parent_state_is_not_ignored(self):
        scene = fixture()
        scene['objects']['1']['children'][0]['blendMode']=0
        scene['objects']['2']['children'].append({'objectID':3,'blendMode':64})
        scene['objects']['2']['frames'][1]['elements']=[[1,0,-1]]
        with self.assertRaises(FormatError): self.certify(scene)


if __name__ == '__main__': unittest.main()
