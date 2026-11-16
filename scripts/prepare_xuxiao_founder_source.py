#!/usr/bin/env python3
"""Prepare Xu Xiao's exact D20 costume and gameplay source inputs.

Consumes the already decoded, authenticated local client configuration. The
output retains equipment alternatives, all original animation fields, trigger
ordering and every ancestor gate. It never evaluates source expressions or
registers an incomplete character. Original media stays outside the repository.
"""
from __future__ import annotations

import argparse
import copy
import io
import json
from pathlib import Path, PurePosixPath
import re
from zipfile import ZipFile

from pangu_source_identity import properties, record, matches_model, inventory_strings
from prepare_serpent_named_settings import (
    ARCHIVE_PIN, SPLIT, SPLIT_SHA, SCHEMA_PIN, AnimationProjection, encoded, member,
    pinned, require, sha, typed,
)
from prepare_serpent_source_rules import (
    PROD_PIN, COLLECTION_MEMBER, COLLECTION_PIN, ITEMS_MEMBER, ITEMS_PIN,
    BATTLE_SPLIT, BATTLE_PIN, TREE_PIN, Literal,
)
from source_floorfall_audio import Storage, compact


ROOT = Path(__file__).resolve().parents[1]
COLLECTION = 'D_LEGENDARY_WPN_IMPERIAL_GLOVES_01'
SLOTS = (
    ('WPN_IMPERIAL_GLOVES_01', 'WPN_IMPERIAL_GLOVES_01a'),
    ('ARM_AGL_49',), ('HLM_AGL_49',), ('RNG_AGL_KNIVES_06',),
)
MODELS = (
    'Top100/wpn__imperial_gloves_01_01', 'Top100/wpn__imperial_gloves_01_01a',
    'Top100/arm__agl_49', 'Top100/helm__agl_49', 'Top100/rng__agl_knives_01_06',
)
DYNASTY = 'settings_sets_dynasty.bytes'
GLOVES = 'settings_style_imperial_gloves.bytes'
ANIMATION_PINS = {
    DYNASTY: (334225, '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'),
    GLOVES: (26109, '50523ae995efd42cecd05d40a7f96a162858b8c0c41823165d3fa4994dbbd3f6'),
}
DEDICATED = tuple(range(1564, 1592))
STYLE = tuple(range(4786, 4795))
SHARED = (32, 2668)
LOCKS = tuple(sorted((*DEDICATED, *STYLE, *SHARED)))
CATALOG_PIN = (9100700, '2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055')
HEAD_PIN = (20354880, 'c2242893775f0ba0fb21e88d830419ff41afa117dd22f0aae2ea577e25d37ee4')


def read_bounded(path, maximum):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= maximum,
            'Expected a bounded regular local source file')
    return path.read_bytes()


def values(value):
    if type(value) is str:
        yield value
    elif type(value) is list:
        for child in value:
            yield from values(child)
    elif type(value) is dict:
        for child in value.values():
            yield from values(child)


def levels_and_equipment(prod_raw):
    pinned(prod_raw, PROD_PIN, 'decoded prod archive')
    with ZipFile(io.BytesIO(prod_raw)) as archive:
        collection_raw = pinned(member(archive, COLLECTION_MEMBER, 200000), COLLECTION_PIN, 'collections')
        items_raw = pinned(member(archive, ITEMS_MEMBER, 500000), ITEMS_PIN, 'items')
    source = record(collection_raw.decode(), COLLECTION, True)
    fields = properties(source)
    require(fields['ID'] == '142' and json.loads(fields['aliasKey']) == 'D20',
            'Original Founder collection identity differs')
    bucket = 'new ItemListBunch([' + ','.join(
        '[' + ','.join('ItemModels.' + name + '.ID' for name in slot) + ']'
        for slot in SLOTS) + '])'
    require(fields['bucket'] == bucket, 'Original four-slot equipment alternatives changed')
    levels = Literal(fields['leveling']).parse()
    require(list(levels) == ['1', '2', '3', '4', '5', '6'], 'Original Founder level sequence differs')
    for i in range(1, 7):
        tag = 'D20_DEFAULT_ABILITY' if i == 2 else f'D20_{i}_LEVEL'
        require(tag in levels[str(i)]['specialAbility']['attributes'], 'Original D20 level gate differs')
    equipment = []
    for slot, symbols in enumerate(SLOTS):
        for alternative, symbol in enumerate(symbols):
            source_item = record(items_raw.decode(), symbol)
            item = properties(source_item)
            tags = json.loads(item['Tags'])
            model = json.loads(item['Model'])
            require(model == MODELS[len(equipment)] and
                    any(tag.startswith('SET_DYNASTY_20_') for tag in tags),
                    'Original D20 equipment identity differs')
            equipment.append(dict(slot=slot, alternative=alternative, symbol=symbol,
                id=int(item['ID']), model=model, tags=tags,
                originalRecordSHA256=sha(source_item.encode())))
    return dict(collectionKey=COLLECTION, collectionID=142, alias='D20',
        equipmentSlots=[list(slot) for slot in SLOTS], equipment=equipment, levels=levels,
        sourceLiteral=fields['leveling'], sourceLiteralSHA256=sha(fields['leveling'].encode()),
        originalRecordSHA256=sha(source.encode()), levelsAreUnmergedOriginalEntries=True,
        fakeValueFieldsInterpreted=False, javascriptExecuted=False)


def animations(splits_raw, schema_raw):
    pinned(splits_raw, ARCHIVE_PIN, 'decoded splits archive')
    projection = AnimationProjection(schema_raw)
    with ZipFile(io.BytesIO(splits_raw)) as outer:
        split = member(outer, SPLIT, 2000000)
    require(sha(split) == SPLIT_SHA, 'Original animation split differs')
    result, source_files = [], {}
    with ZipFile(io.BytesIO(split)) as archive:
        for name, pin in ANIMATION_PINS.items():
            raw = pinned(member(archive, name, 400000), pin, name)
            reader = Storage(raw)
            require(reader.pos == len(raw), 'Animation source bytes not fully consumed')
            rows = reader.value(reader.root)
            require(type(rows) is list and len(rows) == (295 if name == DYNASTY else 13),
                    'Original animation table size differs')
            for index, row in enumerate(rows):
                require(type(row) is list and len(row) == 29, 'Original animation field layout differs')
                if name == DYNASTY:
                    selected = type(row[0]) is str and row[0].startswith('D20_')
                    require(selected == (250 <= index <= 294), 'Original D20 selection differs')
                    if not selected:
                        continue
                named = json.loads(encoded(projection.named(row)))
                restored = projection.unnamed(named)
                require(typed(row) == typed(restored), 'Lossy animation naming or JSON round trip')
                result.append(dict(sourceEntry=name, sourceSHA256=pin[1], sourceRecordIndex=index,
                    originalTypedValueSHA256=sha(encoded(typed(row))),
                    roundTripTypedValueSHA256=sha(encoded(typed(restored))), configuration=named))
            source_files[name] = raw
    require(len(result) == 58, 'Original D20 and Imperial Gloves motion inventory differs')
    return result, source_files


def lock_paths(tree):
    result = {}
    nodes = 0
    def visit(node, path, ancestry):
        nonlocal nodes
        nodes += 1
        require(nodes <= 30000 and len(path) <= 32 and node.get('kind') == 'SplitData'
                and len(node['fields']) == 3, 'Invalid original lock tree')
        children, conditions, name = node['fields']
        lineage = ancestry + [dict(treePath=path, rawConditions=copy.deepcopy(conditions),
                                   conditions=compact(conditions))]
        if name is not None:
            match = re.fullmatch(r'lock_([0-9]+)\.bytes', name)
            require(match is not None, 'Unexpected original lock reference')
            lock = int(match[1])
            if lock in LOCKS:
                result.setdefault(lock, []).append(lineage)
        require(children is None or type(children) is list, 'Invalid original lock children')
        for index, child in enumerate(children or []):
            visit(child, path + [index], lineage)
    visit(tree, [], [])
    require(set(result) == set(LOCKS), 'Selected original D20 lock paths are incomplete')
    return result


def triggers(splits_raw):
    pinned(splits_raw, ARCHIVE_PIN, 'decoded splits archive')
    with ZipFile(io.BytesIO(splits_raw)) as outer:
        split = pinned(member(outer, BATTLE_SPLIT, 17000000), BATTLE_PIN, 'battle split')
    records, originals = [], {}
    with ZipFile(io.BytesIO(split)) as archive:
        tree_raw = pinned(member(archive, 'lockTree.bytes', 1000000), TREE_PIN, 'lock tree')
        reader = Storage(tree_raw)
        require(reader.pos == len(tree_raw), 'Lock-tree bytes not fully consumed')
        paths = lock_paths(reader.value(reader.root))
        for lock in LOCKS:
            name = f'lock_{lock}.bytes'
            raw = member(archive, name, 1000000)
            reader = Storage(raw)
            require(reader.pos == len(raw), 'Trigger source bytes not fully consumed')
            value = reader.value(reader.root)
            round_trip = json.loads(encoded(value))
            require(typed(value) == typed(round_trip), 'Lossy trigger JSON round trip')
            sets = []
            for set_index, source_set in enumerate(value):
                require(source_set['kind'] == 'TriggerSetData' and len(source_set['fields']) == 2,
                        'Original TriggerSetData layout differs')
                set_name, trigger_rows = source_set['fields']
                if lock in DEDICATED:
                    require(set_name.startswith(('SET_DYNASTY_20', 'SET_D20_', 'D20_')),
                            'Original D20 trigger identity differs')
                rows = []
                for index, trigger in enumerate(trigger_rows):
                    require(trigger['kind'] == 'TriggerData' and len(trigger['fields']) == 6,
                            'Original TriggerData layout differs')
                    fields = trigger['fields']
                    rows.append(dict(triggerIndex=index, rawSourceFields=copy.deepcopy(fields),
                        priority=compact(fields[2]), events=compact(fields[3]),
                        conditions=compact(fields[4]), actions=compact(fields[5])))
                sets.append(dict(sourceSetIndex=set_index, sourceSetName=set_name, triggers=rows))
            records.append(dict(sourceLock=lock, sourceFile=name, sourceBytes=len(raw), sourceSHA256=sha(raw),
                scope='dedicatedD20' if lock in DEDICATED else 'imperialGlovesStyle' if lock in STYLE else 'sharedConditional',
                sourceTreePaths=paths[lock], sets=sets,
                originalTypedValueSHA256=sha(encoded(typed(value))),
                roundTripTypedValueSHA256=sha(encoded(typed(round_trip))), allSixTriggerFieldsPreserved=True))
            originals[name] = raw
    originals['lockTree.bytes'] = tree_raw
    return records, originals


def catalog_inventory(raw, equipment, animation_rows):
    pinned(raw, CATALOG_PIN, 'Android source catalog')
    catalog = [json.loads(line) for line in raw.splitlines() if line]
    require(len(catalog) < 100000 and len({row['file'] for row in catalog}) == len(catalog),
            'Duplicate or oversized catalog')
    def identity(row):
        return {key: row[key] for key in ('file', 'bytes', 'sha256')}
    models = [dict(symbol=item['symbol'], model=item['model'], sourceBundles=[identity(row)
        for row in catalog if any(matches_model(path, item['model']) for path in inventory_strings(row))])
        for item in equipment]
    paths = {}
    for row in animation_rows:
        source = row['configuration']['FileName']
        path = PurePosixPath(source)
        require(not path.is_absolute() and '..' not in path.parts and path.suffix == '.bin',
                'Unsafe original motion path')
        paths.setdefault(source, []).append(row['configuration']['Animation'])
    motions = []
    for source, aliases in paths.items():
        asset = 'assets/gamedata/resources/content/animations/binaries/' + str(PurePosixPath(source).with_suffix('.bytes')).lower()
        hits = []
        for row in catalog:
            for entry in row.get('paths', []):
                if entry['path'].lower() == asset:
                    hits.append(dict(**identity(row), resourcePath=entry['path'],
                                     pathID=str(entry['path_id']), fileID=entry['file_id']))
        motions.append(dict(sourceFile=source, aliases=aliases, sourceBundles=hits))
    return dict(equipment=models, motions=motions,
        missingEquipment=[row['model'] for row in models if not row['sourceBundles']],
        missingMotionFiles=[row['sourceFile'] for row in motions if not row['sourceBundles']],
        catalogMatchesAreNotPhysicalByteVerification=True)


def build(args):
    output = args.output.absolute()
    require(not output.exists() and output.parent.resolve() == output.parent
            and output != ROOT and ROOT not in output.parents,
            'Use a new private output directory outside the repository')
    head_raw = pinned(read_bounded(args.head, 21000000), HEAD_PIN, 'existing Xu Xiao personal head')
    require(head_raw[:4] == b'glTF', 'Existing Xu Xiao head must remain actual GLB geometry')
    prod = read_bounded(args.prod, 3000000)
    splits = read_bounded(args.splits, 18000000)
    equipment = levels_and_equipment(prod)
    schema = read_bounded(args.schema, 20000)
    motions, animation_sources = animations(splits, schema)
    rules, rule_sources = triggers(splits)
    inventory = catalog_inventory(read_bounded(args.catalog, 10000000), equipment['equipment'], motions)
    header = dict(schema='xuxiao-d20-original-source-v1', characterName='徐骁',
        sourceCollection='D20', sourceConfiguration='1.46.0.16.16733-prod',
        sourceProdSHA256=PROD_PIN[1], sourceSplitsSHA256=ARCHIVE_PIN[1],
        sourceAnimationSchemaSHA256=SCHEMA_PIN[1], nativeAnimationSchemaMethod=16684,
        personalHeadBytes=HEAD_PIN[0], personalHeadSHA256=HEAD_PIN[1],
        sourceOnly=True, runtimeBound=False, productionActivated=False,
        decryptionPerformed=False, javascriptExecuted=False, networkBytes=0,
        nativeAcceptance=False, deviceAcceptance=False, testFlightUploaded=False)
    output.mkdir(parents=True, mode=0o700)
    (output / 'original-sources').mkdir(mode=0o700)
    products = []
    def save(name, raw):
        path = output / name
        with path.open('xb') as handle:
            handle.write(raw)
        path.chmod(0o600)
        products.append(dict(file=name, bytes=len(raw), sha256=sha(raw)))
    save('xuxiao-original-equipment-levels-v1.json', encoded({**header, **equipment}))
    save('xuxiao-original-animation-inputs-v1.json', encoded(dict(**header, records=motions)))
    save('xuxiao-original-trigger-inputs-v1.json', encoded(dict(**header, records=rules)))
    save('xuxiao-required-resources-v1.json', encoded(dict(**header, **inventory)))
    save('original-sources/animation-schema-private.json', schema)
    for name, raw in {**animation_sources, **rule_sources}.items():
        save('original-sources/' + name, raw)
    receipt = dict(**header, dedicatedAnimationRecords=45, imperialGlovesAnimationRecords=13,
        animationRoundTripRecords=len(motions), dedicatedLocks=list(DEDICATED), styleLocks=list(STYLE),
        sharedConditionalLocks=list(SHARED), triggerRoundTripLocks=len(rules),
        triggerSets=sum(len(row['sets']) for row in rules),
        triggerRecords=sum(len(s['triggers']) for row in rules for s in row['sets']),
        originalTreePaths=sum(len(row['sourceTreePaths']) for row in rules),
        sourceMotionFiles=len(inventory['motions']), missingEquipment=inventory['missingEquipment'],
        missingMotionFiles=inventory['missingMotionFiles'], products=copy.deepcopy(products),
        headReprocessed=False, personalHeadCopied=False,
        boundary='Exact source inputs only. Costume geometry, pose decoding, FX/audio, gameplay interpreter and native assembly are not completed by this preparation.')
    save('receipt-private.json', encoded(receipt))
    print(json.dumps(dict(output=str(output), animations=len(motions), locks=len(rules),
        triggerRecords=receipt['triggerRecords'], missingEquipment=len(inventory['missingEquipment']),
        missingMotions=len(inventory['missingMotionFiles']), receipt=products[-1]), ensure_ascii=False))
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('prod', 'splits', 'schema', 'catalog', 'head', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    build(parser.parse_args())
