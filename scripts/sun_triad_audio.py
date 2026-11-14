#!/usr/bin/env python3
"""Bind verified H17 and Ninjato source audio to original animation markers.

All inputs are existing private source files. No network access, guessed sound
families, resampling, gain changes, or filename-based event inference is used.
Additional accepted-event cues may be supplied after their runtime event
semantics have been checked against the original trigger records.
"""
from __future__ import annotations
import argparse, hashlib, io, json, re, warnings, wave
from pathlib import Path
from sun_triad_assets import require, private_output, write_private

PREFIX='assets/gamedata/resources/audio/sounds/'


def sha(data):return hashlib.sha256(data).hexdigest()


def source_path(value):
    name=value.split('@')[0]
    require(name and '..' not in name and not name.startswith('/'),'Invalid source audio resource path')
    return PREFIX+name.lower()+'.wav'


def extract(models,bundle_inventory,output):
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1'
    result={};by_digest={}
    for row in bundle_inventory['bundles']:
        bundle=Path(row['file']).name;raw=(models/bundle).read_bytes()
        require(len(raw)==row['bytes'] and sha(raw)==row['sha256'],'Original audio bundle identity differs')
        environment=UnityPy.load(raw);container={p.lower():r for p,r in environment.container.items()}
        for source in row['paths']:
            path=source['path'].lower();require(path in container,'Original audio container entry is missing')
            pointer=container[path];obj=pointer.deref()
            require(obj.type.name=='AudioClip','Source sound does not reference an AudioClip')
            clip=pointer.read();samples=clip.samples
            require(len(samples)==1,'Original audio decoder returned ambiguous samples')
            original_name,data=next(iter(samples.items()))
            require(original_name.endswith('.wav'),'Original audio decoder did not return WAV')
            with wave.open(io.BytesIO(data),'rb') as decoded:
                channels,frequency,frames,width=(decoded.getnchannels(),decoded.getframerate(),decoded.getnframes(),decoded.getsampwidth())
                require(decoded.getcomptype()=='NONE' and width==2,'Source audio is not PCM16')
            require(channels==clip.m_Channels and frequency==clip.m_Frequency,'Original audio format changed during decoding')
            require(abs(frames/frequency-clip.m_Length)<2/frequency,'Original audio duration changed during decoding')
            digest=sha(data)
            if digest in by_digest:filename=by_digest[digest]
            else:
                stem=re.sub(r'[^A-Za-z0-9_]+','_',Path(original_name).stem)
                filename='SF3H17_'+stem+'_'+digest[:10]+'.wav'
                require(1<=len(data)<=4_000_000 and len(filename)<=160,'Original audio exceeds target bounds')
                write_private(output/filename,data);by_digest[digest]=filename
            resource=clip.m_Resource
            encoded=get_resource_data(resource.m_Source,clip.object_reader.assets_file,resource.m_Offset,resource.m_Size)
            record=dict(name=filename,bytes=len(data),sha256=digest,sourceName=clip.m_Name,
                sourcePath=path,sourcePathID=str(obj.path_id),sourceBundle=bundle,sourceBundleSHA256=row['sha256'],
                sourceObjectSHA256=sha(obj.get_raw_data()),encodedSHA256=sha(encoded),encodedBytes=len(encoded),
                sampleRate=frequency,channels=channels,sampleFrames=frames,sampleWidth=width)
            if path in result:require(result[path]['sha256']==digest,'Conflicting original audio resource identity')
            result[path]=record
    require(set(bundle_inventory['wanted'])==set(result),'Original audio path inventory is incomplete')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('models','bundles','settings','profile','spirits','trigger-audio','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--cue-bindings',type=Path)
    args=parser.parse_args();warnings.filterwarnings('ignore',category=Warning,module='UnityPy')
    output=private_output(args.output)
    bundle_inventory=json.loads(args.bundles.read_text());sounds=extract(args.models,bundle_inventory,output)
    settings=json.loads(args.settings.read_text());profile=json.loads(args.profile.read_text())
    summons=json.loads((args.spirits/'SF3_H17_Summons.json').read_text())
    require(profile['id']=='sun_triad' and profile['sha256']==summons['characterSHA256'],'Source audio character pin mismatch')
    records={r['configuration']['Animation']:r for r in settings['records']}
    main_clips={c['name']:c['frames'] for c in profile['clips']}
    markers=[];proof=[];unbound=[];seen={};role_sources={};role_clips={}

    def group(values):
        paths=[source_path(value) for value in values]
        require(all(path in sounds for path in paths),'Original marker references unrestored audio')
        return list(dict.fromkeys(sounds[path]['name'] for path in paths))

    def marker(alias,clip,frames,frame,values,*,role=None,basis=None):
        source=records[alias];frame=max(0,frame or 0)
        require(0<=frame<frames,'Original sound marker exceeds original motion frame count')
        files=group(values);key=(role,clip,frame,tuple(files))
        if key in seen:
            proof[seen[key]]['sourceBindings'].append(basis or dict(sourceAnimation=alias,sourceFrame=frame))
            return
        item=dict(id='source_'+str(len(markers)).zfill(4)+'_'+re.sub(r'[^A-Za-z0-9_-]','_',alias)[:70],
                  clip=clip,sourceFrame=frame,files=files)
        if role:item['summonRole']=role
        seen[key]=len(proof);markers.append(item)
        proof.append(dict(id=item['id'],sourceConfiguration=source['sourceEntry'],sourceSHA256=source['sourceSHA256'],
            sourceRecordIndex=source['sourceRecordIndex'],sourceBindings=[basis or dict(sourceAnimation=alias,sourceFrame=frame)]))

    def animation(alias,clip,frames,role=None):
        source=records[alias];configuration=source['configuration']
        require(Path(configuration['FileName']).stem==clip,'Original source alias and clip differ')
        require(configuration['FirstFrame'] is None,'Cropped source animation needs a separately checked marker origin')
        for index,sound in enumerate(configuration['Sounds'] or []):
            if sound['Common']:
                marker(alias,clip,frames,sound['Frame'],sound['Common'],role=role,
                    basis=dict(sourceAnimation=alias,soundIndex=index,field='Sounds.Common',
                               sourceFrame=sound['Frame'],frameRule='Sounds.Frame is clamped at zero and is not decremented.'))
            for kind in ('Gender','Floor'):
                if sound[kind] is not None:
                    unbound.append(dict(sourceAnimation=alias,clip=clip,summonRole=role,sourceFrame=sound['Frame'],
                        field=kind,sourceValue=sound[kind],reason='Requires the active original gender/floor audio context.'))

    for alias,row in records.items():
        configuration=row['configuration'];clip=Path(configuration['FileName']).stem
        if row['sourceEntry']=='settings_sets_dynasty.bytes' or 'Spirit' in alias:continue
        if clip in main_clips:animation(alias,clip,main_clips[clip])
        elif configuration['Sounds']:
            unbound.append(dict(sourceAnimation=alias,clip=clip,field='Sounds',sourceValue=configuration['Sounds'],
                reason='Independent source model timeline; it is not a host animation.'))

    for definition in summons['models']:
        choices=[json.loads(p.read_text()) for p in args.spirits.glob('h17-*-provenance.json')]
        choices=[p for p in choices if p['sourceModel']==definition['sourceModel']]
        require(len(choices)==1,'Original companion audio role provenance is ambiguous')
        aliases=choices[0]['sourceRoles']
        for motion in definition['motions']:
            for role in motion['roles']:
                alias=aliases[role];role_sources[alias]=role;role_clips[role]=(motion['clip'],motion['frames'])
                animation(alias,motion['clip'],motion['frames'],role)

    # These four source trigger entries explicitly target an original state or
    # interval. They can therefore use the same actor timeline as Sounds.Frame.
    # Other model/round/condition events remain independently reviewed cues.
    trigger_records=json.loads(args.trigger_audio.read_text())
    bound_trigger_indices=[]
    for index,record in enumerate(trigger_records):
        identity=(record['lock'],record['triggerIndex'])
        if identity not in ((1819,5),(1819,6),(1820,1),(1826,2)):continue
        require(record['conditions'] is None and len(record['audioActions'])==1,'Original actor sound trigger conditions differ')
        action=record['audioActions'][0]['a111'];require(action[1] is None and action[2] is None,'Unexpected actor sound playback flags')
        if identity==(1826,2):
            alias='H17_Spirit_Rift_1';interval_name=record['events'][0]['a18'][1]
            intervals=[i for i in records[alias]['configuration']['Intervals'] if i['Name']==interval_name]
            require(len(intervals)==1 and intervals[0]['Start'] is not None,'Original sound interval marker is ambiguous')
            frame=max(0,intervals[0]['Start']-1)
            basis=dict(sourceAnimation=alias,sourceInterval=interval_name,sourceStart=intervals[0]['Start'],
                       frameRule='Interval.Start is decremented by the original interval constructor.')
        else:
            alias=record['events'][0]['a1'][0];frame=0
            basis=dict(sourceAnimation=alias,sourceEvent='AnimationStart',frameRule='Actor animation start is sample zero.')
        require(alias in role_sources,'Original actor trigger role is missing')
        role=role_sources[alias];clip,frames=role_clips[role]
        marker(alias,clip,frames,frame,action[0],role=role,basis=dict(**basis,sourceLock=record['lock'],sourceTrigger=record['triggerIndex']))
        bound_trigger_indices.append(index)

    cues=[];audio={}
    if args.cue_bindings:
        binding=json.loads(args.cue_bindings.read_text())
        require(binding['sourceTriggerSHA256']==sha(args.trigger_audio.read_bytes()),'Accepted-event cue trigger proof differs')
        cues=binding['cues'];audio=binding.get('audio',{})
    all_files={item['name']:{k:item[k] for k in ('name','bytes','sha256')} for item in sounds.values()}
    references={name for entry in markers+cues for name in entry['files']}|{name for group in audio.values() for name in group}
    require(references<=set(all_files),'Accepted-event cue references an unverified original WAV')
    files=[all_files[name] for name in sorted(references)]
    require(len(files)<=96 and sum(item['bytes'] for item in files)<=32_000_000,'Original audio candidate exceeds loader bounds')
    document=dict(version=1,profileID='sun_triad',characterSHA256=profile['sha256'],
        sourceConfigurationSHA256=sha(args.settings.read_bytes()),
        evidence=['Source bundle/container/AudioClip identities and PCM format are verified before binding.',
                  'Original Sounds.Frame values are not shifted by the attack interval minus-one rule.',
                  'Independent summoned actors use the exact source model role and its own motion timeline.',
                  'Explicit AnimationStart and named IntervalStart audio actions retain their original event frame.',
                  'No guessed weapon-family contact audio, resampling, gain changes, or generic cast timing is introduced.'],
        files=files,audio=audio,cues=cues,markers=markers)
    raw=json.dumps(document,separators=(',',':'),allow_nan=False).encode();write_private(output/'SF3_H17_Audio.json',raw)
    write_private(output/'h17-audio-binding-provenance-private.json',json.dumps(dict(
        sourceConfigurationSHA256=sha(args.settings.read_bytes()),sourceTriggerSHA256=sha(args.trigger_audio.read_bytes()),
        decodedSourceFiles=list(sounds.values()),markers=proof,boundSourceTriggerIndices=bound_trigger_indices,
        remainingSourceTriggers=[r for i,r in enumerate(trigger_records) if i not in bound_trigger_indices],
        contextDependentSounds=unbound),indent=2,allow_nan=False).encode())
    print(json.dumps(dict(file='SF3_H17_Audio.json',bytes=len(raw),sha256=sha(raw),files=len(files),
        audioBytes=sum(item['bytes'] for item in files),markers=len(markers),cues=len(cues),
        restoredSourcePaths=len(sounds),sourceActorTriggersBound=len(bound_trigger_indices))))


if __name__=='__main__':main()
