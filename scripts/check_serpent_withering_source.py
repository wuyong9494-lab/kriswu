#!/usr/bin/env python3
"""Read D13 Withering constants/expressions from the exact original lock bytes.

This bounded source oracle never imports or runs the Swift implementation.
It validates event types, source owners, range operators and damage channels,
then exports numeric cases for checking the ordinary production adapter.
"""
import argparse
import hashlib
import json
from pathlib import Path

from check_serpent_state_source import require
from source_floorfall_audio import Storage, compact

SOURCE_SHA256 = '941b17f2617d37d6bb0a252332d547c1aa740e61aa45f91b0705a646fbf4f354'


def build(source):
    raw = source.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == SOURCE_SHA256, 'Unverified original Withering source')
    storage = Storage(raw)
    require(storage.pos == len(raw), 'Unconsumed original trigger bytes')
    sets = storage.value(storage.root)
    require(len(sets) == 1 and sets[0]['fields'][0] == 'SET_DYNASTY_13_LEVEL_4', 'Unexpected source set')
    rows = [dict(priority=compact(t['fields'][2]), events=compact(t['fields'][3]),
                 conditions=compact(t['fields'][4]), actions=compact(t['fields'][5]))
            for t in sets[0]['fields'][1]]
    require(len(rows) == 11, 'Unexpected source trigger count')
    aura = rows[3]
    require(aura['events'] == [{'a45': [None]}, {'a44': ['enum65537', 'SET_DYNASTY_13_BLOOM_CHECK']}],
            'Aura activation events changed')
    threshold = aura['conditions'][0]['expr']
    require(threshold[0] == {'f82': [{'f51': ['Me', 'SET_DYNASTY_13_SLIDER_VALUE']}]} and threshold[-1] == 'op20',
            'Aura source threshold changed')
    require(aura['actions'][0] == {'a171': ['SET_D13_WITHERING_AURA_ACTIVE', 'enum65537', 1.0, None, None]},
            'Aura variable lifetime changed')
    require(aura['conditions'][1] == {'Not': [
        {'expr': [{'f82': [{'f51': ['Me', 'SET_D13_WITHERING_AURA_ACTIVE']}]}, 1.0, 'op22']},
        {'expr': [{'f82': [{'f51': ['Me', 'SET_D13_ROT_FORM']}]}, 1.0, 'op22']}]},
        'Ordinary aura activation guards changed')
    gain, decay = rows[5], rows[6]
    require(gain['events'] == [{'a11': [None, 60.0]}] and decay['events'] == [{'a11': [None, 20.0]}],
            'Independent source periodic events changed')
    for row in (gain, decay):
        require(row['conditions'][0] == {'expr': [{'f37': [None]}, 'RoundFightStart', 'op22']},
                'Periodic phase changed')
        require(row['conditions'][1] == {'expr': [{'f82': [{'f51': ['Me', 'SET_D13_WITHERING_AURA_ACTIVE']}]}, 1.0, 'op22']},
                'Aura activation guard changed')
    distance = gain['conditions'][2]['expr']
    require(distance[:4] == [
        {'f17': [{'f24': [{'f74': ['enum65537']}, 'COM', None]}]},
        {'f17': [{'f24': [{'f74': ['enum65538']}, 'COM', None]}]}, 'op1', 'op13'],
        'Both original COM-X samples are required')
    require(distance[-1] == 'op19' and decay['conditions'][2]['expr'] == distance[:-1] + ['op20'],
            'Source near/far boundaries changed')
    target = {'f82': [{'f51': ['Enemy', 'SET_D13_WITHERING_DEBUFF']}]}
    positive_layers = {'expr': [target, 0.0, 'op18']}
    require(len(gain['conditions']) == 3 and len(decay['conditions']) == 4
            and decay['conditions'][3] == positive_layers, 'Source decay lower bound changed')
    increment = gain['actions'][0]['a171']
    decrement = decay['actions'][0]['a171']
    require(increment == ['SET_D13_WITHERING_DEBUFF', 'enum65538', [target, 1.0, 'op0', 40.0, 'op10'], None, None]
            and decrement == ['SET_D13_WITHERING_DEBUFF', 'enum65538', [target, 1.0, 'op1'], None, None],
            'Source stack ownership/arithmetic changed')
    factors = [a['a142'] for a in rows[9]['actions']]
    channels = ['Factor_WeaponDamage', 'Factor_UnarmedDamage', 'Factor_RangedDamage', 'Factor_MagicPower']
    require([a[0] for a in factors] == channels and all(a[1] == 'enum65537' for a in factors),
            'Source damage channels/owner changed')
    expression = [1.0, target, 0.02, 'op2', 'op1']
    require(all(a[2] == expression and a[3:] == [1.0, None] for a in factors),
            'Source power multiplier changed')
    prehit = {'expr': [{'f80': [None]}, 'PreHit', 'op22']}
    first_hit = {'Or': [{'And': [prehit, {'Or': [
        {'expr': [{'f82': [{'f51': ['Enemy', 'HIT_FIRST']}]}, 1.0, 'op22']},
        {'expr': [{'f62': [None]}, 'Hit_Invisible_Hit', 'op22']}]}]}, {'Not': [prehit]}]}
    require(rows[4]['events'] == rows[9]['events'] == [{'a27': ['enum65537', None, None, None, None]}]
            and rows[9]['conditions'] == [first_hit, positive_layers]
            and rows[4]['conditions'] == [first_hit,
                {'expr': [{'f82': [{'f51': ['Me', 'CRITICAL']}]}, 1.0, 'op22']}, positive_layers],
            'Source accepted PreHit/critical guards changed')
    require(rows[4]['priority'] == 8992
            and rows[4]['actions'] == [{'a171': ['FORCE_NO_CRITICAL', 'enum65537', 1.0, 1, None]}],
            'Source critical gate changed')
    return dict(schema='d13-withering-source-oracle-v1', sourceSHA256=SOURCE_SHA256,
        auraThreshold=threshold[1], gainPeriod=gain['events'][0]['a11'][1],
        decayPeriod=decay['events'][0]['a11'][1], distanceSourceUnits=distance[-2],
        maximumStacks=increment[2][3], sourceDamageChannels=channels,
        factorCases=[dict(stacks=n, multiplier=expression[0] - n * expression[2]) for n in range(41)],
        rangeCases=[dict(distance=d, gains=d < distance[-2], decays=d >= distance[-2])
                    for d in (0, 299.999, 300, 300.001, 1000)],
        genericTriggerInterpreter=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = build(args.source)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write('\n')
    print(json.dumps({'sourceSHA256': result['sourceSHA256'], 'factorCases': len(result['factorCases']),
                      'rangeCases': len(result['rangeCases'])}))
