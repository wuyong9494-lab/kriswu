#!/usr/bin/env python3
"""Read the exact D13 poison-buff and Bloom-passive arithmetic from source.

Uses the independently authenticated complete trigger records. This bounded
arithmetic oracle does not execute generic triggers, infer missing mode gates,
or rewrite a profile/release identity.
"""
import argparse
import json
from pathlib import Path

from check_serpent_state_source import RECEIPT_SHA, documents, evaluate, require, trigger
from prepare_serpent_named_settings import encoded


def variable(action, name):
    values = action['a171']
    require(values[0] == name and values[1] == 'enum65537', 'Unexpected source variable')
    return values


def threshold(row, name):
    matches = []
    for condition in row['conditions']:
        expression = condition.get('expr')
        if expression and expression[0] == {'f82': [{'f51': ['Me', name]}]}:
            require(expression[2] == 'op20', 'Expected original greater-or-equal threshold')
            matches.append(expression[1])
    require(len(matches) == 1, 'Missing or ambiguous source threshold')
    return matches[0]


def build(root):
    docs = documents(root, (1379, 1389))
    bloom = 'SET_DYNASTY_13_SLIDER_VALUE'
    stack = 'SET_D13_BARKSKIN_STACKS'
    barkskin = trigger(docs, 1389, 7)
    defenses = [action['a142'] for action in barkskin['actions'] if 'a142' in action]
    require([a[:2] for a in defenses] == [
        ['Factor_HeadDefense', 'enum65537'], ['Factor_BodyDefense', 'enum65537']],
        'Source barkskin defense channels changed')
    require(defenses[0][2:] == defenses[1][2:], 'Head/body source factors differ')
    decrement = variable(barkskin['actions'][2], stack)
    initial_layers = variable(trigger(docs, 1389, 5)['actions'][1], stack)[2]
    recharge = variable(trigger(docs, 1389, 6)['actions'][0], 'SET_D13_BARKSKIN_STACK_TIMER_CD')[3]
    restored = variable(trigger(docs, 1389, 10)['actions'][0], stack)
    healed = trigger(docs, 1389, 13)['actions'][0]['a10']
    require(healed[:3] == ['D13_LIFEDRAIN_HEAL', 'enum65537', 'ModHP']
            and healed[8] == ['Vampire'], 'Source healing status changed')
    first_period = variable(trigger(docs, 1389, 12)['actions'][2], 'D13_LIFEDRAIN_TIMER')[3]
    repeat_period = variable(trigger(docs, 1389, 13)['actions'][1], 'D13_LIFEDRAIN_TIMER')[3]
    require(first_period == repeat_period == healed[5], 'Source life-drain periods differ')
    ranged_defenses = [a['a142'] for a in trigger(docs, 1379, 14)['actions']]
    require([a[:2] for a in ranged_defenses] == [
        ['Factor_HeadDefense', 'enum65538'], ['Factor_BodyDefense', 'enum65538']],
        'Source ranged-buff defense channels changed')
    break_block = trigger(docs, 1379, 11)
    require(break_block['actions'] == [{'a171': ['BLOCK_BROKEN', 'enum65538', 1.0, 1, None]}]
            and 'AttackType' not in json.dumps(break_block['conditions']),
            'Source block-break scope changed')
    final_hit = trigger(docs, 1389, 2)
    require(final_hit['events'] == [{'a16': ['enum65538', None, None, None, None]}]
            and final_hit['conditions'][-1] == {'expr': [{'f59': [None]}, 0.0, 'op18']}
            and final_hit['conditions'][0] == {'Or': [
                {'And': [{'expr': [{'f80': [None]}, 'Hit', 'op22']},
                    {'Or': [{'expr': [{'f82': [{'f51': ['Me', 'HIT_FIRST']}]}, 1.0, 'op22']},
                            {'expr': [{'f62': [None]}, 'Hit_Invisible_Hit', 'op22']}]}]},
                {'Not': [{'expr': [{'f80': [None]}, 'Hit', 'op22']}]}]},
            'Source final Hit listener/guards changed')
    require(len(final_hit['actions']) == 1 and set(final_hit['actions'][0]) == {'a149'},
            'Source final Hit action changed')
    final_hit_expression = final_hit['actions'][0]['a149'][2]
    final_hit_rows = [dict(calculated=damage,
        final=evaluate(final_hit_expression, {}, damage, 1))
        for damage in (0.025, 0.1, 0.5, 1, 30, 30 / 0.7)]
    defense_rows = []
    for layers in range(1, int(initial_layers) + 1):
        values = {stack: layers}
        defense_rows.append(dict(layers=layers,
            defenseFactor=evaluate(defenses[0][2], values, 0, 1),
            afterPreHit=evaluate(decrement[2], values, 0, 1),
            afterRecharge=evaluate(restored[2], values, 0, 1)))
    healing_rows = []
    for amounts in ([0, 0, 0, 0], [0.2, 0, 0, 0], [0.02, 0.04, 0.06, 0.08], [0.2] * 4):
        values = {f'SET_D13_{channel}_POISON_DAMAGE': amount for channel, amount in
                  zip(('WEAPON', 'UNARMED', 'RANGED', 'SHADOW'), amounts)}
        healing_rows.append(dict(poison=amounts, perTick=evaluate(healed[3], values, 0, 1)))
    return dict(schema='d13-passive-source-oracle-v2', sourceReceiptSHA256=RECEIPT_SHA,
        sourceLocks=sorted(docs), barkskinThreshold=threshold(trigger(docs, 1389, 5), bloom),
        lifeDrainThreshold=threshold(trigger(docs, 1389, 12), bloom),
        initialLayers=initial_layers, rechargeTicks=recharge, healingSegmentTicks=first_period,
        rangedPoisonDefenseFactor=evaluate(ranged_defenses[0][2], {}, 0, 1),
        weaponPoisonBreaksBlockWithoutAttackTypeRestriction=True,
        finalHitExpression=final_hit_expression, finalHitConditions=final_hit['conditions'],
        finalHitRows=final_hit_rows,
        defenseRows=defense_rows, healingRows=healing_rows,
        defenseToHealthConversion='Application percent-defense divisor; status ModHP bypasses PreHit',
        genericTriggerInterpreter=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = build(args.source)
    with args.output.open('xb') as file:
        file.write(encoded(result))
    args.output.chmod(0o600)
    print(json.dumps(dict(sourceLocks=result['sourceLocks'], defenseCases=len(result['defenseRows']),
                         healingCases=len(result['healingRows']), finalHitCases=len(result['finalHitRows']),
                         output=str(args.output))))
