#!/usr/bin/env python3
"""Bind recovered bottle FK and authenticate ordinary D13 rain/ground rules.

Outputs stay private. Cloud motion is explicitly unbound; consumers must obtain
the real cloud node sample before advancing cloud contacts. No static substitute
or full-fighter registration is produced here.
"""
import argparse
import hashlib
import json
from pathlib import Path

from check_serpent_action_source import NAMED_SHA, checked_json
from check_serpent_state_source import RECEIPT_SHA, documents, require, trigger
from prepare_serpent_named_settings import encoded
from recover_serpent_bottle_model import FILE, MOTION_SHA, verify
from sun_triad_assets import accessor_read, glb_read, matrix, pose_world, world_poses

MODEL_SHA = '5ccf41b00f10b3e504012a33e8f6212c7935a2ff4ac65b831eedfab2d91626cd'


def source_contract(source, named):
    docs = documents(source, (1400, 1402, 1403))
    records = checked_json(named, NAMED_SHA)['records']
    cloud = next(r for r in records if r['sourceRecordIndex'] == 69)['configuration']
    require(cloud['Animation'] == 'D13_Poison_Bomb_Cloud_Model_Attack'
            and cloud['FileName'] == 'ranged/universal/s_rng_agl_cloud_bullet.bin'
            and cloud['Looped'] is True and cloud['Align'][3] == [200., 0., 0.]
            and cloud['Align'][4:] == [['X'], ['GrandParent','Nodes','pelvis'],
                                       [None,'Nodes','magic_joint_root']], 'Cloud alignment changed')
    birth, end = trigger(docs,1402,0), trigger(docs,1402,1)
    require(birth['actions'] == [{'a6':['D13_Bottle_Throw_Model',None,None]}]
            and end['events'] == [{'a0':['D13_Bottle_Throw_Model','enum65537']}]
            and end['actions'][0]['a45'][15][7] == 'shd__shadow_ranged_agile_cloud'
            and end['actions'][1] == {'a50':[None,None]}, 'Bottle lifecycle changed')
    start, repeat = trigger(docs,1403,1), trigger(docs,1403,9)
    initial = {a['a171'][0]:a['a171'] for a in start['actions'] if 'a171' in a}
    require(start['events'] == [{'a1':['D13_Poison_Bomb_Cloud_Model_Attack','enum65537']}]
            and initial['D13_Poison_Random'][2] == {'f14':[1,4]}
            and repeat['priority'] == -10
            and repeat['actions'][0] == {'a171':['D13_Poison_Random','enum65537',{'f14':[1,4]},None,None]},
            'Cloud random ordering changed')
    target = {'f17':[{'f24':[{'f74':['enum65538']},'COM',None]}]}
    center = {'f17':[{'f24':[{'f74':['enum65537']},'Nodes','magic_joint_root']}]}
    bounds = [{'expr':[target,center,300.,'op1','op20']},
              {'expr':[target,center,300.,'op0','op21']}]
    for index, channel in enumerate(('Weapon','Unarmed','Ranged','Shadow'), 5):
        t = trigger(docs,1403,index)
        require(t['events'] == [{'a44':['enum65537','D13_Poison_Tick']}]
                and t['conditions'][-2:] == bounds
                and t['conditions'][2] == {'expr':[{'f82':[{'f51':['Me','D13_Poison_Random']}]},float(index-4),'op22']}
                and t['actions'] == [{'a171':[f'D13_Cloud_{channel}_Poison_Tick','enum65542',1.,0,None]}],
                'Cloud contact/channel changed')
    ground = trigger(docs,1403,11)
    ground_vars = {a['a171'][0]:a['a171'] for a in ground['actions'] if 'a171' in a}
    pulse = trigger(docs,1403,13)
    require(pulse['conditions'][-2:] == bounds and len(pulse['conditions']) == 4,
            'Ground zone or immunity guard changed')
    ground_stack = pulse['actions'][0]['a171']
    ground_damage = pulse['actions'][2]['a10']
    require(ground_stack == ['D13_Poison_Ground_Stacks','enum65538',
            [{'f82':[{'f51':['Enemy','D13_Poison_Ground_Stacks']}]},1.,'op0'],1200.,None]
            and ground_damage == ['SET_D13_GROUND_POISON','enum65538','ModHP',
                [0.,.02,{'f82':[{'f51':['Enemy','D13_Poison_Ground_Stacks']}]},'op2',1200.,'op3',
                 {'f213':[None]},'op2','op1'],None,1200.,None,None,['Poison']],
            'Ground stacking/damage changed')
    ground_repeat = trigger(docs,1403,14)
    require(ground_repeat['priority'] == -10
            and ground_repeat['actions'] == [{'a171':['D13_Poison_Ground_Tick','enum65537',1.,60.,None]}],
            'Ground interval changed')
    for index in (10,15,16):
        require(trigger(docs,1403,index)['events'] is not None, 'Missing cleanup event')
    require(trigger(docs,1403,15)['actions'][-1] == {'a50':[None,None]}
            and trigger(docs,1403,16)['actions'][-1] == {'a50':[None,None]}, 'Missing model deletion')
    # Only the source level-eight lock sets the reduction coefficient. Ordinary
    # levels 2..6 therefore leave it zero; do not import level-eight effects.
    return dict(schema='d13-rain-source-oracle-v1', receiptSHA256=RECEIPT_SHA,
        cloudPeriod=int(initial['D13_Poison_Tick'][3]),
        cloudLifetime=int(initial['D13_Poison_Cloud_Duration'][3]),
        groundDelay=int(initial['D13_Poison_Ground_CD'][3]),
        groundLifetime=int(ground_vars['D13_Poison_Ground_Duration'][3]),
        groundFirstPulse=int(ground_vars['D13_Poison_Ground_Tick'][3]),
        groundPeriod=int(ground_repeat['actions'][0]['a171'][3]),
        groundPoisonLifetime=int(ground_stack[3]), groundPoisonPerStack=ground_damage[3][1],
        halfWidth=300., cloudOffset=cloud['Align'][3][0],
        cloudRandomMin=1, cloudRandomMax=4, groundHasInvincibilityGuard=False,
        sourceLocks=sorted(docs), cloudMotionBound=False)


def bottle_binding(directory):
    path = directory/FILE
    require(hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA, 'Wrong recovered bottle generation')
    document = json.loads((directory/'bottle-source-private.json').read_bytes())
    verify(path,document)
    g,binary = glb_read(path)
    _,rest,parents = world_poses(g['nodes'])
    names = {node['name']:i for i,node in enumerate(g['nodes'])}
    animation = g['animations'][0]
    samples = []
    for tick in range(49):
        values = {}; local = [m.copy() for m in rest]
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            data = accessor_read(g,binary,sampler['output'])
            i,j,w = tick//2,min(24,tick//2+1),(tick%2)*.5
            a,b = data[i].astype(float),data[j].astype(float)
            if channel['target']['path']=='rotation' and a@b<0: b=-b
            values.setdefault(channel['target']['node'],{})[channel['target']['path']]=a*(1-w)+b*w
        for node,v in values.items(): local[node]=matrix(v['translation'],v['rotation'],[1,1,1])
        world=pose_world(local,parents)
        samples.append({key:(world[names[name]][:3,3]*100).tolist()
                        for key,name in [('root','ranged_root'),('left','gun_joint_l'),('right','gun_joint_r')]})
    return dict(schema='d13-bottle-motion-binding-v1',modelSHA256=MODEL_SHA,
        motionSHA256=MOTION_SHA,modelBytes=291180,animation='D13_Bottle_Throw_Model',
        endTick=48,coordinates='source-centimeters-z-converted',samples=samples)


def oracle(contract):
    # Independently exercise source bounds and formula, including exact edges,
    # vertical displacement (not a condition), misses and immunity. Native timer
    # event ordering still needs device verification; expectations use expired
    # status removal before same-tick condition dispatch.
    cases=[]
    for center in (-450.,0.,712.5):
        for offset in (-300.01,-300.,-299.99,0.,299.99,300.,300.01):
            for roll in range(1,5):
                for invincible in (False,True):
                    inside=center+offset>=center-contract['halfWidth'] and center+offset<=center+contract['halfWidth']
                    cases.append(dict(center=center,target=center+offset,roll=roll,invincible=invincible,
                        rainChannel=roll if inside and not invincible else None,groundStacks=1 if inside else 0))
    return dict(**contract,contactCases=cases,
        rainTicks=list(range(contract['cloudPeriod'],contract['cloudLifetime'],contract['cloudPeriod'])),
        groundTicks=list(range(contract['groundDelay'],contract['groundDelay']+contract['groundLifetime'],contract['groundPeriod'])))


def build(args):
    contract=source_contract(args.source,args.named)
    binding=bottle_binding(args.bottle)
    require(not args.output.exists(),'Use a fresh output directory')
    args.output.mkdir(parents=True,mode=0o700)
    for name,value in [('SF3_D13_Bottle_Motion_Binding.json',binding),('serpent-rain-oracle.json',oracle(contract))]:
        path=args.output/name;path.write_bytes(encoded(value));path.chmod(0o600)
    return dict(bottleSamples=len(binding['samples']),contactCases=len(oracle(contract)['contactCases']),
        cloudMotionBound=False,sourceLocks=contract['sourceLocks'])


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','named','bottle','output'):parser.add_argument('--'+name,type=Path,required=True)
    print(json.dumps(build(parser.parse_args())))
