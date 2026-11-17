#!/usr/bin/env python3
"""Reject wrong source identities using the actual private Overload candidate.

Requires --candidate-profile; no synthetic passing asset or silent skip.
This checks source-compiler boundaries, not game/native rendering behavior.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
from pathlib import Path
import unittest
import warnings
from zipfile import ZipFile

import prepare_serpent_overload_source as source

CONFIG = None


class SourceBoundaryTests(unittest.TestCase):
    def changed(self, key, value):
        config = copy.deepcopy(CONFIG)
        config[key] = value
        with self.assertRaises(ValueError):
            source.validate_configuration(config)

    def test_rejects_another_hero_alias(self):
        self.changed('Animation', 'D15_Avatara_Transform_In')

    def test_rejects_same_frame_count_different_original_path(self):
        self.changed('FileName', 'unique_moves/moth/moth_shadow_form_in.bin')

    def test_rejects_unreviewed_frame_crop(self):
        self.changed('FirstFrame', 2)

    def test_rejects_unreviewed_mirror(self):
        self.changed('Mirrored', True)

    def test_rejects_different_source_clock(self):
        self.changed('MidFrames', 0)

    def test_rejects_one_frame_early_overload_marker(self):
        config = copy.deepcopy(CONFIG)
        next(r for r in config['Intervals'] if r['Name'] == 'D13_Bloom_Overload')['Start'] = 27
        with self.assertRaises(ValueError):
            source.validate_configuration(config)

    def test_rejects_corrupt_original_motion(self):
        with self.assertRaises(ValueError):
            source.pinned(b'corrupt', source.PINS['motion'], 'motion')

    def test_rejects_duplicate_zip_member(self):
        buffer = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with ZipFile(buffer, 'w') as archive:
                archive.writestr('a', b'x')
                archive.writestr('a', b'x')
        with ZipFile(io.BytesIO(buffer.getvalue())) as archive:
            with self.assertRaises(ValueError):
                source.checked_member(archive, 'a', (1, hashlib.sha256(b'x').hexdigest()))


def main():
    global CONFIG
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate-profile', type=Path, required=True)
    args = parser.parse_args()
    source.require(args.candidate_profile.is_file() and not args.candidate_profile.is_symlink(),
                   'Use the real private source candidate')
    raw = args.candidate_profile.read_bytes()
    source.pinned(raw, (304421, '40c85f3236903098eb0b20d70002dd0513e93afccad71b0be870f3a4bc8975af'),
                  'verified original Overload source candidate')
    profile = json.loads(raw)
    source.require(profile['id'] == 'liu_serpent' and len(profile['clips']) == 1
                   and profile['recoveryBoundary'] == source.BOUNDARY, 'Candidate identity differs')
    CONFIG = profile['clips'][0]['sourceConfiguration']['configuration']
    source.validate_configuration(CONFIG)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SourceBoundaryTests))
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == '__main__':
    main()
