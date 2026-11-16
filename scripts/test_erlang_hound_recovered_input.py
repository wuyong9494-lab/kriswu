#!/usr/bin/env python3
"""Check the actual recovered hound cache, source identities and attachment."""
import argparse
import copy
import gzip
import json
import tempfile
import unittest
import warnings
from pathlib import Path

from recover_erlang_hound_effects import CHARACTER_SHA, MATERIALS, PROFILE_SHA, SOURCES, sha
from prepare_erlang_hound_effects import BUNDLE, EFFECTS, inventory
from sun_triad_particle_assets import SourceAssets


class RecoveredHoundChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
        cls.cache = cls.recovery / 'source-inputs-private'
        cls.runtime = cls.recovery / 'runtime'
        cls.receipt = json.loads((cls.cache / 'source-cache-recovery-receipt-private.json').read_bytes())
        cls.sampling = json.loads((cls.runtime / 'd15-hound-fx-receipt-private.json').read_bytes())
        cls.document = json.loads(gzip.decompress((cls.runtime / 'SF3_D15_Effects.json.gz').read_bytes()))
        cls.temporary = tempfile.TemporaryDirectory()
        cls.assets = SourceAssets(cls.source, cls.cache, Path(cls.temporary.name), bundle_identity=BUNDLE)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_complete_recovered_cache_matches_pinned_sources(self):
        self.assertEqual(self.receipt['sourceFiles'], [dict(name=n, bytes=v[0], sha256=v[1]) for n, v in SOURCES.items()])
        for name, (size, digest) in SOURCES.items():
            path = self.mesh_bundle if name == self.mesh_bundle.name else self.source / name
            raw = path.read_bytes()
            self.assertEqual((len(raw), sha(raw)), (size, digest))
        expected = {record['name'] for record in self.receipt['files']}
        actual = {str(p.relative_to(self.cache)) for p in self.cache.rglob('*') if p.is_file()}
        self.assertEqual(actual, expected | {'source-cache-recovery-receipt-private.json'})
        for record in self.receipt['files']:
            raw = (self.cache / record['name']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (record['bytes'], record['sha256']))
        self.assertEqual({int(r['pathID']): r['sourceObjectSHA256'] for r in self.receipt['materialRecords']}, MATERIALS)
        self.assertEqual(len(self.receipt['meshRecords']), 1)
        self.assertEqual(self.receipt['meshRecords'][0]['pathID'], '124742994637592539')
        self.assertEqual(self.receipt['meshRecords'][0]['externalCAB'], 'CAB-d3188284432b8c2807c55619773eefb4')

    def test_real_emitters_and_new_actor_binding(self):
        profile_raw = self.profile.read_bytes()
        self.assertEqual(sha(profile_raw), PROFILE_SHA)
        profile = json.loads(profile_raw)
        self.assertEqual(self.document['characterSHA256'], CHARACTER_SHA)
        self.assertEqual(self.sampling['profileSHA256'], PROFILE_SHA)
        self.assertEqual([t for t in profile['summonTracks'] if t['role'] == 'erlangSummon_hound'],
                         [self.sampling['houndTrack']])
        original = {}
        for effect, prefab in EFFECTS.items():
            _, rows = inventory(self.assets.environment, effect, prefab)
            for row in rows:
                for source in (c for c in row['components'] if c.type.name == 'ParticleSystem'):
                    original[str(source.path_id)] = sha(source.get_raw_data())
        sampled = {r['sourceParticleSystem']: r['sourceParticleSystemSHA256'] for r in self.sampling['sourceEmitters']}
        self.assertEqual(len(sampled), 9)
        self.assertTrue(all(original[pid] == digest for pid, digest in sampled.items()))
        self.assertEqual(sum(len(effect['tracks']) for effect in self.document['effects'].values()), 42)
        self.assertEqual(sum(len(track['frames']) for effect in self.document['effects'].values() for track in effect['tracks']), 2225)

    def test_material_cache_rejects_wrong_cab_and_changed_raw_identity(self):
        record = self.assets.records[0]
        with self.assertRaises(ValueError):
            self.assets.record(record['type'], 'CAB-unverified', int(record['pathID']))
        original = self.assets.records
        changed = copy.deepcopy(original)
        for candidate in changed:
            if candidate['type'] == record['type'] and candidate['pathID'] == record['pathID']:
                candidate['sourceObjectSHA256'] = '0' * 64
        self.assets.records = changed
        try:
            with self.assertRaises(ValueError):
                self.assets.record(record['type'], record['externalCAB'], int(record['pathID']))
        finally:
            self.assets.records = original


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('recovery', 'source', 'mesh-bundle', 'profile'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for key, value in vars(args).items():
        setattr(RecoveredHoundChecks, key, value)
    unittest.main(argv=['test_erlang_hound_recovered_input.py'], verbosity=2)
