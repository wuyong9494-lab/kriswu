#!/usr/bin/env python3
"""Equivalently rebind authenticated D15 media to the fitted contour actor.

All PCM, sampled effects, source shaders, textures, clocks and omitted emitter
scope remain exact. Only current actor/profile identities change. Original
recovered-source provenance remains its original identity, not a new claim.
"""
from __future__ import annotations

import argparse
import copy
import gzip
import json
from pathlib import Path

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from recover_erlang_source_audio import NECK_PROFILE_SHA, NECK_CHARACTER_SHA
from bind_erlang_recovered_effects import re_safe_name
from sun_triad_assets import private_output, require


CONTOUR_PROFILE_SHA = '05ebdc38393bb55b7053a4664f317f81d0c2532bd43c8c50bb313cc513b18d03'
CONTOUR_CHARACTER_SHA = '2957d7861b2ee7656945259dd273f241591ce55f71d364dab007a9bc372d76f6'
INPUTS = {
    'audio': ('erlang-audio-runtime-v5', 'SF3_Erlang_Audio.json',
              '04b88bff0b112190b180b8e5de16956a60bf6419de03d944a1d8fa46124f7003', 82),
    'hound': ('erlang-hound-runtime-v1/runtime', 'SF3_D15_Effects.json.gz',
              'e880416974d61ff86b901e28cd5ec186a67cd0ee935459c5755931a33f3a3ab9', 25),
    'stomp': ('erlang-fx-runtime-v1/stomp', 'SF3_D15_StompEffects.json.gz',
              'f9ba45ec8bea159aa2ecd5328fac971b10ec6ab91dde30563c037be80313a882', 9),
    'sword': ('erlang-fx-runtime-v1/sword', 'SF3_D15_SwordEffects.json.gz',
              '93328c90b9736f65973f503b954403bd5466974b8216520508e080c9159e95f7', 39),
    'skill': ('erlang-skill-runtime-v1/runtime', 'SF3_D15_SkillEffects.json.gz',
              'da87f5333f5311624ca2e82c9c3637d3771e18f17f500666487eb2cfe1655639', 100),
}


def equivalent_profiles(prior, current):
    require(prior['sha256'] == NECK_CHARACTER_SHA and current['sha256'] == CONTOUR_CHARACTER_SHA,
            'Unexpected authenticated actor generation')
    left, right = copy.deepcopy(prior), copy.deepcopy(current)
    for key in ('sha256', 'bytes', 'personalNeckBridge'):
        left.pop(key); right.pop(key)
    require(left == right, 'A source actor rule, motion, role or independent model changed during fitting')
    bridge = current['personalNeckBridge']
    require(bridge['fitting'] == 'original-open-contour-v2'
            and bridge['originalPortraitVerticesChanged'] == 0
            and bridge['originalBoundaryHalfEdges'] == 182
            and bridge['originalPositionQuantizationUsed'] is False
            and bridge['sourceEndpointNormalsAndUVColour'] is True
            and bridge['bodyBoundaryVertices'] == 15
            and bridge['dynamicBodyVertexAttributesPreserved'] is True
            and bridge['localSourceHoleEdges'] == 10,
            'Expected the inspected authentic contour fitting')
    require(len(current['clips']) == 62 and len(current['summonTracks']) == 15
            and current['recoveryBoundary']['productionActivation'] is False,
            'Recovered source scope or production boundary changed')


def retarget(kind, document, prior, current):
    equivalent_profiles(prior, current)
    require(document['profileID'] == current['id'] == 'wuyong_erlang'
            and document['characterSHA256'] == NECK_CHARACTER_SHA,
            'Media do not describe the authenticated prior fitted actor')
    result = copy.deepcopy(document)
    result['characterSHA256'] = CONTOUR_CHARACTER_SHA
    if kind == 'audio':
        require(document['profileSHA256'] == NECK_PROFILE_SHA and document['schemaVersion'] == 5,
                'Expected the actual recovered schema-5 audio manifest')
        result['profileSHA256'] = CONTOUR_PROFILE_SHA
    # This equality deliberately covers every clock, source identity, sample,
    # material, unplayed cue and known missing emitter, without a field allowlist.
    reverted = copy.deepcopy(result)
    reverted['characterSHA256'] = document['characterSHA256']
    if kind == 'audio':
        reverted['profileSHA256'] = document['profileSHA256']
    require(reverted == document, 'Retargeting changed immutable recovered source media')
    return result


def build(args):
    prior_path = args.work_root/'erlang-neck-v1/SF3_Erlang_Profile.json'
    prior = json.loads(checked(prior_path, NECK_PROFILE_SHA, 24_000_000))
    profile_raw = checked(args.profile, CONTOUR_PROFILE_SHA, 24_000_000)
    current = json.loads(profile_raw)
    equivalent_profiles(prior, current)
    model_name = current['resourceName'] + '.glb'
    model_path = args.profile.parent/model_name
    model = checked(model_path, CONTOUR_CHARACTER_SHA, 24_000_000)
    require(len(model) == current['bytes'], 'Current contour actor size differs')
    prepared, resources = [], {}
    for kind, (directory_name, name, digest, count) in INPUTS.items():
        directory = args.work_root/directory_name
        raw = checked(directory/name, digest, 8_000_000)
        document = json.loads(gzip.decompress(raw) if name.endswith('.gz') else raw)
        require(len(document['files']) == count, 'Recovered resource inventory differs: ' + kind)
        for row in document['files']:
            resource = row['name']
            require(re_safe_name(resource), 'Unsafe original media name')
            data = checked(directory/resource, row['sha256'], 32_000_000)
            require(len(data) == row['bytes'], 'Recovered resource byte count differs')
            require(resource not in resources or resources[resource] == data,
                    'Different original media share a resource name')
            resources[resource] = data
        result = retarget(kind, document, prior, current)
        prepared.append((kind, name.removesuffix('.gz'), digest, encoded(result)))
    require(not args.output.exists(), 'Use a new private contour media destination')
    output = private_output(args.output)
    write_new(output/model_name, model)
    write_new(output/'SF3_Erlang_Profile.json', profile_raw)
    for name, data in resources.items():
        write_new(output/name, data)
    groups = []
    for kind, name, source_digest, data in prepared:
        write_new(output/name, data)
        item = dict(kind=kind, sourceManifestSHA256=source_digest, manifest=record(output/name),
                    currentIdentityOnlyChanged=True)
        if kind != 'audio':
            write_new(output/(name + '.gz'), gzip.compress(data, mtime=0))
            item['compressedManifest'] = record(output/(name + '.gz'))
        groups.append(item)
    receipt = dict(schema='d15-contour-actor-equivalent-media-binding-v1',
        sourceProfile=record(prior_path), profile=record(output/'SF3_Erlang_Profile.json'),
        character=record(output/model_name), groups=groups,
        referencedMediaFiles=sum(row[3] for row in INPUTS.values()),
        uniqueMediaFiles=len(resources), uniqueMediaBytes=sum(len(data) for data in resources.values()),
        originalPCMAndSourceFXBytesUnchanged=True, sourceClocksAndBindingsUnchanged=True,
        recoveredSourceProvenanceUnchanged=True, knownUnboundEmittersPreserved=True,
        originalSourceAnimationCount=62, productionPinsChanged=False,
        nativeRenderingVerified=False, nativePlaybackVerified=False)
    write_new(output/'erlang-contour-media-binding-private.json', encoded(receipt))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('work-root', 'profile', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    print(json.dumps(build(parser.parse_args()), allow_nan=False))


if __name__ == '__main__':
    main()
