#!/usr/bin/env python3
"""Bind the verified hound candidate to an exact local Wu profile, offline."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from prepare_erlang_hound import (BONES_SHA, MOTION_SHA, SOURCE_CONFIGURATION_SHA,
                                 ROLE, PARTS, checked, private_output, require, write_private)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def document(candidate, profile):
    require(candidate['schema'] == 'original-d15-hound-candidate-v1'
            and profile['id'] == 'wuyong_erlang' and len(profile['sha256']) == 64,
            'Wrong hound/profile identity')
    track = candidate['track']
    require(track['role'] == ROLE and track['sourceSHA256'] == MOTION_SHA
            and track['boneConfigurationSHA256'] == BONES_SHA
            and track['sourceEndEventTick'] == 110
            and track['frames'] == 60 and len(track['root']) == 119
            and track['attackParts'] == {'primary': PARTS}, 'Wrong source hound track')
    require([t for t in profile.get('summonTracks', []) if t['role'] == ROLE] == [track],
            'Profile physics and companion rendering must bind identical samples')
    value = dict(sourceModel=candidate['sourceModel'], rootBone=candidate['rootBone'],
                 file=candidate['modelFile'], materials=candidate['materials'], track=track,
                 originalMotionFrames=141, firstSourceFrame=1, lastSourceFrame=60,
                 exportFramesPerSecond=30, endEventTick=110,
                 hideStartTick=0, hideEndTick=55, fadeOutTicks=10, fadeInTicks=15)
    return dict(version=1, profileID=profile['id'], characterSHA256=profile['sha256'],
                sourceConfigurationSHA256=SOURCE_CONFIGURATION_SHA, models=[value])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--candidate-sha256', required=True)
    p.add_argument('--profile', type=Path, required=True)
    p.add_argument('--profile-sha256', required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    candidate_raw = checked(a.candidate, a.candidate_sha256, 1_000_000)
    profile_raw = checked(a.profile, a.profile_sha256, 32_000_000)
    candidate, profile = json.loads(candidate_raw), json.loads(profile_raw)
    manifest = document(candidate, profile)
    model = candidate['modelFile']
    require(model['name'] == 'SF3WE_D15_Hound.glb', 'Unexpected companion model filename')
    model_raw = checked(a.candidate.parent / model['name'], model['sha256'], 8_000_000)
    require(len(model_raw) == model['bytes'], 'Companion model size mismatch')
    out = private_output(a.output)
    require(not out.exists() or not any(out.iterdir()), 'Companion assembly directory must be empty')
    out.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(manifest, separators=(',', ':'), allow_nan=False).encode()
    name = 'SF3_D15_Companions.json'
    write_private(out / name, raw)
    write_private(out / model['name'], model_raw)
    receipt = dict(schema='bound-d15-hound-release-v1', profileSHA256=sha(profile_raw),
                   characterSHA256=profile['sha256'], candidateSHA256=sha(candidate_raw),
                   manifest=dict(name=name, bytes=len(raw), sha256=sha(raw)), model=model,
                   exactPhysicsAndPresentationTrack=True, retainedOriginalMotionFrames=141,
                   configuredPlaybackFrames=60, sourceEndEventTick=110,
                   shaderParity=False, publicationPerformed=False)
    write_private(out / 'd15-hound-binding-receipt-private.json',
                  json.dumps(receipt, indent=2, allow_nan=False).encode())
    print(json.dumps(receipt, separators=(',', ':')))


if __name__ == '__main__':
    main()
