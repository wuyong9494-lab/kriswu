#!/usr/bin/env python3
"""Append the original Imperial passive mirror without rebuilding 54 clips.

The source arrays are already in the authenticated profile. Native body mirror
rules are applied after local half-frame nlerp, then every runtime track is
sampled from the exact same exported 60 Hz poses. Source media is not fetched.
"""
from __future__ import annotations

import argparse
import base64
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np

from build_erlang_source_assets import CONFIGS, append_motion, checked, encoded, record, sha, write_new
from erlang_source_profile import SETTINGS_SHA, combat_rules
from source_body_mirroring import body_rules
import source_body_mirroring
from sun_triad_assets import Writer, glb_read, private_output, require
from sun_triad_source_bones import parse_bones_data

ROLE = 'imperialHeavyPassiveMirrored'
CLIP = 'imperial_spear_heavy_slash_passive_mirrored'
ALIAS = 'Imperial_Spear_Heavy_Slash_Passive_Mirror'


def append(args):
    profile_raw=checked(args.profile,args.profile_sha256,48_000_000)
    profile=json.loads(profile_raw)
    original_clips=len(profile['clips'])
    require(profile['id']=='wuyong_erlang' and original_clips in (54,55) and ROLE not in profile['roles'],
            'Expected intact Wu source candidate without the mirror variant')
    model_path=args.profile.parent/(profile['resourceName']+'.glb')
    model_raw=checked(model_path,profile['sha256'],48_000_000)
    require(len(model_raw)==profile['bytes'],'Source actor size differs')
    g,b=glb_read(model_path)
    before=copy.deepcopy(g)
    writer=Writer();writer.g=g;writer.b=bytearray(b[:g['buffers'][0]['byteLength']])
    original_binary=bytes(writer.b)
    names={row['name']:row['targetNode'] for row in profile['sourceBoneBindings']}
    bone_ids={row['sourceID']:row['name'] for row in profile['sourceBoneBindings'] if row['sourceID'] is not None}
    require(len(names)==len(profile['sourceBoneBindings']) and
            all(g['nodes'][node]['name']==name for name,node in names.items()),'Source rig mapping differs')
    configs={};base_raw=None
    for kind,(name,pin) in CONFIGS.items():
        folder=args.source_configs if kind=='weapon' else args.shared_bones
        raw=checked(folder/name,pin,1_000_000)
        configs[kind]=parse_bones_data(raw)
        if kind=='base':
            base_raw=raw
            configs[kind]['masses']={b.get('Name'):float(b.get('Mass','0')) for b in ET.fromstring(raw).findall('./Bones/Bone')}
    source=next(c for c in profile['clips'] if c['name']==profile['roles']['imperialHeavyPassive'])
    require(source['sha256']=='75e0ec9ac3674098657aac66d6c3ee51b66f342234aae2a7b33fc3a666a6c411',
            'Wrong original Imperial passive object')
    raw=base64.b64decode(source['sourceBytesBase64'],validate=True)
    require(sha(raw)==source['sha256'],'Retained original motion bytes differ')
    info=dict(name=source['name'],frames=source['sourceUncroppedFrames'],bytes=len(raw),
        sha256=source['sha256'],bundle=source['bundle'],path_id=int(source['sourcePathID']))
    settings=json.loads(checked(args.settings,SETTINGS_SHA,4_000_000))
    rows=[r for r in settings['records'] if r['configuration']['Animation']==ALIAS]
    require(len(rows)==1 and rows[0]['configuration']['Mirrored']==-1,'Original mirror alias is missing')
    clip=append_motion(writer,names,bone_ids,configs,info,raw,rows[0],
        mirror_rules=body_rules(base_raw),export_name=CLIP)
    require(clip['frames']==71 and clip['playbackTicks']==140 and clip['sourceEndEventTick']==132
            and len(clip['tracks']['toeL'])==len(clip['tracks']['toeR'])==141,'Mirror source window differs')
    profile['clips'].append(clip);profile['roles'][ROLE]=CLIP
    old_attacks=profile['combatRules']['attacks']
    profile['combatRules'],missing_receipts=combat_rules(profile,settings)
    require(old_attacks==profile['combatRules']['attacks'],'Mirror export changed normal attack rules')
    require(g['animations'][:-1]==before['animations'] and len(g['animations'])==original_clips+1,
            'Mirror append changed a successful existing animation')
    for key in ('nodes','meshes','materials','skins','textures','images','samplers','scenes'):
        require(g[key]==before[key],'Mirror append changed '+key)
    require(bytes(writer.b[:len(original_binary)])==original_binary,'Mirror append changed original buffer bytes')
    difference=float(np.max(np.abs(np.asarray(clip['tracks']['toeL'])-np.asarray(source['tracks']['toeL']))))
    require(difference>.001,'Mirror variant is just the unmirrored track')
    require(not args.output.exists(),'Refuse to replace a candidate')
    output=private_output(args.output)
    identity=writer.save(output/model_path.name)
    profile.update(identity)
    write_new(output/'SF3_Erlang_Profile.json',encoded(profile))
    receipt=dict(sourceProfile=record(args.profile),character=record(output/model_path.name),
        profile=record(output/'SF3_Erlang_Profile.json'),sourceAlias=ALIAS,role=ROLE,clip=CLIP,
        frames=71,exportKeys=141,exportFramesPerSecond=60,playbackTicks=140,sourceEndEventTick=132,
        existingAnimationsUnchanged=original_clips,originalEmbeddedBytesUnchanged=len(original_binary),
        originalMotionSHA256=source['sha256'],sourceBonesSHA256=sha(base_raw),
        mirrorHelperSHA256=sha(Path(source_body_mirroring.__file__).read_bytes()),
        maximumToeDifferenceFromUnmirroredMeters=difference,
        nativeMethods=[38157,39217,39218,39219,39220,39221,39222,39223,39224,39225,39226,39227,39228,39229,39261,39262,39277],
        boundaries=['Source local half-frame nlerp precedes rest-relative Euler mirroring.',
                    'This is the reviewed nonsingular passive motion; unreviewed singular input is rejected.',
                    'Portable float64 Euler evaluation then float32 GLB storage; no claim of native bitwise equivalence.',
                    'Every FK/COM/toe/capsule track is recomputed on the unchanged Wu rig from those exported poses.'],
        ignoredOriginalCapsuleNames=[r for r in missing_receipts if r['unresolvedConfiguredPartNames']])
    write_new(output/'erlang-mirrored-passive-private.json',encoded(receipt))
    return {k:v for k,v in receipt.items() if k not in ('ignoredOriginalCapsuleNames','nativeMethods','boundaries')}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('profile','settings','shared-bones','source-configs','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--profile-sha256',required=True)
    print(json.dumps(append(parser.parse_args())))


if __name__=='__main__':main()
