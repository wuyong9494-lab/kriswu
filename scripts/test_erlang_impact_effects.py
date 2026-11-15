#!/usr/bin/env python3
"""New Earth/meditation checks against recovered original objects, not images."""
from __future__ import annotations
import argparse
from collections import Counter
import copy
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
import warnings
import numpy as np

from prepare_erlang_impact_effects import (EARTH, MEDITATION, EFFECTS, FORCE_SYSTEMS,
    EYE_EFFECT, BASE_EYE_SHA, impact_bindings)
from erlang_skill_effect_materials import IMPACT_MATERIALS, LASER_MATERIALS
from prepare_erlang_hound_effects import inventory
from sun_triad_assets import matrix
from sun_triad_particles import emission_schedule, sample_particle


def sha(raw): return hashlib.sha256(raw).hexdigest()


class ActualImpactEffectChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        warnings.filterwarnings('ignore'); UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        cls.environment = UnityPy.load(str(ARGS.bundle)); cls.objects = {o.path_id: o for o in cls.environment.objects}
        cls.document = json.loads(gzip.decompress((ARGS.candidate / 'SF3_D15_SkillEffects.json.gz').read_bytes()))
        cls.receipt = json.loads((ARGS.candidate / 'd15-impact-effects-receipt-private.json').read_bytes())
        cls.profile = json.loads(ARGS.profile.read_bytes())
        cls.materials = json.loads((ARGS.materials / 'd15-skill-shader-bindings-private.json').read_bytes())
        cls.programs = {p['sourceMaterialPathID']:p for p in
            json.loads((ARGS.materials / 'd15-skill-metal-programs-private.json').read_bytes())['materials']}

    def test_accepted_eye_and_all_its_resources_are_unchanged(self):
        raw = (ARGS.base_eye / 'SF3_D15_SkillEffects.json.gz').read_bytes()
        self.assertEqual(sha(raw), BASE_EYE_SHA); before = json.loads(gzip.decompress(raw))
        self.assertEqual(self.document['effects'][EYE_EFFECT], before['effects'][EYE_EFFECT])
        self.assertEqual(self.document['erlangSkillBindings'][0], before['erlangSkillBindings'][0])
        self.assertEqual(self.document['erlangSkillScopes'][EYE_EFFECT], before['erlangSkillScopes'][EYE_EFFECT])
        for key, material in before['materials'].items(): self.assertEqual(self.document['materials'][key], material)
        for row in before['files']:
            self.assertIn(row, self.document['files'])
            self.assertEqual((ARGS.candidate / row['name']).read_bytes(), (ARGS.base_eye / row['name']).read_bytes())

    def test_twenty_three_original_emitters_keep_five_explicit_module_gaps(self):
        for name, (_, included, total) in EFFECTS.items():
            scope = self.document['erlangSkillScopes'][name]; effect = self.document['effects'][name]
            self.assertEqual(set(scope['boundEmitters']), set(map(str, included)))
            self.assertEqual(scope['sourceActiveEmitters'], total); self.assertFalse(scope['completePrefab'])
            self.assertEqual(len(scope['unboundEmitters']), total-len(included))
            self.assertEqual(set(t['sourceParticleSystem'] for t in effect['tracks']), set(scope['boundEmitters']))
            proofs = {p['sourceParticleSystem']:p for p in self.receipt['sourceEffects'][name]['boundEmitters']}
            for track in effect['tracks']:
                source = self.objects[int(track['sourceParticleSystem'])]
                proof = proofs[track['sourceParticleSystem']]
                renderer = self.objects[int(proof['sourceRendererPathID'])]
                self.assertEqual(sha(source.get_raw_data()), proof['sourceParticleSystemSHA256'])
                self.assertEqual(sha(renderer.get_raw_data()), proof['sourceRendererSHA256'])
                original = renderer.read_typetree()
                self.assertEqual((track['sourceRenderMode'], track['sourceRenderAlignment']),
                    (original['m_RenderMode'], original['m_RenderAlignment']))
                self.assertEqual('geometry' in track, original['m_RenderMode'] in (2,4))
                self.assertEqual(proof['sourceForceApplied'], int(track['sourceParticleSystem']) in FORCE_SYSTEMS)
                self.assertNotIn('loopPeriod', track)
            for proof in self.receipt['sourceEffects'][name]['unboundEmitters']:
                original=self.objects[int(proof['sourceParticleSystem'])].read_typetree()
                if proof['bindingStatus']=='stretched_billboard_direction_unbound':
                    self.assertEqual(self.objects[int(proof['sourceRendererPathID'])].read_typetree()['m_RenderMode'],1)
                elif proof['bindingStatus']=='mesh_shape_has_no_source_mesh':
                    self.assertEqual(original['ShapeModule']['type'],6)
                    self.assertEqual(original['ShapeModule']['m_Mesh'],{'m_FileID':0,'m_PathID':0})
                elif proof['bindingStatus']=='shape_birth_alignment_unbound':
                    self.assertTrue(original['ShapeModule']['alignToDirection'])
                else:self.fail('Unexplained original emitter omission')
            binding = next(b for b in self.document['erlangSkillBindings'] if b['effect'] == name)
            self.assertEqual(binding['lifetimeTicks'], int(np.ceil(effect['duration'] * 60)))
        for row in self.document['files']:
            raw = (ARGS.candidate / row['name']).read_bytes()
            self.assertEqual((len(raw),sha(raw)), (row['bytes'],row['sha256']))
        tracks = [t for e in self.document['effects'].values() for t in e['tracks']]
        self.assertLessEqual(sum(len(t['frames']) for t in tracks), 1_000_000)
        self.assertLessEqual(sum(len(t.get('geometry',{}).get('positions',[]))//3 for t in tracks), 600_000)
        self.assertLessEqual(sum(r['bytes'] for r in self.document['files']), 40_000_000)

    def test_source_event_anchors_reject_shifted_release_and_wrong_parent(self):
        expected, proof = impact_bindings(self.profile, ARGS.model_tracks, ARGS.rules)
        for binding in self.document['erlangSkillBindings'][1:]:
            actual = binding.copy(); actual.pop('lifetimeTicks')
            self.assertEqual(actual, expected[binding['effect']])
            self.assertFalse(binding['attachToLocal']); self.assertEqual(binding['follow'], [0,0,0])
        self.assertEqual(expected[EARTH]['shift'], [0,0,0])
        self.assertEqual(expected[EARTH]['release']['offset'], [20,0,0])
        self.assertEqual(proof['earthCreateTrigger']['events'], proof['earthEffectTrigger']['events'])
        self.assertEqual(expected[MEDITATION]['shift'], [0,.03,0])
        self.assertEqual(expected[MEDITATION]['sourceTarget'], 'modelParent')
        self.assertIsNone(expected[MEDITATION]['sourceClip']); self.assertIsNone(expected[MEDITATION]['release'])
        for key, value in (('atTick',40), ('offset',[-20,0,0])):
            wrong = copy.deepcopy(self.profile)
            next(r for r in wrong['erlangRules']['releases'] if r['modelRole']=='erlangSummon_earth')[key] = value
            with self.assertRaisesRegex(ValueError, 'Runtime Earth release'):
                impact_bindings(wrong, ARGS.model_tracks, ARGS.rules)
        with tempfile.TemporaryDirectory() as directory:
            directory=Path(directory)
            (directory/'d15-lock-1432-compact-private.json').write_bytes((ARGS.rules/'d15-lock-1432-compact-private.json').read_bytes())
            med=json.loads((ARGS.rules/'d15-lock-1438-compact-private.json').read_bytes())
            next(r for r in med if r['triggerIndex']==1)['actions'][0]['a46'][4]='enum65537'
            (directory/'d15-lock-1438-compact-private.json').write_text(json.dumps(med))
            with self.assertRaisesRegex(ValueError, 'Original meditation Parent chest'):
                impact_bindings(self.profile, ARGS.model_tracks, directory)

    def test_actual_original_mesh_vertices_and_winding(self):
        from UnityPy.helpers.MeshHelper import MeshHandler
        external = {}
        for path in ARGS.mesh_inputs:
            for row in json.loads(path.read_bytes())['records']:
                if row.get('type','Mesh')=='Mesh' and 'arraysFile' in row: external[int(row['pathID'])]=row
        checked={}
        for name in EFFECTS:
            proofs={p['sourceParticleSystem']:p for p in self.receipt['sourceEffects'][name]['boundEmitters']}
            for track in self.document['effects'][name]['tracks']:
                if track['sourceRenderMode']!=4: continue
                render=self.objects[int(proofs[track['sourceParticleSystem']]['sourceRendererPathID'])].read_typetree()
                pointer=render['m_Mesh'];pid=int(pointer['m_PathID'])
                if pid not in checked:
                    if pointer['m_FileID']==0:
                        handler=MeshHandler(self.objects[pid].read());handler.process()
                        positions=np.asarray(handler.m_Vertices)[:,:3]
                        indices=np.asarray(handler.get_triangles()[0]).reshape(-1,3)
                    else:
                        record=external[pid]; raw=Path(record['arraysFile']).read_bytes()
                        self.assertEqual(sha(raw),record['arraysSHA256'])
                        with np.load(record['arraysFile'],allow_pickle=False) as arrays:
                            positions=arrays['positions'][:,:3].copy();indices=arrays['triangles0'].reshape(-1,3).copy()
                    checked[pid]=(positions*[1,1,-1],indices[:,[0,2,1]].reshape(-1))
                positions,indices=checked[pid]
                np.testing.assert_array_equal(np.asarray(track['geometry']['positions']).reshape(-1,3),positions)
                np.testing.assert_array_equal(track['geometry']['indices'],indices)
        self.assertIn(-5020005211651685517,checked)
        self.assertIn(-2272744349922921157,checked)

    def test_original_constant_force_changes_stone_trajectory_without_changing_default(self):
        _, rows=inventory(self.environment,EARTH,EFFECTS[EARTH][0]);worlds={}
        for row in rows:
            transform=matrix(row['position'],row['rotation'],row['scale'])
            worlds[row['pathID']]=worlds[row['parent']]@transform if row['parent'] is not None else transform
            systems=[o for o in row['components'] if o.path_id==-6292074152677255774]
            if not systems: continue
            source=systems[0].read_typetree();renderer=next(o for o in row['components'] if o.type.name=='ParticleSystemRenderer').read_typetree()
            self.assertFalse(source['ClampVelocityModule']['enabled'])
            particle=emission_schedule(source,str(systems[0].path_id))[0][0]
            transform=worlds[row['pathID']]
            off,_=sample_particle(source,renderer,transform,row['scale'],particle)
            explicit,_=sample_particle(source,renderer,transform,row['scale'],particle,apply_source_force=False)
            on,_=sample_particle(source,renderer,transform,row['scale'],particle,apply_source_force=True)
            self.assertEqual(off,explicit)
            actual_track=next(t for t in self.document['effects'][EARTH]['tracks']
                if t['sourceParticleSystem']==str(systems[0].path_id) and t['name'].endswith('_'+str(particle.index)))
            self.assertEqual(actual_track['frames'],on['frames'])
            self.assertGreater(np.linalg.norm(np.asarray(on['frames'][-1][1:4])-np.asarray(off['frames'][-1][1:4])),1)
            # The original also has a position-dependent radial velocity.
            # Isolate that independent module for a closed-form acceleration
            # oracle; keep its exact ForceModule, shape, scale and lifespan.
            isolated=copy.deepcopy(source);isolated['VelocityModule']['enabled']=False
            off,_=sample_particle(isolated,renderer,transform,row['scale'],particle)
            on,_=sample_particle(isolated,renderer,transform,row['scale'],particle,apply_source_force=True)
            self.assertGreater(particle.life,0)
            local_displacement=np.array([0,0,-1000*particle.life**2])
            full_scale=np.linalg.norm(transform[:3,:3],axis=0)
            scale=full_scale if source['scalingMode']==0 else np.asarray(row['scale'])
            expected=(transform[:3,:3]/full_scale)@(local_displacement*scale)*[1,1,-1]
            actual=np.asarray(on['frames'][-1][1:4])-np.asarray(off['frames'][-1][1:4])
            np.testing.assert_allclose(actual,expected,atol=1e-7,rtol=1e-9)
            self.assertGreater(np.linalg.norm(actual),1)
            break
        else: self.fail('Original force stone missing')

    def test_twenty_new_material_variants_preserve_source_shader_and_opaque_stone_state(self):
        def canonical(text):
            text=re.sub(r'\bfloat([234])x\1\b',r'mat\1',text);text=re.sub(r'\bfloat([234])\b',r'vec\1',text)
            text=text.replace('rsqrt(','inversesqrt(').replace('o.position','gl_Position')
            text=re.sub(r'\b[oi]\.(vs_\w+)\b',r'\1',text)
            text=re.sub(r'(\w+)\.sample\(\1Sampler,\s*',r'texture(\1,',text)
            return re.sub(r'\s+','',text)
        expected=set(IMPACT_MATERIALS)-set(LASER_MATERIALS)
        self.assertEqual({int(m['sourcePathID']) for m in self.materials['materials']},expected)
        self.assertEqual([m['sourcePathID'] for m in self.materials['materials']
            if 'm_'+m['sourcePathID'] not in self.document['materials']], ['-8870619190891733605'])
        opaque=[]
        for material in self.materials['materials']:
            pid=material['sourcePathID'];raw=(ARGS.materials/(pid+'.raw')).read_bytes()
            self.assertEqual(sha(raw),IMPACT_MATERIALS[int(pid)][1])
            original=Path(material['exactMatches'][0]['glslFile']).read_text()
            target=self.document['materials'].get('m_'+pid);program=self.programs[pid]['program']
            program_raw=(ARGS.materials/program['file']).read_bytes()
            self.assertEqual((len(program_raw),sha(program_raw)),(program['bytes'],program['sha256']))
            metal=program_raw.decode()
            if target is not None:
                self.assertEqual(target['program'],program)
                self.assertEqual((ARGS.candidate/program['file']).read_bytes(),program_raw)
            self.assertNotRegex(metal,r'\bdiscard\s*;')
            self.assertEqual(metal.count('discard_fragment();'),len(re.findall(r'\bdiscard\s*;',original)))
            bodies=re.findall(r'void main\(\)\s*\{(.*?)^\}',original,re.M|re.S)
            self.assertEqual(len(bodies),2)
            wanted=Counter(canonical(line.strip()) for body in bodies for line in body.splitlines() if '=' in line and line.strip().endswith(';'))
            actual=Counter(canonical(line.strip()) for line in metal.splitlines() if '=' in line and line.strip().endswith(';'))
            self.assertFalse(wanted-actual,f'Original shader arithmetic removed: {wanted-actual}')
            if target is not None and target['raster']['destination']==0:
                self.assertEqual(target['raster']['source'],1);opaque.append(pid)
                self.assertTrue(target['raster']['zWrite'])
                self.assertEqual(set(target['textures']),{'_StoneColor_Tex','_StoneCracksNoiseScroll_Tex','_StoneCracks_Tex','_StoneGradient_Tex'})
                for track in self.document['effects'][EARTH]['tracks']:
                    if track['material']=='m_'+pid:
                        self.assertEqual(track['texture'],target['textures']['_StoneColor_Tex']['file'])
                        self.assertEqual(track['sourceRenderQueue'],2000)
        self.assertEqual(opaque,['-654479186809044038'])
        shader=next(s for s in self.materials['shaders'] if s['pathID']=='2855819893914472268')
        self.assertEqual(shader['sourceObjectSHA256'],'f0229a7fbc7710912cb7e3e4059ce20869ae8c8dcafbd17d568ae5dad02d810c')
        self.assertEqual(shader['name'],'Mobile/Particles/Additive')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('candidate','base-eye','materials','bundle','profile','model-tracks','rules'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--mesh-inputs',type=Path,nargs='+',required=True)
    ARGS,tests=parser.parse_known_args();unittest.main(argv=[sys.argv[0],*tests],verbosity=2)
