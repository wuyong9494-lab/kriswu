"""Focused checks against an actual verified D13 candidate.

SERPENT_RECOVERY_ROOT points to the parent containing recovery-20261115 and
recovery-20261116. Missing private originals are skips, never source passes.
"""
import copy,json,os,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
import xml.etree.ElementTree as ET
import numpy as np

from build_serpent_source_geometry import source_weights,load_bones,BONES
from prepare_serpent_animated_body import (PROFILE,load_named,verify_clip,append_motion,
    ROLE_KEYS,STATIC_SHA,STATIC_RECEIPT_SHA)
from build_erlang_source_assets import checked
from sun_triad_assets import glb_read,Writer
from sun_triad_source_bones import merge_bone_ids


class SerpentSourceBodyChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        value=os.environ.get('SERPENT_RECOVERY_ROOT')
        if not value:raise unittest.SkipTest('Actual original D13 inputs were not supplied')
        cls.base=Path(value);cls.root=cls.base/'recovery-20261116'
        cls.profile=json.loads((cls.root/'serpent-animated-body-v1'/PROFILE).read_bytes())
        model=cls.root/'serpent-animated-body-v1'/(cls.profile['resourceName']+'.glb')
        checked(model,cls.profile['sha256'],20_000_000);cls.g,cls.b=glb_read(model)
        cls.names={r['name']:r['targetNode'] for r in cls.profile['sourceBoneBindings']}
        cls.configs=load_bones(cls.root/'serpent-source-inputs-v1',cls.base/'recovery-20261115/recovered-shared-bones')
        cls.configs.pop('ranged')
        raw=(cls.base/'recovery-20261115/recovered-shared-bones'/BONES['base'][0]).read_bytes()
        cls.configs['base']['masses']={x.get('Name'):float(x.get('Mass','0')) for x in ET.fromstring(raw).findall('./Bones/Bone')}
        cls.ids={i:n for i,n in merge_bone_ids(*cls.configs.values()).items() if n in cls.names}

    def clip(self,role):
        return next(c for c in self.profile['clips'] if c['name']==self.profile['roles'][role])

    def test_one_bone_layout_requires_real_serialized_channel_contract(self):
        channels=[SimpleNamespace(dimension=0) for _ in range(14)];channels[13].dimension=1
        mesh=SimpleNamespace(m_Name='wpn__shuangou_01_04__l',m_BindPose=[None],m_VertexData=SimpleNamespace(m_Channels=channels))
        handler=SimpleNamespace(m_BoneIndices=[[0],[0]],m_BoneWeights=None,m_Vertices=[[1,2,3],[4,5,6]])
        weights,ids,kind=source_weights(mesh,handler)
        self.assertEqual(weights.tolist(),[[1.],[1.]])
        self.assertEqual(kind,'UnityOneBoneImplicitUnitWeight')
        channels[13].dimension=2
        with self.assertRaisesRegex(ValueError,'OneBone'):source_weights(mesh,handler)
        channels[13].dimension=1;handler.m_BoneIndices=[[0],[1]]
        with self.assertRaisesRegex(ValueError,'OneBone'):source_weights(mesh,handler)

    def test_helmet_policy_and_original_cloth_coordinates_survive_export(self):
        r=json.loads(checked(self.root/'serpent-static-geometry-v1/receipt-private.json',STATIC_RECEIPT_SHA,40_000))
        self.assertEqual(r['character']['sha256'],STATIC_SHA)
        by_name={r['mesh']:r for r in r['sourceSkinHashMappings']}
        for name in ('arm__agl_41_m_tabard','arm__agl_41_m_tie_down'):
            m=np.array(by_name[name]['sourceMeshToActorTransform'])
            self.assertGreater(abs(m[1,2]),.9999)
            self.assertGreater(abs(m[2,1]),.9999)
        active=set();stack=list(self.g['scenes'][0]['nodes'])
        while stack:
            i=stack.pop();active.add(i);stack+=self.g['nodes'][i].get('children',[])
        self.assertFalse(active & set(r['personalPortrait']['preservedMeshNodes']))
        self.assertEqual(sum('mesh' in self.g['nodes'][i] for i in active),7)

    def test_source_clock_crops_and_distinct_poison_aliases(self):
        stance=next(c for c in self.profile['clips'] if c['name']=='dual_sabers_stance')
        self.assertEqual((stance['sourceFirstIndex'],stance['sourceLastIndex'],stance['frames'],stance['playbackTicks']),
                         (61,129,69,136))
        poison,deadly=self.clip('serpentPoison'),self.clip('serpentIntoxication')
        self.assertEqual(poison['sourceBytesBase64'],deadly['sourceBytesBase64'])
        self.assertNotEqual(poison['sourceConfiguration']['configuration']['Intervals'],deadly['sourceConfiguration']['configuration']['Intervals'])
        self.assertNotEqual(poison['name'],deadly['name'])
        self.assertEqual(self.clip('walkForward')['sourceConfiguration']['sourceRecordIndex'],46)
        self.assertEqual(self.clip('walkForward')['frames'],18)

    def test_modified_named_configuration_is_rejected(self):
        source=self.root/'serpent-named-settings-v1/serpent-shuangou-animation-named-v1.json'
        raw=bytearray(source.read_bytes());raw[-2]^=1
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/source.name;p.write_bytes(raw)
            with self.assertRaisesRegex(ValueError,'Pinned input differs'):load_named(p)

    def test_changed_weapon_capsule_is_rejected_by_written_pose(self):
        c=copy.deepcopy(self.clip('idle'));c['tracks']['collisionEdges'][0]['base'][0][0]+=.01
        with self.assertRaisesRegex(ValueError,'Written GLB differs'):
            verify_clip(self.g,self.b,c,self.names,self.ids,self.configs)

    def test_model_only_and_missing_body_tracks_are_rejected(self):
        # Actual stored actor bytes become invalid when even one indispensable
        # source body ID is unresolved; they cannot be accepted as a partial rig.
        import base64
        c=self.clip('idle');raw=base64.b64decode(c['sourceBytesBase64']);ids=dict(self.ids);del ids[0]
        info=dict(sha256=c['sha256'],bytes=len(raw),frames=c['sourceUncroppedFrames'])
        with self.assertRaisesRegex(ValueError,'unbound tracks'):
            append_motion(Writer(),self.names,ids,self.configs,info,raw,c['sourceConfiguration'],c['name'])
        self.assertFalse(self.profile['recoveryBoundary']['fullMatchProfile'])
        self.assertFalse(any(c['name'] in ('d13_bottle_throw_bullet','d13_helmet_ability_model') for c in self.profile['clips']))


if __name__=='__main__':unittest.main()
