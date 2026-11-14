#!/usr/bin/env python3
"""Export original independent H17 root/wave model FK and attack capsules.

Only the model's declared BonesData IDs bind motion channels. Extra authored
motion IDs are recorded, never guessed into an invented skeleton hierarchy.
The result contains source RIGHT-facing transforms in glTF meters, with no
fighter outer rotation or personal scale. The original player turns the root
180 degrees around Y for RIGHT (39193); this is distinct from the display
rotation of a personal fighter model.
"""
from __future__ import annotations
import argparse, hashlib, json, warnings
from pathlib import Path
import numpy as np
from sun_triad_assets import C, CI, decode, matrix, pose_world, require, private_output, write_private
from sun_triad_spirits import source_rig
from sun_triad_source_bones import parse_bones_data

MODEL_BUNDLE='3719ae2b78ab1968e0ffdb31081cb1c0.bin'
MODEL_SHA='85ee3665f55ea2d7517a9b17414e9806aa0a201782cf66eeb9bc6d725f916dc4'
BONES='3719ae2b78ab1968e0ffdb31081cb1c0_5334929850884102527_bones.textasset-private.clear-private'
BONES_SHA='27902c22151fa33d2bc45b163bb9d4ca106f4c934a36013eb31bb37a35dbfbd7'
MOTION_BUNDLE='9893dca6e10355eb9c3c79d1613f08b1.bin'
SOURCE_RIGHT=np.diag([-1.,1.,-1.,1.])
MOTIONS={
    'roots':('h17_root_spike_model','c33a9c85a17542ab436c380ebbc5a116e7b51ec4a67df2a022ce6674ee9d5a11',
             'H17_Root_Spike_Model_Start',31),
    'mistWave':('h17_wave_model','ef3cb604495fe6c111c4e5ce5daa9030dd55b8c71437cb3a64e2d520666d6b2d',
                'H17_Illusion_Wave_Model_Attack',22),
}


def sha(raw):return hashlib.sha256(raw).hexdigest()


def right_facing_samples(worlds, root_index):
    """Return exact RIGHT poses anchored at the initial source Align pivot X.

    FX retains full motion after the birth-time X alignment. Core extracts the
    same root motion once; its collision endpoints are relative to current X.
    The model has no source Y/Z Align, so neither axis is removed.
    """
    right=[[SOURCE_RIGHT @ m for m in frame] for frame in worlds]
    root=np.array([frame[root_index][:3,3] for frame in right])
    for frame in right:
        for m in frame:m[0,3]-=root[0,0]
    return right,root


def core_capsule_from_fx(record, root):
    result=dict(id=record['id'],defense='body',radiusMillimeters=record['radiusMillimeters'])
    delta=root[:,0]-root[0,0]
    for endpoint in ('base','tip'):
        points=np.array(record[endpoint],dtype=float)
        points[:,0]-=delta
        result[endpoint]=np.round(points,9).tolist()
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('models','motions','animations','output'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();output=private_output(args.output)
    import UnityPy
    UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1'
    warnings.filterwarnings('ignore',category=Warning,module='UnityPy')
    bundle=(args.models/MODEL_BUNDLE).read_bytes();require(sha(bundle)==MODEL_SHA,'Model bundle identity mismatch')
    bone_raw=(args.models/BONES).read_bytes();require(sha(bone_raw)==BONES_SHA,'Original model BonesData identity mismatch')
    bone_data=parse_bones_data(bone_raw)
    env=UnityPy.load(bundle)
    path='assets/gamedata/resources/content/items/models/mgc__common_model_40/m/prefabs/m_common_model_40.prefab'
    rows=source_rig(env.container[path]);names={r['name']:i for i,r in enumerate(rows)}
    require(all(np.allclose(r['scale'],[1.,1.,1.],atol=1e-7,rtol=0) for r in rows),
            'Dynamic or non-unit model scale requires per-sample capsule radius support')
    require(set(bone_data['bones'])==set(range(400,405)), 'Actual original model ID inventory differs')
    require(all(name in names for name in bone_data['bones'].values()),'Model bone is absent from original prefab')
    parents={i:names[r['parent']] for i,r in enumerate(rows) if r['parent'] is not None}
    rest=[C@matrix(r['translation'],r['rotation'],r['scale'])@CI for r in rows]
    configuration=json.loads(args.animations.read_bytes())
    aliases={r['configuration']['Animation']:r['configuration'] for r in configuration['records']}
    models={};core_models={};capsule_records=[];proofs=[]
    for kind,(stem,source_sha,alias,expected_frames) in MOTIONS.items():
        raw=(args.motions/(stem+'.bytes')).read_bytes();require(sha(raw)==source_sha,'Original model motion identity mismatch')
        arrays=decode(raw);require(len(arrays)==2,'Unexpected model motion array count')
        a=arrays[0];frames=a['frame_count'];require(frames==expected_frames,'Model source frame count changed')
        setting=aliases[alias]
        require(setting['SelfEndFrame']==0 and setting['FirstFrame'] is None and setting['EndFrame'] is None,
                'Independent model source end-event or crop changed')
        columns={bone_data['bones'][int(i)]:j for j,i in enumerate(a['bone_ids']) if int(i) in bone_data['bones']}
        require(set(columns)==set(bone_data['bones'].values()),'Model motion is missing a source-declared bone')
        unbound=[int(i) for i in a['bone_ids'] if int(i) not in bone_data['bones']]
        require(unbound==[406,405], 'Unexpected undeclared source model channels')
        transforms={name:[] for name in columns};worlds=[]
        for sample in range(2*frames-1):
            first=sample//2;second=min(first+1,frames-1);fraction=(sample%2)*.5;local=[m.copy() for m in rest]
            for name,column in columns.items():
                position=a['positions'][first,column].astype(float)*(1-fraction)+a['positions'][second,column].astype(float)*fraction
                qa=a['rotations'][first,column].astype(float);qb=a['rotations'][second,column].astype(float)
                if qa@qb<0:qb=-qb
                rotation=qa*(1-fraction)+qb*fraction
                local[names[name]]=C@matrix(position,rotation,rows[names[name]]['scale'])@CI
            world=pose_world(local,parents);worlds.append(world)
        worlds,root=right_facing_samples(worlds,names['magic_joint_root'])
        for world in worlds:
            for name in columns:transforms[name].append(np.round(world[names[name]].T.reshape(-1),9).tolist())
        model=dict(sourceModel='mgc__common_model_40',clip=stem,frames=frames,
            sourceSHA256=source_sha,sourceBoneConfigurationSHA256=BONES_SHA,
            samplesPerSourceFrame=2,bones=transforms,endEventTick=2*(frames-1))
        models[kind]=model
        source_aliases=[c for c in aliases.values() if Path(c['FileName']).stem==stem]
        require(all(interval['Type'] in ('Attack','NoWallRepulsion') and
                    interval.get('StartScale') is None and interval.get('TargetScale') is None and
                    interval.get('ScaleBone') is None
                    for c in source_aliases for interval in c['Intervals'] or []),
                'Original model has a scale or additional interval requiring a runtime adapter')
        selected={part for c in source_aliases for interval in c['Intervals'] or []
            if interval['Type']=='Attack' for part in interval['AttackingParts'] or []}
        core_capsules=[]
        for capsule in bone_data['capsules']:
            if capsule['id'] not in selected:continue
            record=dict(kind=kind,id=capsule['id'],radiusMillimeters=round(capsule['radiusCentimeters']*10),base=[],tip=[])
            for world in worlds:
                for end in ('base','tip'):
                    vertex=capsule[end];p=np.array([*vertex['localPositionCentimeters'],1.])
                    result=world[names[vertex['bone']]]@C@p
                    record[end].append(np.round(result[:3],9).tolist())
            capsule_records.append(record)
            core_capsules.append(core_capsule_from_fx(record,root))
        require(len(core_capsules)==1 and {c['id'] for c in core_capsules}==selected,
                'Source independent model attack capsule inventory changed')
        core_models[kind]=dict(role='triadModel_'+kind,clip=stem,frames=frames,
            sourceSHA256=source_sha,sourceBundle=MOTION_BUNDLE,root=np.round(root,9).tolist(),
            groundLift=[0.]*(2*frames-1),boneConfigurationSHA256=BONES_SHA,
            collisionEdges=[],hurtCapsules=core_capsules,attackParts=dict(primary=sorted(selected)))
        for fx_capsule,core_capsule in zip(capsule_records[-len(core_capsules):],core_capsules):
            for endpoint in ('base','tip'):
                reconstructed=np.array(core_capsule[endpoint]);reconstructed[:,0]+=root[:,0]-root[0,0]
                require(np.allclose(reconstructed,fx_capsule[endpoint],atol=2e-9,rtol=0),
                        'Core and FX model samples do not reconstruct the same capsule')
        proofs.append(dict(kind=kind,sourceMotionSHA256=source_sha,sourceArrayCount=2,
            declaredBoneIDs=sorted(bone_data['bones']),unboundMotionIDs=unbound,
            unboundPolicy='No source BonesData declaration or prefab binding: do not invent a node/parent for the authored channel.',
            sourceAliases=source_aliases,
            sourceModelCoordinates='Original model-local FK; Unity Z reflected, centimeters to meters, original RIGHT rotation Ry(pi), then subtract initial root X for exact source Align. No actor .92 scale or -90 degree display rotation.',
            sourceFacingMethods=[39173,39193,179494,111137],
            sourceAlignMethod=39421,
            sourceAlignShiftRule='The executing model direction LEFT=2 negates Shift.X; RIGHT=1 preserves it. Target direction is not used.',
            sourceRootInitialX=float(root[0,0]),
            coreRootRule='Core capsule X subtracts current root X; root.offsetX adds current minus first once. FX matrices keep full motion minus first root X, so birth sourceOrigin is fixed.',
            sourceScaleRule='Every original model prefab scale is one; motion arrays contain position and quaternion only. Capsule radius is the original BonesData radius without personal fighter scaling.',
            sourceInterpolationRule='Original ordinary playback 39197 -> 39198 is linear. Second-array Bezier interpolation is selected only by the original slow-motion controller flag (37593/34531/34534).',
            sourceEndEventRule='SelfEndFrame is explicitly zero, so endEventTick equals 2*(frames-1), with no default four-frame subtraction.'))
    attack=aliases['H17_Root_Spike_Model_Attack']
    require(attack['FirstFrame']==20 and attack['EndFrame']==30 and attack['SelfEndFrame']==0,
            'Root attack crop has changed')
    roots=models['roots']
    models['rootAttack']=dict(roots,frames=11,endEventTick=20,
        bones={name:values[38:59] for name,values in roots['bones'].items()})
    write_private(output/'h17-source-model-tracks-patch-private.json',json.dumps(dict(sourceModels=models),separators=(',',':'),allow_nan=False).encode())
    write_private(output/'h17-source-model-capsules-private.json',json.dumps(dict(version=1,samplesPerSourceFrame=2,
        coordinateBasis='Same RIGHT-facing glTF meter basis as sourceModels, initial root X removed; apply fixed birth sourceOrigin and LEFT mirroring separately.',
        capsules=capsule_records),separators=(',',':'),allow_nan=False).encode())
    core_path=output/'SF3_H17_Model_Tracks.json'
    write_private(core_path,json.dumps(core_models,separators=(',',':'),allow_nan=False).encode())
    write_private(output/'h17-source-model-provenance-private.json',json.dumps(dict(sourceBundle=MODEL_BUNDLE,
        sourceBundleSHA256=MODEL_SHA,sourcePrefabPath=path,sourceBoneConfigurationSHA256=BONES_SHA,
        originalPrefabHierarchy=rows,sourceDeclarations=bone_data,models=proofs),indent=2,allow_nan=False).encode())
    print(json.dumps(dict(sourceModels=list(models),bonesPerModel={k:len(v['bones']) for k,v in models.items()},
        samples={k:2*v['frames']-1 for k,v in models.items()},capsules=len(capsule_records),
        coreTracks=dict(file=str(core_path),bytes=core_path.stat().st_size,sha256=sha(core_path.read_bytes())))))


if __name__=='__main__':main()
