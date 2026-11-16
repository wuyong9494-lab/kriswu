#!/usr/bin/env python3
"""Authenticate D13 action markers and generate explosion transition oracles.

Evaluates only the selected source expressions/conditions; no game code, remote
JavaScript, generic input interpreter, model collision or native parity claim.
"""
import argparse
import hashlib
import json
from pathlib import Path

from check_serpent_state_source import RECEIPT_SHA, documents, evaluate, require, trigger
from prepare_serpent_named_settings import encoded

PROFILE_SHA = '05f5e49993120467a1c2cd5fdcbce3dba0dd3e8a5223b455f50adcfcd5441818'
NAMED_SHA = '612b85ed595e4a29ab686c00370d0c4bd573d6aaaa62384c769a4abb1f2cf09a'
LEVELS_SHA = 'b240f29568b7fed0886191a4c1500a983278839121489d954e838d6f220431d5'
CHANNELS = ('weapon', 'unarmed', 'ranged', 'shadow')
POISON = {c: f'SET_D13_{c.upper()}_POISON_DAMAGE' for c in CHANNELS}
BUFF = {c: f'SET_DYNASTY_13_POISON_BUFF_{c.upper()}' for c in CHANNELS}
LAST = 'SET_D13_LAST_POISON_TYPE'
USED = 'SET_DYNASTY_13_ABILITY_USED'


def checked_json(path, digest):
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == digest, f'Changed input: {path.name}')
    return json.loads(raw)


def condition(rows, variables, invincible):
    def atom(value):
        if isinstance(value, dict) and 'f37' in value: return 'RoundFightStart'
        if isinstance(value, dict) and 'f29' in value:
            require(value == {'f29': [{'f74': ['enum65538']}]}, 'Unsupported interval owner')
            return 'Invincible' if invincible else ''
        if isinstance(value, str): return value
        return evaluate(value, variables, 0, 1)
    def row(value):
        require(len(value) == 1, 'Ambiguous condition')
        kind, data = next(iter(value.items()))
        if kind == 'And': return all(row(r) for r in data)
        if kind == 'Or': return any(row(r) for r in data)
        if kind == 'Not': return not any(row(r) for r in data)
        require(kind == 'expr' and len(data) == 3 and data[2] in ('op18', 'op22'), 'Unsupported condition')
        a, b = atom(data[0]), atom(data[1])
        return a > b if data[2] == 'op18' else a == b
    return all(row(r) for r in rows or [])


def markers(profile, named, docs):
    rows = []
    for action, role, index, name, lock, source_set, source_trigger in (
        ('poison', 'serpentPoison', 55, 'D13_Poison_Apply', 1379, 0, 7),
        ('bottle', 'serpentBottle', 67, 'D13_Bottle_Throw_Model', 1400, 1, 3)):
        clip = next(c for c in profile['clips'] if c['name'] == profile['roles'][role])
        source = clip['sourceConfiguration']
        require(source['sourceRecordIndex'] == index and source in named['records'], 'Unbound body settings')
        config = source['configuration']
        require(config['MidFrames'] is None and config['FirstFrame'] is None and config['EndFrame'] is None
                and config['SelfEndFrame'] is None and config['Looped'] is None and config['Mirrored'] is None
                and clip['sourceFirstIndex'] == 0 and clip['playbackTicks'] == 2*(clip['frames']-1),
                'Unreviewed action clock')
        intervals = [i for i in config['Intervals'] if i['Name'] == name]
        require(len(intervals) == 1 and intervals[0]['Start'] == intervals[0]['End'], 'Ambiguous action marker')
        t = trigger(docs, lock, source_trigger, source_set)
        require(t['events'] == [{'a18': ['enum65537', name]}], 'Not the actual IntervalStart event')
        release = 2*(intervals[0]['Start']-1)
        end = 2*(clip['frames']-1-4)
        require(end == clip['sourceEndEventTick'] and 0 <= release < end, 'Invalid action release/end')
        sounds = [dict(tick=2*s['Frame'], name=n) for s in config['Sounds'] for n in s['Common'] or []]
        rows.append(dict(action=action, role=role, alias=config['Animation'], clipName=clip['name'],
            clipSHA256=clip['sha256'], frames=clip['frames'], playbackTicks=clip['playbackTicks'],
            endEventTick=end, releaseTick=release, releaseMarker=name, sounds=sounds))
    bottle_start = trigger(docs, 1400, 2, 1)
    require(bottle_start['events'] == [{'a1': ['D13_Bottle_Throw', 'enum65537']}]
            and bottle_start['actions'] == [{'a224': [-1.0, 'enum65537']}, {'a201': [None]},
                {'a171': ['SET_D13_POISON_BOMB_USED', 'enum65537', 1.0, None, None]}],
            'Bottle usage is no longer the reviewed StageChange action')
    model = trigger(docs, 1400, 3, 1)['actions'][0]['a45']
    require(model[:3] == [None, 'enum4', 'Ranged'] and model[15][0] == 'D13_POSION_BOMB_MODEL',
            'Not the equipped ranged model creation')
    return rows


def explosion_cases(docs):
    cases = []
    for level in range(2, 7):
        for invincible in (False, True):
            patterns = [(f'dominant_{c}', [(o, .4 if o == c else .05) for o in CHANNELS]) for c in CHANNELS]
            patterns += [(f'cap_tie_last_{c}', [(o, 1) for o in CHANNELS if o != c]+[(c, 1)]) for c in CHANNELS]
            patterns += [('equal_below_cap', [('weapon', .1), ('unarmed', .1)]), ('empty', [])]
            for name, contacts in patterns:
                variables, timers, inputs = {}, {}, []
                init = [trigger(docs, 1389, 1)]
                if level >= 3: init.append(trigger(docs, 1395, 0))
                if level >= 5: init.append(trigger(docs, 1397, 0))
                for t in init:
                    for a in t['actions']:
                        key, owner, value, _, _ = a['a171']
                        require(owner == 'enum65537', 'Wrong initializer owner')
                        variables[key] = evaluate(value, variables, 0, 1)
                for i, (channel, damage) in enumerate(contacts):
                    t = trigger(docs, 1389, {'weapon':17,'unarmed':18,'ranged':20,'shadow':22}[channel])
                    for a in t['actions']:
                        if 'a171' not in a: continue
                        key, _, expression, duration, _ = a['a171']
                        if key not in (*POISON.values(), LAST): continue
                        variables[key] = evaluate(expression, variables, damage, 1)
                        timers[key] = int(duration or 0)
                    delay = 13 if name.startswith('dominant') else 0
                    for key in timers: timers[key] = max(0, timers[key]-delay)
                    inputs.append(dict(channel=channel, damage=damage, delay=delay))
                damage = [0.0]*4
                damage_trigger = trigger(docs, 1379, 16)
                if condition(damage_trigger['conditions'], variables, invincible):
                    for a in damage_trigger['actions']:
                        value = a['a10']
                        channel = next(c for c in CHANNELS if value[0] == f'SET_D13_POISON_{c.upper()}_EXPLOSION')
                        damage[CHANNELS.index(channel)] = -evaluate(value[3], variables, 0, 1)
                selected = None
                for c, index in zip(CHANNELS, (10,12,13,15)):
                    t = trigger(docs, 1379, index)
                    require(t['priority'] is None, 'Changed buff priority')
                    if condition(t['conditions'], variables, invincible):
                        require(selected is None, 'Multiple original buff winners')
                        selected = c
                        action = next(a['a171'] for a in t['actions'] if 'a171' in a and a['a171'][0] == BUFF[c])
                        require(action[2:4] == [1.0,900.0], 'Changed buff lifetime')
                cleanup = docs[1381 if level < 4 else 1398 if level < 6 else 1399]['sets'][0]['triggers']
                for t in cleanup:
                    require(t['priority'] == -5, 'Changed cleanup priority')
                    if not condition(t['conditions'], variables, invincible): continue
                    for a in t['actions']:
                        if 'a171' not in a: continue
                        key, owner, expression, duration, _ = a['a171']
                        if key not in (*POISON.values(), LAST, USED): continue
                        require(owner == 'enum65537', 'Wrong cleanup variable owner')
                        value = evaluate(expression, variables, 0, 1)
                        if isinstance(duration, dict) and 'f230' in duration:
                            require(duration['f230'] == ['enum65537',key], 'Wrong source lifetime')
                            time = timers.get(key, 0)
                        else: time = int(evaluate(duration, variables, 0, 1))
                        variables[key] = value; timers[key] = time
                last = variables.get(LAST, 0)
                cases.append(dict(level=level, name=name, invincible=invincible, contacts=inputs,
                    damage=damage, selected=selected, cooldown=timers.get(USED,0),
                    amounts=[variables.get(POISON[c],0) for c in CHANNELS],
                    timers=[timers.get(POISON[c],0) for c in CHANNELS],
                    last=CHANNELS[int(last)-2] if last else None))
    return cases


def build(args):
    docs = documents(args.source, (1379,1381,1389,1395,1397,1398,1399,1400))
    levels = checked_json(args.source/'serpent-original-levels-v1.json', LEVELS_SHA)
    for level, tag in ((2,'D13_DEFAULT_ABILITY'),(4,'D13_ABILITIES_UPGRADE'),(6,'D13_POISON_BOMB')):
        require(tag in levels['levels'][str(level)]['specialAbility']['attributes'], 'Level/tag binding changed')
    profile, named = checked_json(args.profile, PROFILE_SHA), checked_json(args.named, NAMED_SHA)
    return dict(schema='d13-action-source-oracle-v1', receiptSHA256=RECEIPT_SHA,
        profileSHA256=PROFILE_SHA, sourceLocks=sorted(docs), motions=markers(profile,named,docs),
        explosionCases=explosion_cases(docs), fullTriggerInterpreter=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source','profile','named','output'): parser.add_argument('--'+name,type=Path,required=True)
    args = parser.parse_args()
    result = build(args)
    with args.output.open('xb') as file: file.write(encoded(result))
    args.output.chmod(0o600)
    print(json.dumps(dict(motions=len(result['motions']), explosionCases=len(result['explosionCases']),
                         sourceLocks=result['sourceLocks'])))
