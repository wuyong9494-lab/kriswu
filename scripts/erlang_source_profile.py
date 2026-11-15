"""Bind D15/Spear source clocks and explicit arena statistics to real geometry."""
from __future__ import annotations

import copy
import math
from pathlib import Path

from sun_triad_assets import require

SETTINGS_SHA = '742a807523b97a58aefffa5d14dbc35eb7c39b4f9e4c5b026f27788f623d4835'
REFERENCE_CATALOG_SHA = '41a63ef6a87f994be75560da10ae3adea881d472ae343eaaaaf7758593d279e8'
SOURCE_VERSION = 'supplied iOS 1.46.1; packaged configuration 1.46.0.16.16733-prod'
THROW_ROLES = ('ordinaryThrowBack', 'ordinaryThrownBack', 'ordinaryThrowForward',
               'ordinaryThrownForward', 'ordinaryPanguEscape', 'ordinaryPanguResisted')
COMMAND_ROLES = {
    'weapon': 'weapon1', 'weaponForward': 'weaponForward', 'weaponUp': 'weaponUp',
    'weaponDown': 'weaponDown', 'weaponBack': 'weaponBack', 'heavy': 'heavy',
    'kick': 'kick', 'kickForward': 'kickForward', 'kickUp': 'kickUp',
    'kickDown': 'kickDown', 'kickBack': 'kickBack',
}


def source_record(document, name):
    rows = [r for r in document['records'] if r['configuration'].get('FileName')
            and Path(r['configuration']['FileName']).stem == name]
    # Dojo uses the same motion but different lobby policy. The combat alias
    # remains the original non-Dojo entry, never a guessed filename match.
    rows = [r for r in rows if not r['configuration']['Animation'].endswith(('_Dojo','_Mirror'))]
    if len(rows) > 1 and name in ('staff_step_forward', 'staff_step_back'):
        rows = [r for r in rows if r['sourceEntry'] == 'settings_style_imperial_spear.bytes']
    if name == 'staff_idle':
        rows = [r for r in rows if r['configuration']['Animation'] == 'D15_Avatara_Transform_Out']
    require(len(rows) == 1, 'Missing or ambiguous configuration for '+name)
    return rows[0]


def source_window(config, raw_frames):
    """Native positive First/End frames are one based; null is the default."""
    first = 0 if config['FirstFrame'] is None else max(0, config['FirstFrame']-1)
    end = raw_frames-1 if config['EndFrame'] is None else min(raw_frames-1, max(0, config['EndFrame']-1))
    middle = 1 if config['MidFrames'] is None else config['MidFrames']
    require(type(first) is int and type(end) is int and 0 <= first <= end < raw_frames
            and type(middle) is int and 0 <= middle <= 8, 'Unbound source crop/stride')
    return first, end, middle+1


def source_end_event_tick(config, raw_frames):
    """Native EndIndex-floor(position)<=SelfEndFrame, at source speed one.

    This is an event boundary, not a reason to discard the remaining poses.
    Sound Frame has its separate non-subtracting origin.
    """
    first, end, stride = source_window(config, raw_frames)
    before = 4 if config['SelfEndFrame'] is None else config['SelfEndFrame']
    require(type(before) is int and 0 <= before <= 10000, 'Unbound source SelfEndFrame')
    return max(0, end-first-before)*stride


def rounded(value):
    return int(math.copysign(math.floor(abs(value)+.5), value))


def ordinary_throws(profile, reference):
    policy = copy.deepcopy(reference['ordinaryThrows'])
    require(policy['id'] == 'source-common-throws-and-d19-pair-v1'
            and policy['simultaneousContactPolicy'] == 'sourceComplementaryLottery'
            and policy['attempts'] == [], 'Source paired-throw policy differs')
    source = policy['source']
    require({k:source[k] for k in source if k != 'motions'} == dict(
        normalizedUnarmedPower=1000, millimetersPerSourceUnitNumerator=92,
        millimetersPerSourceUnitDenominator=10, maximumRangeSourceUnits=102,
        forwardWallThresholdSourceUnits=150, backWallThresholdSourceUnits=100,
        throwDisabledAfterVictimEndTicks=105), 'Source paired-throw constants differ')
    clips = {c['name']:c for c in profile['clips']}
    require({m['role'] for m in source['motions'].values()} == set(THROW_ROLES), 'Paired roles differ')
    for motion in source['motions'].values():
        clip = clips[profile['roles'][motion['role']]]
        require(clip['sha256'] == motion['sourceSHA256']
                and clip['playbackTicks'] == motion['lastSampleTick'] == 2*(clip['frames']-1),
                'Paired original motion identity or clock differs')
        tracks = clip['tracks']
        motion['rootMillimeters'] = [rounded(p[0]*1000) for p in tracks['root']]
        motion['footLeftMillimeters'] = rounded(tracks['footL'][0][0]*1000)
        motion['pelvisMillimeters'] = rounded(tracks['pelvis'][0][0]*1000)
    require(all(len(c['tracks']['centerOfMass']) == 2*c['frames']-1 for c in profile['clips']),
            'Every actor pose needs its own source mass-weighted centre')
    return policy


def combat_rules(profile, document):
    clips = {c['name']:c for c in profile['clips']}
    attacks, receipts = [], []
    impact = dict(distanceMillimeters=160, durationTicks=8,
                  launchVelocityMillimetersPerTick=0, gravityMillimetersPerTickSquared=18)
    blocked = dict(distanceMillimeters=60, durationTicks=6,
                   launchVelocityMillimetersPerTick=0, gravityMillimetersPerTickSquared=18)
    pairs = []
    links = {link['from']:link['to'] for link in profile['comboLinks']}
    for command, role in COMMAND_ROLES.items():
        name, visited = profile['roles'][role], set()
        while name not in visited:
            pairs.append((command, name)); visited.add(name)
            if name not in links: break
            name = links[name]
    pairs += [(command, profile['roles']['kickJump']) for command in COMMAND_ROLES if command.startswith('kick')]
    # This second stage is selected only by the original paired PostHit
    # transition. It is not a combo-button destination, but still needs its own
    # authenticated capsule contact window instead of inheriting Miss's strike.
    if 'imperialHeavyActive' in profile['roles']:
        pairs.append(('heavy', profile['roles']['imperialHeavyActive']))
    for command, name in dict.fromkeys(pairs):
        clip = clips[name]; record = source_record(document, name); config = record['configuration']
        first, end, stride = source_window(config, clip['sourceUncroppedFrames'])
        require(clip['frames'] == end-first+1 and clip['playbackTicks'] == (end-first)*stride,
                'Combat geometry and source clock differ')
        shapes = clip['tracks']['collisionEdges'] + clip['tracks']['hurtCapsules']
        by_id = {p['id']:p for p in shapes}; strikes = []
        for item in config['Intervals'] or []:
            if item['Type'] != 'Attack':
                continue
            parts, damage = item['AttackingParts'], item['Damage']
            require(parts, 'Original physical attack has no configured part')
            unresolved = [p for p in parts if p not in by_id]
            require(not unresolved or (config['Animation'] == 'Imperial_Spear_Upper_Slash'
                    and set(unresolved) <= {'Tight_Left','Tight_right'}),
                    'Original physical attack part is unbound')
            resolved = [p for p in parts if p in by_id]
            require(resolved, 'No original capsule resolves for this physical strike')
            require(damage and damage['Attack'] in ('WeaponDamage', 'UnarmedDamage')
                    and damage['BaseDamage'] is not None, 'Unsupported source damage formula')
            start = max(1, stride*(max(0, (item['Start'] or 1)-1)-first))
            stop = min(clip['playbackTicks'], stride*((item['End'] or end+1)-first)-1)
            require(start <= stop, 'Original strike lies outside source clip')
            sides = [] if command.startswith('kick') else sorted({by_id[p]['side'] for p in resolved if 'side' in by_id[p]})
            require(set(sides) <= set(profile['activeWeaponSides']), 'Source spear side is unavailable')
            amount = rounded(damage['BaseDamage']*1000)
            strikes.append(dict(id=len(strikes), startTick=start, endTick=stop, weaponSides=sides,
                damage=amount, damageKind='weapon' if damage['Attack']=='WeaponDamage' else 'unarmed',
                blockedDamage=rounded(amount*.25), knocksDown=False,
                hitStopTicks=4, blockedHitStopTicks=2, impact=impact, blockedImpact=blocked,
                collisionEdgeIDs=resolved))
            receipts.append(dict(command=command, clip=name, sourceEntry=record['sourceEntry'],
                sourceSHA256=record['sourceSHA256'], sourceRecordIndex=record['sourceRecordIndex'],
                sourceInterval=item, unresolvedConfiguredPartNames=unresolved,
                missingPartBehavior=None if not unresolved else dict(
                    policy='ignore-unresolved-exact-name',nativeMethods=[38174,36245],
                    evidenceSHA256=['a154455a26f130f8f780d4487a195beeda3e118ff32e259c02c81b5392750011',
                                    '492f7ba708f80a627af88ac9002ea14242d250744ee715b549d596aeeb4c427e'],
                    reason='Native exact String.Equals lookup returns null; caller skips only that name.'),
                applicationNormalizedPower=1000, normalizedDamage=amount))
        require(strikes, 'No source contact window for '+name)
        attacks.append(dict(command=command, clipName=name, strikes=strikes))
    return dict(id='erlang-d15-source-imperial-spear-geometry-v1', basis='applicationAdaptation',
        sourceVersion=SOURCE_VERSION, evidence=[
            'Original IMPERIAL_SPEAR/agile-kick intervals, both original spear capsule sides and real body capsules, native source stride/crop.',
            'Application normalization: WeaponDamage=1000; UnarmedDamage=1000; blocked damage=25 percent.',
            'Application hit-stop4/2 ticks and recoil160mm/8ticks or60mm/6ticks; no claim these are original impulse magnitudes.',
            'Imperial combo anchors35/15/37 use original IntervalEnd:Transitional and destination FrameShift0.',
            'Native38174/36245 performs exact String.Equals capsule lookup and skips null: unresolved Tight_Left/Tight_right are ignored, while original Leg/Foot parts remain.'], attacks=attacks), receipts
