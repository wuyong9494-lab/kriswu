#!/usr/bin/env python3
"""Compile verified private H17 trigger actions into reviewable runtime bindings.

This reads the exact source trigger/animation tables. It does not infer effect
timing from a prefab name. Conditional branches that need an additional game
state adapter stay explicit in the review receipt instead of silently becoming
unconditional effects. The large particle document is changed only with --apply.
"""
from __future__ import annotations
import argparse, copy, gzip, hashlib, json
from pathlib import Path
from sun_triad_assets import require, private_output, write_private


def digest(data):
    return hashlib.sha256(data).hexdigest()


def qualifiers(conditions):
    result = {}
    def visit(value, negative=False):
        if isinstance(value, list):
            for item in value: visit(item, negative)
        elif isinstance(value, dict):
            if set(value) == {'Not'}:
                visit(value['Not'], not negative)
            elif 'expr' in value:
                expr=value['expr']
                if len(expr) != 3 or expr[1:] != [1., 'op22']: return
                if isinstance(expr[0], dict) and 'f171' in expr[0]:
                    quality=expr[0]['f171'][0]
                    require(quality in ('min','low','medium','high','ultra'), 'Unknown original quality name')
                    if negative: result.setdefault('sourceExcludedQualities', []).append(quality)
                    else:
                        require('sourceRequiredQuality' not in result, 'Ambiguous source quality condition')
                        result['sourceRequiredQuality']=quality
                elif isinstance(expr[0], dict) and 'f65' in expr[0]:
                    require(expr[0]['f65']==[{'f74':['enum65537']}], 'Mirror condition is not for this model')
                    result['sourceMirrorPose']=not negative
    visit(conditions)
    return result


def effect_action(record, action, index):
    key, values = next(iter(action.items()))
    identity=f"fx_{record['lock']}_{record['setIndex']}_{record['triggerIndex']}_{index}"
    if key=='a46':
        require(len(values)==16, 'Original CustomEffect field count changed')
        name,camera,bone,frames,target,pool,single,local,ymax,ymin,loop,follow,position,shift,additional,params=values
        require(not camera and frames in (None,0) and pool in (None,1)
                and ymax is None and ymin is None and additional is None and params is None,
                'This effect needs an additional exact source adapter')
        require(target in (None,'enum65537','enum65538'), 'Unsupported source effect target')
        require(shift is None or shift==[0.,0.,0.], 'Nonzero source effect shift needs an explicit adapter')
        require(follow is None or len(follow)==3 and all(x in (0.,1.) for x in follow), 'Unsupported source Follow vector')
        value=dict(id=identity,action='play',effect=name,anchor='target' if target=='enum65538' else 'owner',
                   bone=bone,follow=bool(local or follow is not None and any(follow)),
                   attachToLocal=bool(local),looped=bool(loop),sourceFollow=follow,
                   sourceSingleInstance=bool(single))
        if position is not None:
            require(bone is None and not local and follow is None, 'Position is not an absolute arena effect')
            value.update(anchor='arena',sourcePosition=position)
    elif key=='a49':
        require(len(values)==5, 'Original DestroyEffect field count changed')
        name,target,frames,queue,all_effects=values
        require(name and target in (None,'enum65537','enum65538') and not queue and not all_effects,
                'This source DestroyEffect needs queue/all-effect support')
        value=dict(id=identity,action='stop',effect=name,anchor='target' if target=='enum65538' else 'owner',
                   bone=None,follow=False,attachToLocal=False,looped=False,stopFrames=frames or 0)
    else:
        raise ValueError('Unsupported effect action')
    value.update(qualifiers(record['conditions']))
    return value


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source-actions','animations','profile','summons','audio','candidate'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--source-models',type=Path)
    parser.add_argument('--apply', action='store_true')
    args=parser.parse_args();output=private_output(args.candidate)
    source_raw=args.source_actions.read_bytes(); records=json.loads(source_raw)
    animations=json.loads(args.animations.read_bytes())['records']
    profile=json.loads(args.profile.read_bytes()); clips={c['name']:c['frames'] for c in profile['clips']}
    summons=json.loads(args.summons.read_bytes());audio=json.loads(args.audio.read_bytes())
    role_cues={c['event']:c.get('sourceRoles') for c in audio['cues']}
    aliases={r['configuration']['Animation']:r['configuration'] for r in animations}
    markers=[];bindings=[];proofs=[];pending=[]
    by_source={(r['lock'],r['setIndex'],r['triggerIndex']):r for r in records}

    def add_marker(record,value,interval,alias_filter=None):
        matches=[]
        for alias,configuration in aliases.items():
            if alias_filter is not None and alias not in alias_filter: continue
            clip=Path(configuration['FileName']).stem
            if clip not in clips: continue
            for item in configuration['Intervals'] or []:
                if item['Name']!=interval:continue
                frame=max(0,(item['Start'] or 1)-1)
                require(frame<clips[clip], 'Original interval exceeds source clip')
                item_value=dict(value, id=value['id']+'_'+clip, clip=clip,sourceFrame=frame)
                matches.append((alias,item,item_value))
        require(bool(matches), 'Original effect interval is not present in a verified host animation: '+interval)
        seen={m['id'] for m in markers}
        for alias,item,m in matches:
            if m['id'] in seen:
                require(next(x for x in markers if x['id']==m['id'])==m,'Source aliases disagree about an effect marker')
                continue
            seen.add(m['id']);markers.append(m)
            proofs.append(dict(id=m['id'],lock=record['lock'],set=record['set'],trigger=record['triggerIndex'],
                sourceSHA256=record['sourceSHA256'],sourceAnimation=alias,sourceInterval=item,
                timing='Original interval Start minus one; source 30 Hz samples, 60 Hz live playback.'))

    def add_binding(record,value,event,suffix='',**fields):
        v=dict(value,id=value['id']+suffix,event=event,**fields);bindings.append(v)
        proofs.append(dict(id=v['id'],lock=record['lock'],set=record['set'],trigger=record['triggerIndex'],
            sourceSHA256=record['sourceSHA256'],sourceEvents=record['events'],sourceConditions=record['conditions']))

    for record in records:
        lock,trigger=record['lock'],record['triggerIndex']
        for ai,action in enumerate(record['effectActions']):
            value=effect_action(record,action,ai)
            if lock==1779 and trigger not in (20,):
                intervals=[e['a18'][1] for e in record['events'] if 'a18' in e]
                require(len(intervals)==1, 'Host effect trigger does not have one source interval')
                add_marker(record,value,intervals[0])
            elif lock==1779 and trigger==20:
                add_binding(record,value,'mistBladeEnded')
                add_binding(record,value,'sourceRoundFightEnded','_round_end')
            elif lock==1776:
                value['anchor']='sourceModel'
                if trigger==1:
                    add_binding(record,value,'sourceRootModelCreated')
                elif trigger==4:
                    # Core rootModelEnded combines the original parent-expiry,
                    # round-end and failed-start exit paths, once per model ID.
                    add_binding(record,value,'sourceRootModelEnded')
                elif trigger in (5,6):
                    proofs.append(dict(id=value['id'],sourceEquivalentTo='sourceRootModelEnded',
                        lock=lock,trigger=trigger,sourceSHA256=record['sourceSHA256'],
                        sourceEvents=record['events'],sourceConditions=record['conditions']))
                else:raise ValueError('Unknown root model effect trigger')
            elif lock==1795:
                event='sourceSoulModelCreated' if trigger==2 else 'sourceSoulAnimationEnded'
                require(trigger in (2,3) and role_cues[event], 'Exact soul role lifecycle is missing')
                value['anchor']='sourceModel'
                add_binding(record,value,event,sourceRoles=role_cues[event])
            elif lock==1796 and trigger in (2,3):
                value.update(sourcePositionCondition=dict(left='targetCOMX',
                    comparison='lessOrEqual' if trigger==2 else 'greater',right='ownerCOMX'),
                    sourceOncePerRound='H17_LOSS_EFFECTS')
                winning_aliases={name for name,c in aliases.items() if 'STANCE_WIN_POSE' in (c['Groups'] or [])}
                add_marker(record,value,'H17_Win_FX_Start',winning_aliases)
                pending.append(dict(runtimeCandidate=value,sourceRecord=record,
                    reason='The original IntervalStart branch is bound. The alternative enemy LOSS AnimationStart branch additionally requires the owner H17_Win_FX_Start_Enemy interval and enemy not in LOSS_IDLE.'))
            elif lock==1796 and trigger in (4,5,6,7):
                interval=record['events'][0]['a18'][1]
                alias_filter={4:{'H17_Stance_Round_Win'},5:{'H17_Stance_Win'}}.get(trigger)
                add_marker(record,value,interval,alias_filter)
            elif lock==1797:
                add_marker(record,value,record['events'][0]['a18'][1])
            elif lock==1800:
                add_binding(record,value,'sourceRoundStarted',loopUntil='sourceRoundFightEnded')
                # This native arena has no original intro yet. Its explicit
                # first-round ambience adapter uses the source continuing
                # forest, without pretending the 201-frame intro was played.
                add_binding(record,value,'arenaForestLoopStarted','_arena_adapter',loopUntil='sourceRoundFightEnded')
            elif lock in (1798,1801):
                # Exact NPC branch differs only by opponent-H17 exclusion.
                # The native arena selects a single H17 arena owner globally.
                proofs.append(dict(id=value['id'],sourceEquivalentTo='single H17 arena owner selection',
                    lock=lock,trigger=trigger,sourceSHA256=record['sourceSHA256'],
                    sourceEvents=record['events'],sourceConditions=record['conditions']))
            elif lock==1799 and trigger in (1,2,3):
                value['sourceRoundScope']='first'
                if trigger in (2,3):
                    value['sourcePositionCondition']=dict(left='ownerPelvisX',
                        comparison='less' if trigger==2 else 'greaterOrEqual',right='zero')
                add_binding(record,value,'sourceRoundStarted')
            elif lock==1799 and trigger in (5,6):
                value['sourcePositionCondition']=dict(left='ownerPelvisX',
                    comparison='less' if trigger==5 else 'greaterOrEqual',right='zero')
                add_marker(record,value,record['events'][0]['a18'][1])
            elif lock==1799 and trigger==7:
                add_marker(record,value,record['events'][0]['a18'][1])
            else:
                pending.append(dict(runtimeCandidate=value,sourceRecord=record,
                    reason='Exact win/intro state and coordinate conditions require the corresponding source lifecycle selector.'))
    require(len({v['id'] for v in markers})==len(markers),'Duplicate effect marker')
    require(len({v['id'] for v in bindings})==len(bindings),'Duplicate effect binding')
    result=dict(version=1,profileID='sun_triad',characterSHA256=profile['sha256'],sourceQuality='high',
        sourceMirrorPose=False,sourceConfigurationSHA256=digest(source_raw),bindings=bindings,markers=markers)
    patch_path=output/'h17-source-effect-bindings-patch-private.json'
    write_private(patch_path,json.dumps(result,indent=2,allow_nan=False).encode())
    receipt=dict(sourceActionsSHA256=digest(source_raw),sourceAnimationsSHA256=digest(args.animations.read_bytes()),
        bindings=len(bindings),markers=len(markers),runtimeProofs=proofs,pendingExactSourceConditions=pending,
        attachmentNativeMethods=[29447,29489,182174,34303,34309],
        stopFrameRule='Raw DestroyEffect Frames are original 60 Hz simulation counter ticks, without the animation stride multiplier.',
        stopNativeProof='h17-effect-stop-native-proof-private.json',
        stopShaderUniform='_Transparent',stopCompletion='Deactivate effect after the original frame counter duration.')
    write_private(output/'h17-source-effect-binding-provenance-private.json',json.dumps(receipt,indent=2,allow_nan=False).encode())
    if args.apply:
        doc=json.loads((output/'SF3_H17_Effects.json').read_bytes())
        for field in ('characterSHA256','sourceConfigurationSHA256','sourceQuality','bindings','markers'):
            doc[field]=result[field]
        model_path=args.source_models or output/'h17-source-model-tracks-patch-private.json'
        source_models=json.loads(model_path.read_bytes())['sourceModels']
        require(set(source_models)=={'roots','rootAttack','mistWave'},'Independent source model tracks are incomplete')
        doc['sourceModels']=source_models
        for value in bindings+markers:
            require(value['effect'] in doc['effects'],'Binding references an absent source effect')
        raw=json.dumps(doc,separators=(',',':'),allow_nan=False).encode();compressed=gzip.compress(raw,mtime=0)
        require(len(raw)<=256_000_000 and len(compressed)<=32_000_000,'Bounded FX document exceeded')
        write_private(output/'SF3_H17_Effects.json',raw);write_private(output/'SF3_H17_Effects.json.gz',compressed)
    print(json.dumps(dict(patch=str(patch_path),bindings=len(bindings),markers=len(markers),pending=len(pending),applied=args.apply)))


if __name__=='__main__':main()
