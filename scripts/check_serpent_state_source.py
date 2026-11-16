#!/usr/bin/env python3
"""Generate numeric test oracles directly from authenticated D13 source RPN.

Only arithmetic needed by the selected state projection is interpreted. Unknown
functions/operators fail. This is not a general trigger or input interpreter.
"""
import argparse
import hashlib
import json
from pathlib import Path

from prepare_serpent_named_settings import encoded, typed
from source_floorfall_audio import Storage, compact

RECEIPT_SHA = 'd169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37'


def require(value, message):
    if not value:
        raise ValueError(message)


def documents(root):
    raw = (root/'receipt-private.json').read_bytes()
    require(hashlib.sha256(raw).hexdigest() == RECEIPT_SHA, 'Unverified source receipt')
    pins = {r['sourceLock']: r for r in json.loads(raw)['records']}
    result = {}
    for lock in (1379,1384,1389,1395,1397,1400):
        document = json.loads((root/f'serpent-lock-{lock}-source-v1.json').read_bytes())
        raw = (root/'original-sources'/f'lock_{lock}.bytes').read_bytes()
        require(hashlib.sha256(raw).hexdigest() == pins[lock]['sourceSHA256'], 'Source bytes changed')
        reader = Storage(raw)
        original = reader.value(reader.root)
        rebuilt = []
        for source_set in document['sets']:
            triggers = []
            for t in source_set['triggers']:
                fields = t['rawSourceFields']
                require(compact(fields[3:]) == [t[k] for k in ('events','conditions','actions')],
                        'Source projection changed')
                triggers.append(dict(kind='TriggerData', fields=fields))
            rebuilt.append(dict(kind='TriggerSetData', fields=[source_set['sourceSetName'], triggers]))
        require(typed(original) == typed(rebuilt), 'Source trigger reconstruction changed')
        result[lock] = document
    return result


def evaluate(value, variables, damage, amplifier):
    if isinstance(value, (int,float)):
        return float(value)
    if isinstance(value, dict):
        if set(value) == {'f59'}: return damage
        if set(value) == {'f213'}: return amplifier
        if set(value) == {'f82'}:
            owner, name = value['f82'][0]['f51']
            require(owner == 'Me', 'Unsupported variable owner')
            return variables.get(name, 0.0)
        raise ValueError('Unsupported source function')
    require(isinstance(value,list), 'Unsupported source expression')
    stack = []
    for token in value:
        if isinstance(token,str):
            require(token in ('op0','op1','op2','op3','op10') and len(stack)>=2, 'Unsupported RPN')
            right, left = stack.pop(), stack.pop()
            if token == 'op0': answer = left+right
            elif token == 'op1': answer = left-right
            elif token == 'op2': answer = left*right
            elif token == 'op3': answer = left/right
            else: answer = min(left,right)
            stack.append(answer)
        else: stack.append(evaluate(token, variables, damage, amplifier))
    require(len(stack)==1, 'Incomplete RPN')
    return stack[0]


def trigger(docs, lock, index, source_set=0):
    row = docs[lock]['sets'][source_set]['triggers'][index]
    require(row['triggerIndex'] == index, 'Source trigger order changed')
    return row


def build(root):
    docs=documents(root); cases=[]
    for level in (2,3,5,6):
        for amplifier in (1,2.5):
            for channel,index in (('weapon',17),('unarmed',18),('ranged',20),('shadow',22)):
                for damage in (0.1,1):
                    variables={'PERK_POISON_DAMAGE':0.02,'PERK_COBRA_DANCE_DAMAGE':0.03,
                               'PERK_VENOMOUS_LIMBS_DAMAGE':0.04,'PERK_SECRET_RITUAL_DAMAGE':0.05}
                    init=[trigger(docs,1389,1)]
                    if level>=3: init.append(trigger(docs,1395,0))
                    if level>=5: init.append(trigger(docs,1397,0))
                    for t in init:
                        for a in t['actions']:
                            name,owner,expression,_,_=a['a171']
                            require(owner=='enum65537','Wrong initializer owner')
                            variables[name]=evaluate(expression,variables,damage,amplifier)
                    poison=trigger(docs,1389,index)['actions'][0]['a171']
                    bloom=trigger(docs,1384,3)['actions'][0]['a171']
                    for _ in range(2):
                        variables[poison[0]]=evaluate(poison[2],variables,damage,amplifier)
                        variables[bloom[0]]=evaluate(bloom[2],variables,damage,amplifier)
                    explosion=sum(-evaluate(a['a10'][3],variables,damage,amplifier)
                                  for a in trigger(docs,1379,16)['actions'])
                    cases.append(dict(level=level,amplifier=amplifier,channel=channel,damage=damage,
                        poison=variables[poison[0]],duration=poison[3],bloom=variables[bloom[0]],
                        cooldown=variables['SET_DYNASTY_13_ABILITY_CD'],explosion=explosion))
    # Rain coefficients are read from the source initializer, not tooltip FakeValues.
    rain=trigger(docs,1400,0)['actions'][0]['a171'][2]
    require(rain==0.02,'Cloud source changed')
    return dict(schema='d13-state-source-oracle-v1',receiptSHA256=RECEIPT_SHA,cases=cases,
                sourceLocks=sorted(docs),rainPerTick=rain,fullTriggerInterpreter=False)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=build(args.source)
    with args.output.open('xb') as file: file.write(encoded(result))
    args.output.chmod(0o600)
    print(json.dumps({'sourceOracleCases':len(result['cases']),'authenticatedSourceLocks':result['sourceLocks']}))
