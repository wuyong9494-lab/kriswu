import copy
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest

from recover_serpent_bottle_model import FILE, verify
from sun_triad_assets import Writer, glb_read


class SerpentBottleModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path=os.environ.get('SERPENT_BOTTLE_OUTPUT')
        if not path: raise unittest.SkipTest('Actual recovered D13 bottle output not supplied')
        cls.root=Path(path)
        cls.document=json.loads((cls.root/'bottle-source-private.json').read_bytes())

    def test_actual_original_motion_and_skin_readback(self):
        result=verify(self.root/FILE,self.document)
        self.assertEqual(result['comparisons'],245)
        self.assertEqual(result['skinnedVertexComparisons'],41650)
        self.assertLess(result['maximumSkinErrorMeters'],2e-5)

    def test_native_clamp_retains_real_samples_and_cloud_creation_precedes_delete(self):
        d=self.document
        self.assertEqual(d['sourceConfiguration']['configuration']['EndFrame'],30)
        self.assertEqual(d['sourceMotion']['frames'],29)
        self.assertEqual((d['sourceFirstIndex'],d['sourceLastIndex'],d['sourceEndEventTick']),(4,28,48))
        self.assertEqual(d['sourceAnimationEnd']['actions'][0]['a45'][15][7],'shd__shadow_ranged_agile_cloud')
        self.assertEqual(d['sourceAnimationEnd']['actions'][1],{'a50':[None,None]})
        self.assertEqual(d['boundaries']['bottleAttackIntervals'],0)
        self.assertFalse(d['boundaries']['cloudMotionBound'])

    def test_changed_key_time_motion_mesh_or_mirrored_binding_is_rejected(self):
        original,binary=glb_read(self.root/FILE)
        for mutation in ('key_time','root_motion','mesh_vertex','mirror_bone'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as temp:
                g=copy.deepcopy(original);data=bytearray(binary[:g['buffers'][0]['byteLength']])
                if mutation=='mirror_bone':
                    g['skins'][0]['joints']=g['skins'][1]['joints']
                else:
                    if mutation=='key_time': index=g['animations'][0]['samplers'][0]['input']
                    elif mutation=='root_motion': index=g['animations'][0]['samplers'][0]['output']
                    else: index=g['meshes'][0]['primitives'][0]['attributes']['POSITION']
                    accessor=g['accessors'][index];view=g['bufferViews'][accessor['bufferView']]
                    offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
                    old=struct.unpack_from('<f',data,offset)[0]
                    struct.pack_into('<f',data,offset,old+.1)
                path=Path(temp)/'changed.glb';writer=Writer();writer.g=g;writer.b=data;writer.save(path)
                with self.assertRaises(ValueError):verify(path,self.document)


if __name__=='__main__':unittest.main()
