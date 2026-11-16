#!/usr/bin/env python3
"""Bind the verified Shuangou combo gates and physical contact windows.

This private candidate retains D13 identity and all 66 actual animations. Poison,
Bloom, bottle physics and generic shadow/ranged commands remain unactivated.
It cannot be substituted for a complete production serpent implementation.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from build_erlang_source_assets import checked, encoded, record, write_new
from erlang_source_profile import combat_rules
from prepare_serpent_animated_body import NAMED_SHA
from sun_triad_assets import private_output, require

BODY_SHA = '2242e07e8768c929b89191cf2d7c95ab51aa3560ef34e998415ece8a3b8561da'
MODEL_SHA = 'f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70'
LOCKS = {
    4993: ('c73f0b22b9dcd09984e41126a97ca1b4121c5654401ed0673231bd25bfaa1d94',
           '67eeff5a22e2c25827ca1c30a2c52a615489b5448fa309007a275c28b081585f', 5),
    4996: ('bfd5110a6c1e27333ae7a38469e6d1d5a1fdb2c6ae32353a8db5c5d552be2880',
           'cd44482f741ed0f702f6f21224d36682563830c29c9344e5b1b727bc20ede089', 3),
}
PROFILE = 'SF3_Serpent_Physical_Combat_Profile.json'
EVIDENCE = [
    'Original D13 Shuangou/agile-kick contact intervals, four original hook capsules and real body capsules; native source stride/crop.',
    'Eight combo links from locks 4993/4996: original IntervalEnd:Transitional and destination FrameShift0, with original animation aliases.',
    'Application normalization: WeaponDamage=1000; UnarmedDamage=1000; blocked damage=25 percent.',
    'Application hit-stop4/2 ticks and recoil160mm/8ticks or60mm/6ticks; no claim these are original impulse magnitudes.',
    'Only physical commands are staged. D13 poison/Bloom/bottle rules and the complete source input-condition evaluator are not activated.',
]


def combo_bindings(profile, locks):
    by_alias = {}
    for clip in profile['clips']:
        alias = clip['sourceConfiguration']['configuration']['Animation']
        require(alias not in by_alias, 'Ambiguous original animation alias')
        by_alias[alias] = clip
    links, receipts = [], []
    for lock, document in locks.items():
        require(document['sourceSHA256'] == LOCKS[lock][1]
                and document['allSixTriggerFieldsPreserved'], 'Original combo lock identity differs')
        count = 0
        for source_set in document['sets']:
            for trigger in source_set['triggers']:
                if trigger['events'] != [{'a17': ['enum65537', 'Transitional']}]:
                    continue
                actions = trigger['actions']
                require(len(actions) == 1 and set(actions[0]) == {'a6'}, 'Unexpected combo action')
                alias, shift, flags = actions[0]['a6']
                require(shift is None and flags is None and alias in by_alias, 'Unbound combo destination')
                destination = by_alias[alias]
                transitions = destination['sourceConfiguration']['configuration']['Transitions']
                require(len(transitions) == 1 and transitions[0][:2] == [0, None]
                        and len(transitions[0][2]) == 1, 'Unbound destination frame shift')
                previous = transitions[0][2][0]
                require(previous in by_alias, 'Unbound combo predecessor')
                source = by_alias[previous]
                config = source['sourceConfiguration']['configuration']
                gates = [i for i in config['Intervals'] if i['Name'] == 'Transitional']
                require(len(gates) == 1 and type(gates[0]['End']) is int, 'Ambiguous combo interval')
                frame = gates[0]['End']
                require(all(c['sourceFirstIndex'] == 0 and c['playbackTicks'] == 2*(c['frames']-1)
                            for c in (source, destination))
                        and 0 <= frame < min(source['frames'], destination['frames'])-1,
                        'Unbound combo anchor clock')
                link = dict(from_=source['name'], to=destination['name'], sourceFrame=frame)
                link['from'] = link.pop('from_')
                require(link['from'] not in {l['from'] for l in links}, 'Ambiguous combo branch')
                links.append(link)
                receipts.append(dict(link=link, sourceLock=lock, sourceSHA256=document['sourceSHA256'],
                    sourceSet=source_set['sourceSetName'], sourceSetIndex=source_set['sourceSetIndex'],
                    triggerIndex=trigger['triggerIndex'], sourceAnimation=previous, destinationAnimation=alias,
                    event=trigger['events'], action=actions, originalConditions=trigger['conditions'],
                    interval=copy.deepcopy(gates[0]), destinationTransition=transitions[0]))
                count += 1
        require(count == LOCKS[lock][2], 'Original combo link inventory differs')
    require(len(links) == 8, 'Incomplete Shuangou physical chains')
    return links, receipts


def bind(body, named, locks):
    require(body['id'] == 'liu_serpent' and body['weaponID'] == 'wpn__shuangou_01_04'
            and body['sha256'] == MODEL_SHA and len(body['clips']) == 66
            and body['comboLinks'] == [] and 'combatRules' not in body, 'Expected recovered D13 body')
    profile = copy.deepcopy(body)
    links, combos = combo_bindings(profile, locks)
    profile['comboLinks'] = links
    # Keep the original skill clips under their specific D13 names. Never let
    # legacy generic skill handling impersonate poison or bottle behaviour.
    withheld = {role: profile['roles'].pop(role) for role in ('shadow', 'ranged')}
    rules, contacts = combat_rules(profile, named,
        identity='serpent-d13-source-shuangou-geometry-v1', evidence=EVIDENCE)
    profile['combatRules'] = rules
    profile['schema'] = 'serpent-physical-combat-candidate-v1'
    profile['recoveryBoundary'].update(physicalRulesBound=True, comboLinksBound=True,
        sourceInputConditionsFullyEvaluated=False, fullMatchProfile=False, runtimeBound=False)
    evidence = dict(schema='serpent-physical-combat-binding-v1', comboLinks=combos,
        contacts=contacts, withheldGenericSkillRoles=withheld, adaptations=EVIDENCE[2:4],
        boundaries=profile['recoveryBoundary'])
    return profile, evidence


def build(args):
    require(not args.output.exists(), 'Use a fresh private physical output')
    body = json.loads(checked(args.profile, BODY_SHA, 24_000_000))
    named = json.loads(checked(args.named, NAMED_SHA, 2_000_000))
    locks = {lock: json.loads(checked(args.triggers/f'serpent-lock-{lock}-source-v1.json',
                                    pins[0], 2_000_000)) for lock, pins in LOCKS.items()}
    profile, evidence = bind(body, named, locks)
    model = args.profile.parent/(profile['resourceName']+'.glb')
    raw_model = checked(model, MODEL_SHA, 20_000_000)
    require(len(raw_model) == profile['bytes'], 'D13 model byte count differs')
    output = private_output(args.output)
    write_new(output/model.name, raw_model)
    write_new(output/PROFILE, encoded(profile))
    write_new(output/'physical-combat-binding-private.json', encoded(evidence))
    receipt = dict(schema='serpent-physical-combat-receipt-v1', inputs=[record(args.profile), record(args.named)],
        profile=record(output/PROFILE), character=record(output/model.name),
        binding=record(output/'physical-combat-binding-private.json'),
        unchangedBodyClips=66, unchangedGeometryAndPersonalPortrait=True,
        physicalAttacks=len(profile['combatRules']['attacks']),
        sourceStrikeWindows=sum(len(a['strikes']) for a in profile['combatRules']['attacks']),
        comboLinks=len(profile['comboLinks']), boundaries=profile['recoveryBoundary'])
    write_new(output/'physical-combat-receipt-private.json', encoded(receipt))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'named', 'triggers', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(build(parser.parse_args()), allow_nan=False))


if __name__ == '__main__':
    main()
