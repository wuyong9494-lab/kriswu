#!/usr/bin/env python3
"""Bind already recovered PCM to exact actor/model clocks; never decode media.

Private source inputs remain outside git. Missing model bindings stay explicit
pending entries, never aliases to an owner's cast phase. Final profile and GLB
identity are authenticated before producing a runtime manifest.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from build_erlang_source_assets import checked, encoded, record, write_new, sha
from sun_triad_assets import private_output, require

INPUT_SHA = '01649a542d8a20cbe66e9e1bee831201c3c70cdd4200c6f0b1b23c66e88aa9fd'
ORDINARY_INPUT_SHA = '7296d0f5152bf07b34c532f621b5ffc3b91e92e00ab69f898325c9a7b6a41ea3'
MEDITATION_TRIGGER_SHA = '77cdd96fb7649acb2d9f1e93d68155f1df7fab5a99dc94e3199c058c2fce21b1'
FLOOR_INPUT_SHA = '8e43cbe4b0f4d63cedb64f9b8f386dd992f12e3922daef4e9219bd9e1849a41d'
FLOOR_SOURCE_SHA = 'aed69b0fe5f39de00bd3871a5361f4b8d887e9ba9753302546dcc0cb97e109c3'
PALACE_SHA = '185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8'
CONFIG_SHA = '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'
DEFAULT_MODELS = {
    'D15_Ability_Dog_Attack_Model': dict(role='erlangSummon_hound',
        sourceMotionSHA256='6443c760202bf084ae030d81b419f8494db1f4aa2e7c7904c40054bdf924b712'),
}
DEFERRED = {
    'd15_meditation': 'awaiting-exact-source-trigger',
    'd15_swords_explosion': 'no-active-reference-in-reviewed-source-scope',
}
MODEL_ALIASES = {'D15_Ability_Dog_Attack_Model','D15_Meditation_Explosion_Model_Attack_Damage',
                 'D15_Hovering_Sword_Model_Attack','D15_Avatara_Axe_Ground_Model_Attack'} | {
                    f'D15_Hovering_Sword_Model_Birth_{n}' for n in range(1,7)}
MODEL_ROLES = {
    'D15_Ability_Dog_Attack_Model': 'erlangSummon_hound',
    'D15_Meditation_Explosion_Model_Attack_Damage': 'erlangSummon_meditation',
    'D15_Hovering_Sword_Model_Attack': 'erlangSummon_sword',
    'D15_Avatara_Axe_Ground_Model_Attack': 'erlangSummon_aftershock',
    **{f'D15_Hovering_Sword_Model_Birth_{n}': f'erlangSummon_swordBirth{n}' for n in range(1,7)},
}


def bind_marker(event, profile, models):
    name = Path(event['sourceMotion']).stem
    role, model_role, clip = None, None, None
    ordinary = event.get('id', '').startswith(('ordinary_', 'floor_'))
    if ordinary:
        require(profile['roles'].get(event['role']) == event['clip'], 'Ordinary source role is not admitted')
        name = event['clip']
        candidates = [c for c in profile['clips'] if c['name'] == name and
                      c['sha256'] == event['sourceMotionSHA256'] and c['frames'] == event['sourceFrames'] and
                      c['playbackTicks'] == event['duration']]
        require(len(candidates) == 1, 'Ordinary source motion identity or full clock differs')
    else:
        candidates = [c for c in profile['clips'] if c['name'] == name and c.get('sourceConfiguration')
                      and c['sourceConfiguration']['sourceSHA256'] == event['sourceSHA256']
                      and c['sourceConfiguration']['sourceRecordIndex'] == event['sourceRecordIndex']]
    require(len(candidates) <= 1, 'Ambiguous actor source identity')
    if candidates:
        clip = candidates[0]
        roles = [r for r,n in profile['roles'].items() if n == name]
        require(len(roles) == 1, 'Ambiguous actor motion role')
        role = roles[0]
        require(clip['sourceFirstIndex'] == event['sourceFirstIndex'], 'Actor crop origin differs')
        frames, duration, motion_sha = clip['frames'], clip['playbackTicks'], clip['sha256']
    elif event['animationAlias'] in models:
        model = models[event['animationAlias']]
        require(model['role'] == MODEL_ROLES.get(event['animationAlias']),
                'A model source alias cannot borrow another instance animation clock')
        candidates = [t for t in profile.get('summonTracks',[]) if t['role'] == model['role']]
        if candidates:
            require(len(candidates) == 1, 'Ambiguous model source role')
            clip = candidates[0]
            require(clip['clip'] == name and clip['sourceSHA256'] == model['sourceMotionSHA256'],
                    'Model original motion identity differs')
            require(model.get('sourceFirstIndex',event['sourceFirstIndex']) == event['sourceFirstIndex'],
                    'Model crop origin differs')
            role = model_role = model['role']
            frames, duration, motion_sha = clip['frames'], len(clip['root'])-1, clip['sourceSHA256']
    identifier = event['id'] if ordinary else f"d15_{event['sourceRecordIndex']}_{event['markerIndex']}_{event['route']}"
    files = [choice['file'] for choice in event['choices']]
    if clip is None:
        require(event['animationAlias'] in MODEL_ALIASES, 'An actor marker cannot silently become a pending model')
        return None,dict(id=identifier,animationAlias=event['animationAlias'],files=files,
            reason='awaiting-exact-source-model-binding',originalMarker=event)
    require(event['sourceTick'] == (event['sourceFrame']-event['sourceFirstIndex'])*event['sourceFrameStride']
            and 0 <= event['sourceTick'] <= duration
            and duration == (frames-1)*event['sourceFrameStride'], 'Source audio clock differs')
    result = dict(id=identifier,animationAlias=event['animationAlias'],role=role,modelRole=model_role,
        clip=name,sourceMotionSHA256=motion_sha,sourceRecordIndex=event['sourceRecordIndex'],route=event['route'],
        sourceFrame=event['sourceFrame'],sourceFirstIndex=event['sourceFirstIndex'],
        sourceFrameStride=event['sourceFrameStride'],sourceFrames=frames,sourceTick=event['sourceTick'],
        duration=duration,files=files,
        sourceEntry=event['sourceEntry'],sourceConfigurationSHA256=event['sourceSHA256'],
        originalChoices=event['choices'],originalFrame=event['rawFrame'])
    return result,None


def bind(args):
    source = json.loads(checked(args.audio_input, INPUT_SHA, 512_000))
    ordinary = None
    if args.ordinary_input:
        ordinary = json.loads(checked(args.ordinary_input, ORDINARY_INPUT_SHA, 512_000))
        require(ordinary['ownerProfileID']=='wuyong_erlang' and len(ordinary['files'])==52
                and len(ordinary['events'])==69, 'Ordinary source audio scope differs')
    trigger_source = None
    if args.meditation_trigger_source:
        require(ordinary is not None, 'Source trigger binding requires the complete original audio input')
        trigger_source = json.loads(checked(args.meditation_trigger_source, MEDITATION_TRIGGER_SHA, 8192))
    floor = None
    if args.floor_input:
        require(ordinary is not None and trigger_source is not None, 'Floor binding extends the complete source audio')
        floor = json.loads(checked(args.floor_input, FLOOR_INPUT_SHA, 512_000))
        require(floor['ownerProfileID'] == 'wuyong_erlang' and floor['floor'] == 'Stone'
                and floor['floorSourceSHA256'] == sha(encoded(floor['floorSource'])) == FLOOR_SOURCE_SHA
                and floor['floorSource']['applicationStage']['sha256'] == PALACE_SHA
                and len(floor['files']) == 7 and len(floor['events']) == 21
                and all(e['route'] == 'Floor.Stone' for e in floor['events']), 'Original Palace Floor audio scope differs')
    raw = checked(args.profile,args.profile_sha256,48_000_000)
    profile = json.loads(raw)
    require(profile['id']==profile['hero']=='wuyong_erlang' and len(source['files'])==28
            and len(source['events'])==29 and source['sourceConfigurationSHA256']==CONFIG_SHA,
            'Source audio/profile scope differs')
    character = args.profile.parent/(profile['resourceName']+'.glb')
    checked(character,profile['sha256'],48_000_000)
    require(character.stat().st_size==profile['bytes'],'Character size differs')
    models = dict(DEFAULT_MODELS)
    if args.model_bindings:
        require(args.model_bindings_sha256 is not None,'Additional model bindings require a digest')
        additional=json.loads(checked(args.model_bindings,args.model_bindings_sha256,512_000))
        for alias,binding in additional.items():
            require(alias not in models or models[alias]==binding,'Conflicting model binding')
            models[alias]=binding
    markers,pending=[],[]
    events = source['events'] + ([] if ordinary is None else ordinary['events']) + ([] if floor is None else floor['events'])
    for event in events:
        marker,missing=bind_marker(event,profile,models)
        if marker is not None:markers.append(marker)
        if missing is not None:pending.append(missing)
    fields = ('name','bytes','sha256','sampleRate','channels','sampleFrames','sampleWidth','pcmSHA256')
    originals = {f['name']: f for f in source['files']}
    parents = {f['name']: args.audio_input.parent for f in source['files']}
    if ordinary is not None:
        for f in ordinary['files']:
            if f['name'] in originals:
                require(all(originals[f['name']][k] == f[k] for k in fields), 'Shared original PCM identities conflict')
            else:
                originals[f['name']] = f; parents[f['name']] = args.ordinary_input.parent
    if floor is not None:
        for f in floor['files']:
            require(f['name'] not in originals, 'Floor inputs unexpectedly overlap the prior original inventory')
            originals[f['name']] = f; parents[f['name']] = args.floor_input.parent
    files=[{k:f[k] for k in fields} for f in originals.values()]
    require(len(files) == (82 if floor is not None else 28 if ordinary is None else 75), 'Combined original PCM inventory differs')
    unplayed = dict(DEFERRED)
    triggers = []
    if trigger_source is not None:
        meditation = [f for f in source['files'] if f['sourceName']=='d15_meditation']
        require(len(meditation)==1 and meditation[0]['sha256']==trigger_source['sourcePCM']['sha256']
                and trigger_source['start']['loop'] is False, 'Original one-shot meditation input differs')
        for role, alias in [('erlangMeditationStart','D15_Meditation_Start'),
                            ('erlangMeditationLoop','D15_Meditation_Loop'),
                            ('erlangMeditationEnd','D15_Meditation_End')]:
            clip = next(c for c in profile['clips'] if c['name']==profile['roles'][role])
            require(clip['sourceConfiguration']['configuration']['Animation']==alias
                    and clip['sourceConfiguration']['sourceSHA256']==CONFIG_SHA,
                    'Source meditation event belongs to another actor animation')
        triggers = [dict(id='d15_meditation',file=meditation[0]['name'],loop=False,
            sourceIdentifier=trigger_source['sourceIdentifier'],sourceLock=1432,
            sourceLockSHA256=trigger_source['sourceLock']['sha256'],startTrigger=13,stopTrigger=21,
            startEvent='meditationStarted',stopEvent='meditationStopped')]
        del unplayed['d15_meditation']
    deferred=[dict(sourceName=f['sourceName'],file=f['name'],reason=unplayed[f['sourceName']])
              for f in source['files'] if f['sourceName'] in unplayed]
    require({x['sourceName'] for x in deferred}==set(unplayed),'Unplayed source scope differs')
    references=({f for m in markers+pending for f in m['files']}|{x['file'] for x in deferred}|
                {x['file'] for x in triggers})
    require(references=={f['name'] for f in files} and len(markers)+len(pending)==len(events)
            and len({m['id'] for m in markers+pending})==len(events),'PCM closure differs')
    require(not args.output.exists(),'Refuse to replace a bound audio candidate')
    output=private_output(args.output)
    for f in files:
        data=checked(parents[f['name']]/f['name'],f['sha256'],4_000_000)
        require(len(data)==f['bytes'],'PCM size differs')
        write_new(output/f['name'],data)
    source_configurations = {'settings_sets_dynasty.bytes':CONFIG_SHA}
    if ordinary is not None:
        source_configurations.update(ordinary['sourceConfigurationHashes'])
    if floor is not None:
        require(not pending and len(markers) == 119, 'Complete Palace binding requires all actual actor/model clocks')
        require(all(source_configurations.get(k) == v for k,v in floor['sourceConfigurationHashes'].items()),
                'Floor configuration bytes conflict with existing source audio')
    context = dict(gender='Male', floor=None)
    if floor is not None:
        context.update(floor='Stone', stageName='SF3_Palace_Exterior.glb', stageSHA256=PALACE_SHA,
            floorSourceSHA256=FLOOR_SOURCE_SHA)
    document=dict(schemaVersion=4 if floor is not None else 3 if triggers else 1 if ordinary is None else 2,
        profileID=profile['id'],profileSHA256=sha(raw),
        characterSHA256=profile['sha256'],sourceConfigurationSHA256=CONFIG_SHA,
        sourceAudioManifestSHA256=INPUT_SHA,
        sourceOrdinaryAudioManifestSHA256=None if ordinary is None else ORDINARY_INPUT_SHA,
        sourceTriggerManifestSHA256=None if trigger_source is None else MEDITATION_TRIGGER_SHA,
        sourceFloorAudioManifestSHA256=None if floor is None else FLOOR_INPUT_SHA,
        sourceConfigurationHashes=source_configurations,files=files,markers=markers,pendingModels=pending,
        deferredTriggers=deferred,triggerSounds=triggers,context=context,
        scope=('All 98 existing Common/Male plus 21 original Floor.Stone markers, only in the authenticated Palace.' if floor is not None else
               'All 29 D15 Common/Male configuration markers.' if ordinary is None else
               'All 29 D15 plus 69 admitted Imperial/move/hit/kick/paired-throw Common/Male source markers; Floor is not selected.'),
        runtimePlaybackObserved=False)
    write_new(output/'SF3_Erlang_Audio.json',encoded(document))
    receipt=dict(profile=record(args.profile),character=record(character),audio=record(output/'SF3_Erlang_Audio.json'),
        files=len(files),actorMarkers=sum(m['modelRole'] is None for m in markers),
        modelMarkers=sum(m['modelRole'] is not None for m in markers),pendingModelMarkers=len(pending),
        ordinarySourceMarkers=0 if ordinary is None else len(ordinary['events']),
        floorSourceMarkers=0 if floor is None else len(floor['events']),
        deferredTriggerFiles=len(deferred),sourceTriggerSounds=len(triggers),decodedAgain=False,normalApplicationPlaybackObserved=False)
    write_new(output/'erlang-audio-binding-private.json',encoded(receipt))
    return receipt


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('audio-input','profile','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--profile-sha256',required=True)
    parser.add_argument('--model-bindings',type=Path)
    parser.add_argument('--model-bindings-sha256')
    parser.add_argument('--ordinary-input',type=Path)
    parser.add_argument('--meditation-trigger-source',type=Path)
    parser.add_argument('--floor-input',type=Path)
    print(json.dumps(bind(parser.parse_args())))


if __name__=='__main__':main()
