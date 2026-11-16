#!/usr/bin/env python3
"""Verify original D13 body audio routes, exact PCM and fail-closed pins."""
from collections import Counter
import copy
import io
import json
import os
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
import wave

from prepare_serpent_body_audio import (CHARACTER_SHA, CONFIGURATION_HASHES, CONTEXT,
    DOCUMENT_FILE, EXISTING_AUDIO_SHA, MANIFEST_SHA, MATCH_SHA, NEW_PATHS, PCM_FIELDS,
    PREFIX, PROFILE_SHA, RECEIPT_FILE, REUSED_AUDIO_SHA, choices, encoded,
    read_inputs, read_manifest, sha, typed, verify_document)


NEW_PCM = {
    '9_Footsteps_Stone_Surface_V25': (44100, 15445,
        'eb16eb18122019003f82e39cd8d9259deaf15486d37dcfeab7a7b58c232f7676'),
    '8_Short_Whooshes_Of_Light_Weapon_V10_bip': (22050, 6528,
        '3672a65639326495f275d20a75c6e3f086476ac72bcd36cd92cf642fdcb3c0ef'),
    '8_Short_Whooshes_Of_Light_Weapon_V16_bip': (22050, 6939,
        'a26237c47136ec8770ca5fdaa5e4e3e02a42b648e76df2b5a5baeed530907753'),
    '8_Short_Whooshes_Of_Light_Weapon_V17_bip': (22050, 5936,
        '7c7e0c9241e8f7e5c074c266479456fa40ce90b72a017462970cd2e44240f617'),
    '8_Short_Whooshes_Of_Light_Weapon_V21_bip': (22050, 6397,
        'fe290bbe2dfaae28e3d6c61fc712a761b64c0a238314bcce91f37d3d738af16d'),
    '8_Short_Whooshes_Of_Light_Weapon_V6_bip': (22050, 6803,
        '1dc334ad600a82e0b8825133d926c3dfc19c75278bfc09ae967f62975a1360e1'),
}


class SerpentBodyAudioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = os.environ.get('SERPENT_BODY_AUDIO_DIR')
        cls.directory = Path(directory) if directory else None
        if cls.directory:
            cls.receipt = json.loads((cls.directory/RECEIPT_FILE).read_bytes())
            arguments = {k: Path(v['path']) for k, v in cls.receipt['inputs'].items()}
            cls.inputs = read_inputs(SimpleNamespace(**arguments))
            cls.value = read_manifest(cls.directory/DOCUMENT_FILE, cls.inputs)

    def actual(self):
        if self.directory is None:
            self.skipTest('Actual private supplemental D13 body audio was not supplied')
        return self.value

    def test_candidate_order_case_and_duplicate_weight_are_preserved(self):
        source = ['whoosh/light/Original_A@Battle@Movement',
                  'whoosh/light/original_b@Battle@Movement',
                  'whoosh/light/Original_A@Battle@Movement']
        result = choices(source)
        self.assertEqual([c['identifier'] for c in result], source)
        self.assertEqual([c['sourcePath'] for c in result], [
            PREFIX+'whoosh/light/original_a.wav', PREFIX+'whoosh/light/original_b.wav',
            PREFIX+'whoosh/light/original_a.wav'])
        self.assertEqual(len(result), 3)
        self.assertTrue(all(set(c) == {'identifier', 'sourcePath', 'bus', 'mixerGroup'} for c in result))
        for value in ([], [{'identifier': source[0], 'weight': 1}], ['../other@Battle@Movement'],
                      ['a@Menu@Movement'], ['a@Battle@Unknown']):
            with self.subTest(value=value), self.assertRaises(ValueError):
                choices(value)

    def test_all_66_configs_and_embedded_motions_are_authenticated_against_originals(self):
        document = self.actual()
        profile = self.inputs['profile']; physical = self.inputs['physical']
        self.assertEqual(document['sourceMatchProfileSHA256'], MATCH_SHA)
        self.assertEqual(document['sourcePhysicalProfileSHA256'], PROFILE_SHA)
        self.assertEqual(profile['clips'], physical['clips'])
        self.assertEqual(profile['sha256'], CHARACTER_SHA)
        self.assertEqual(document['sourceConfigurationHashes'], CONFIGURATION_HASHES)
        self.assertEqual(len(document['clips']), 66)
        rows = {c['clip']: c for c in document['clips']}
        for clip in profile['clips']:
            source = clip['sourceConfiguration']
            raw = self.inputs['originalConfigurations'][source['sourceEntry'], source['sourceRecordIndex']]
            self.assertEqual(typed(source['configuration']), typed(raw))
            self.assertEqual(rows[clip['name']]['sourceConfigurationSHA256'], sha(encoded(raw)))
        self.assertEqual(sum(not row['roles'] for row in rows.values()), 14)
        self.assertEqual({c['clip'] for c in rows.values() if c['looped']},
                         {'d13_stance_birth', 'dual_sabers_stance_birth'})

    def test_each_of_139_routes_uses_original_frame_and_ordered_candidates(self):
        document = self.actual()
        actual = {(m['clip'], m['markerIndex'], m['route']): m
                  for m in document['markers']+document['excludedExistingBodyMarkers']}
        self.assertEqual(len(actual), 139)
        all_choices = 0
        for clip in self.inputs['profile']['clips']:
            source = clip['sourceConfiguration']
            conf = self.inputs['originalConfigurations'][source['sourceEntry'], source['sourceRecordIndex']]
            first = 0 if conf['FirstFrame'] is None else max(0, conf['FirstFrame']-1)
            stride = 2 if conf['MidFrames'] is None else conf['MidFrames']+1
            for index, row in enumerate(conf['Sounds'] or []):
                for route, candidates in (('Common', row['Common']),
                        ('Male', (row['Gender'] or {}).get('Male')),
                        ('Floor.Stone', (row['Floor'] or {}).get('Stone'))):
                    if not candidates:
                        continue
                    marker = actual[clip['name'], index, route]
                    self.assertEqual(marker['rawFrame'], row['Frame'])
                    self.assertEqual(marker['sourceFrame'], max(0, row['Frame']))
                    self.assertEqual(marker['tick'], (max(0, row['Frame'])-first)*stride)
                    self.assertEqual([c['identifier'] for c in marker['choices']], candidates)
                    self.assertEqual(marker['sourceMotionSHA256'], clip['sha256'])
                    self.assertLessEqual(marker['tick'], clip['sourceEndEventTick'])
                    all_choices += len(candidates)
        self.assertEqual(all_choices, 643)
        stance = actual['d13_stance', 0, 'Common']
        self.assertEqual((stance['rawFrame'], stance['tick']), (60, 120))
        floor = actual['m_agl_jump_up', 2, 'Floor.Stone']
        self.assertEqual((floor['rawFrame'], floor['tick']), (31, 62))
        self.assertEqual(Counter(m['route'] for m in document['markers']),
                         {'Common': 92, 'Male': 36, 'Floor.Stone': 7})
        self.assertEqual(document['context'], CONTEXT)

    def test_only_the_four_existing_clip_clock_events_are_excluded(self):
        document = self.actual()
        def identity(marker):
            return (marker['clip'], marker['sourceMotionSHA256'], marker['tick'],
                    marker['choices'][0]['identifier'])
        old = {(m['clip'], m['sourceMotionSHA256'], m['tick'], m['identifier'])
               for m in self.inputs['ordinary']['bodyMarkers']}
        excluded = document['excludedExistingBodyMarkers']
        self.assertEqual(len(excluded), 4)
        self.assertEqual({identity(m) for m in excluded}, old)
        self.assertTrue(all(len(m['choices']) == 1 and m['route'] == 'Common' for m in excluded))
        self.assertEqual(Counter(m['existingAction'] for m in excluded), {'poison': 3, 'bottle': 1})
        self.assertFalse(any(identity(m) in old for m in document['markers']))
        # A different D13 alias reuses the original poison motion and sounds;
        # excluding by sound or motion digest alone would silently lose them.
        poison = next(m for m in excluded if m['existingAction'] == 'poison')
        same_motion = [m for m in document['markers']
                       if m['sourceMotionSHA256'] == poison['sourceMotionSHA256']]
        self.assertEqual(len(same_motion), 3)
        self.assertTrue(all(m['clip'] != poison['clip'] for m in same_motion))

    def test_all_66_pcm_containers_samples_and_60_reuse_identities_read_back(self):
        document = self.actual()
        self.assertEqual({p.name for p in self.directory.glob('*.wav')}, {f['name'] for f in document['files']})
        self.assertEqual(len(document['files']), 66)
        old = {f['sourcePath']: f for d in (self.inputs['ordinary'], self.inputs['reused']) for f in d['files']}
        provenance = Counter(); new = {}
        for file in document['files']:
            raw = (self.directory/file['name']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (file['bytes'], file['sha256']))
            self.assertEqual(raw[:4], b'RIFF')
            self.assertEqual(raw[8:12], b'WAVE')
            self.assertEqual(struct.unpack_from('<I', raw, 4)[0]+8, len(raw))
            with wave.open(io.BytesIO(raw), 'rb') as pcm:
                self.assertEqual((pcm.getframerate(), pcm.getnchannels(), pcm.getsampwidth(), pcm.getnframes()),
                    (file['sampleRate'], file['channels'], file['sampleWidth'], file['sampleFrames']))
                self.assertEqual(pcm.getcomptype(), 'NONE')
                samples = pcm.readframes(file['sampleFrames']+1)
            self.assertEqual(len(samples), file['sampleFrames']*file['channels']*2)
            self.assertEqual(sha(samples), file['pcmSHA256'])
            if file['reusedExistingPCM']:
                self.assertEqual({k: file[k] for k in PCM_FIELDS},
                                 {k: old[file['sourcePath']][k] for k in PCM_FIELDS})
                provenance[file['provenance']['sourcePCMManifestSHA256']] += 1
            else:
                self.assertIn(file['sourcePath'], NEW_PATHS)
                new[file['sourceName']] = (file['sampleRate'], file['sampleFrames'], file['sha256'])
        self.assertEqual(provenance, {REUSED_AUDIO_SHA: 55, EXISTING_AUDIO_SHA: 5})
        self.assertEqual(new, NEW_PCM)
        self.assertEqual(sum(f['bytes'] for f in document['files']), 2_971_156)

    def test_mutated_route_clock_context_exclusion_and_source_pins_fail_closed(self):
        document = self.actual()
        multiple = next(i for i, m in enumerate(document['markers']) if len(m['choices']) > 1)
        mutations = (
            ('clock', lambda d: d['markers'][0].__setitem__('tick', 118)),
            ('raw_frame', lambda d: d['markers'][0].__setitem__('rawFrame', 59)),
            ('order', lambda d: d['markers'][multiple]['choices'].reverse()),
            ('multiplicity', lambda d: d['markers'][multiple]['choices'].pop()),
            ('extra_weight', lambda d: d['markers'][0]['choices'][0].__setitem__('weight', 1)),
            ('floor_stage', lambda d: d['context'].__setitem__('stageSHA256', '0'*64)),
            ('floor_type', lambda d: d['context'].__setitem__('floor', 'Metal')),
            ('profile', lambda d: d.__setitem__('sourceMatchProfileSHA256', PROFILE_SHA)),
            ('actor', lambda d: d.__setitem__('characterSHA256', '0'*64)),
            ('existing_event', lambda d: d['excludedExistingBodyMarkers'].pop()),
            ('omission', lambda d: d['markers'].pop()),
            ('duplicate', lambda d: d['markers'].append(copy.deepcopy(d['markers'][0]))),
            ('source_path_id', lambda d: d['files'][0].__setitem__('sourcePathID', '1')),
            ('activation', lambda d: d.__setitem__('normalApplicationPlaybackObserved', True)),
        )
        for name, change in mutations:
            with self.subTest(name=name):
                changed = copy.deepcopy(document); change(changed)
                with self.assertRaises(ValueError):
                    verify_document(changed, self.inputs)
        # The fixed outer manifest digest also rejects tampering with new PCM,
        # whose expected digest cannot be authorized by its own JSON field.
        changed = copy.deepcopy(document)
        next(f for f in changed['files'] if not f['reusedExistingPCM'])['sha256'] = '1'*64
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/DOCUMENT_FILE; path.write_bytes(encoded(changed))
            with self.assertRaisesRegex(ValueError, 'Pinned input differs'):
                read_manifest(path, self.inputs)

    def test_receipt_bounds_observations_to_source_events_without_claiming_native_cost(self):
        document = self.actual(); receipt = self.receipt
        self.assertEqual(receipt['manifest']['sha256'], MANIFEST_SHA)
        self.assertEqual(receipt['manifest']['bytes'], 378_569)
        self.assertEqual(receipt['pcmBytes'], 2_971_156)
        self.assertEqual(receipt['originalConfigurationsVerified'], 66)
        self.assertEqual(receipt['sourceAudioObjectsVerified'], 66)
        self.assertEqual(receipt['originalSourceBundleCount'], 4)
        self.assertEqual(receipt['newlyDecodedSourceBundleCount'], 2)
        self.assertEqual(receipt['networkBytes'], 0)
        self.assertFalse(receipt['originalSixSoundManifestChanged'])
        self.assertFalse(receipt['normalApplicationPlaybackObserved'])
        observations = receipt['concurrencyObservation']
        self.assertEqual(observations['uniqueClipTickPairs'], 135)
        self.assertEqual(observations['maximumMarkersAtSameClipTick'], 1)
        self.assertEqual(observations['uniqueOrderedCandidateLists'], 19)
        self.assertEqual(observations['potentialPreparedPlayersForTwoOwners'], 1278)
        self.assertFalse(observations['crossClipOrOwnerTailOverlapMeasured'])
        self.assertFalse(observations['nativePlayerCostMeasured'])
        self.assertEqual(sum(len(m['choices']) for m in document['markers']), 639)


if __name__ == '__main__':
    unittest.main()
