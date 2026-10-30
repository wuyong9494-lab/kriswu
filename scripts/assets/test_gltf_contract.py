import copy
import unittest
from gltf_contract import unsupported_features


class ImportContractTests(unittest.TestCase):
    def setUp(self):
        self.document = {
            'materials': [{'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}}}],
            'meshes': [{'primitives': [{'attributes': {}}]}],
            'animations': [{'name': 'Face', 'samplers': [{'interpolation': 'LINEAR'}],
                            'channels': [{'target': {'path': 'rotation'}}]}]
        }

    def test_bone_face_and_base_color_remain_supported(self):
        self.assertEqual(unsupported_features(self.document), [])

    def test_silent_loss_of_normal_pbr_morph_or_cubic_is_rejected(self):
        mutations = [
            lambda d: d['materials'][0].update(normalTexture={'index': 1}),
            lambda d: d['materials'][0]['pbrMetallicRoughness'].update(metallicRoughnessTexture={'index': 1}),
            lambda d: d['materials'][0]['pbrMetallicRoughness'].update(baseColorFactor=[0.5, 1, 1, 1]),
            lambda d: d['materials'][0]['pbrMetallicRoughness']['baseColorTexture'].update(texCoord=1),
            lambda d: d['meshes'][0]['primitives'][0].update(targets=[{'POSITION': 3}]),
            lambda d: d['animations'][0]['samplers'][0].update(interpolation='CUBICSPLINE'),
            lambda d: d['animations'][0]['channels'][0]['target'].update(path='weights'),
            lambda d: d.update(extensionsRequired=['KHR_draco_mesh_compression'])
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                document = copy.deepcopy(self.document)
                mutate(document)
                self.assertTrue(unsupported_features(document))


if __name__ == '__main__':
    unittest.main()
