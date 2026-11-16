#!/usr/bin/env python3
"""Recover exact D13 levels, trigger fields and original lock-tree gates.

All inputs are already decoded local source. JavaScript is parsed only as a
restricted literal; conditions and action arrays are never evaluated. The
result is source evidence, not an executable ruleset or release manifest.
"""
from __future__ import annotations

import argparse
import copy
import io
import json
import math
from pathlib import Path
import re
from zipfile import ZipFile

from pangu_source_identity import properties, record
from prepare_serpent_named_settings import ARCHIVE_PIN, encoded, member, pinned, require, sha, typed
from source_floorfall_audio import Storage, compact


PROD_PIN = (2751235, '165f5b1483909c461fabc86c591efd01ebb4915cc34ef7bf2579d52c94b35950')
COLLECTION_MEMBER = 'scripts/features/collection/entities/collections.js'
COLLECTION_PIN = (121764, '27acd4f4e000b44806f2c19e8f49c4be08e0574298e0ce4be00015bd9f84ed6d')
ITEMS_MEMBER = 'scripts/features/items/entities/items.js'
ITEMS_PIN = (394369, '745b6e2b81bf2cfd5ac5b9bc03daad3590df05629ff8e7ec6f9578ea47cb1270')
COLLECTION_KEY = 'D_LEGENDARY_WPN_SHUANGOU_01_04'
ITEMS = ('WPN_SHUANGOU_01_04', 'ARM_AGL_41', 'HLM_AGL_41', 'RNG_BOTTLE_01_02')
BATTLE_SPLIT = 'splits/split_battle_triggers.bytes'
BATTLE_PIN = (16429699, 'c3941a009cf87916ba076915b77bf308c33e7a00b9cdbd618bb353b5a6f7651b')
TREE_PIN = (885808, 'c8ab9d34b121365e5a8f1f58d1f2be49f7e57d0074ca819657dffd3f02675d11')
DEDICATED_LOCKS = tuple(range(1374, 1409))
STYLE_LOCKS = (1056, 1067, 4993, 4994, 4996, 4997, 4998, 4999, 5000, 5001, 5002, 5003)
# These four are referenced by the D13 equipment/mode paths but are not the
# dedicated set rules. Preserve their complete conditions and separate scope.
SHARED_LOCKS = (11, 12, 328, 2674)
LOCKS = tuple(sorted(set(DEDICATED_LOCKS + STYLE_LOCKS + SHARED_LOCKS)))


class Literal:
    """Small non-executing grammar for the pinned collection's leveling object."""
    def __init__(self, text):
        require(type(text) is str and 0 < len(text) < 20000, 'Source literal size differs')
        self.text, self.pos, self.nodes = text, 0, 0

    def space(self):
        while self.pos < len(self.text) and self.text[self.pos].isspace(): self.pos += 1

    def take(self, char):
        self.space()
        if self.text.startswith(char, self.pos):
            self.pos += len(char)
            return True
        return False

    def string(self):
        self.space()
        require(self.pos < len(self.text) and self.text[self.pos] == '"', 'Expected JSON source string')
        value, size = json.JSONDecoder().raw_decode(self.text[self.pos:])
        require(type(value) is str, 'Expected source string')
        self.pos += size
        return value

    def value(self, depth=0):
        self.nodes += 1
        require(depth <= 32 and self.nodes <= 5000, 'Source literal nesting exceeds bounds')
        self.space()
        if self.take('{'):
            result = {}
            if self.take('}'): return result
            while True:
                self.space()
                if self.text[self.pos:self.pos+1] == '"': key = self.string()
                else:
                    match = re.match(r'(?:[A-Za-z_$][\w$]*|[0-9]+)', self.text[self.pos:])
                    require(match is not None, 'Unsupported source object key')
                    key = match[0]; self.pos += len(key)
                require(key not in result and self.take(':'), 'Repeated source key or missing colon')
                result[key] = self.value(depth+1)
                if self.take('}'): return result
                require(self.take(','), 'Expected source object separator')
                if self.take('}'): return result
        if self.take('['):
            result = []
            if self.take(']'): return result
            while True:
                result.append(self.value(depth+1))
                if self.take(']'): return result
                require(self.take(','), 'Expected source array separator')
                if self.take(']'): return result
        if self.text[self.pos:self.pos+1] == '"': return self.string()
        for token, value in (('true', True), ('false', False), ('null', None)):
            if self.take(token): return value
        match = re.match(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?', self.text[self.pos:])
        require(match is not None, 'Only source literal values are permitted')
        self.pos += len(match[0])
        result = json.loads(match[0])
        require(type(result) is not float or math.isfinite(result), 'Nonfinite source number')
        return result

    def parse(self):
        value = self.value()
        self.space()
        require(self.pos == len(self.text), 'Trailing or executable source expression')
        return value


def original_levels(prod_raw):
    pinned(prod_raw, PROD_PIN, 'decoded prod archive')
    with ZipFile(io.BytesIO(prod_raw)) as archive:
        collection_raw = pinned(member(archive, COLLECTION_MEMBER, 200000), COLLECTION_PIN, 'collections')
        items_raw = pinned(member(archive, ITEMS_MEMBER, 500000), ITEMS_PIN, 'items')
    collection_text = record(collection_raw.decode(), COLLECTION_KEY, True)
    fields = properties(collection_text)
    require(fields['ID'] == '117' and json.loads(fields['aliasKey']) == 'D13', 'Original collection identity differs')
    expected_bucket = 'new ItemListBunch([' + ','.join('ItemModels.'+key+'.ID' for key in ITEMS) + '])'
    require(fields['bucket'] == expected_bucket, 'Original D13 equipment membership differs')
    levels = Literal(fields['leveling']).parse()
    require(list(levels) == [str(i) for i in range(1, 9)], 'Original D13 level sequence differs')
    required = {2:'D13_DEFAULT_ABILITY',3:'D13_PASSIVE_UPGRADE',4:'D13_ABILITIES_UPGRADE',
                5:'D13_PASSIVE_UPGRADE_2',6:'D13_POISON_BOMB',7:'D13_7_LEVEL',8:'D13_8_LEVEL'}
    for level, key in required.items():
        require(key in levels[str(level)]['specialAbility']['attributes'], 'Original D13 level gate differs')
    equipment = []
    for key in ITEMS:
        item = properties(record(items_raw.decode(), key))
        tags = json.loads(item['Tags'])
        require(any(tag.startswith('SET_DYNASTY_13_') for tag in tags), 'Original equipment tag differs')
        equipment.append(dict(symbol=key, id=int(item['ID']), model=json.loads(item['Model']), tags=tags))
    return dict(collectionKey=COLLECTION_KEY, collectionID=117, alias='D13', equipment=equipment,
        levels=levels, sourceLiteral=fields['leveling'], sourceLiteralSHA256=sha(fields['leveling'].encode()),
        sourceCollectionRecordSHA256=sha(collection_text.encode()), sourceCollectionSHA256=COLLECTION_PIN[1],
        sourceItemsSHA256=ITEMS_PIN[1], levelsAreOriginalEntriesNotAccumulated=True,
        fakeValueFieldsAreNotInterpreted=True, javascriptExecuted=False)


def tree_paths(tree):
    result = {}
    nodes = 0
    def visit(node, path, ancestry):
        nonlocal nodes
        nodes += 1
        require(nodes <= 30000 and len(path) <= 32 and node.get('kind') == 'SplitData', 'Invalid lock tree node')
        fields = node['fields']
        require(len(fields) == 3, 'Original lock tree layout differs')
        children, conditions, filename = fields
        lineage = ancestry + [dict(treePath=path, rawConditions=copy.deepcopy(conditions), conditions=compact(conditions))]
        if filename is not None:
            match = re.fullmatch(r'lock_([0-9]+)\.bytes', filename)
            require(match is not None, 'Unexpected original lock reference')
            lock = int(match[1])
            if lock in LOCKS: result.setdefault(lock, []).append(lineage)
        require(children is None or type(children) is list, 'Invalid original lock children')
        for index, child in enumerate(children or []): visit(child, path+[index], lineage)
    visit(tree, [], [])
    require(set(result) == set(LOCKS), 'Selected original lock-tree references are incomplete')
    return result


def original_triggers(splits_raw):
    pinned(splits_raw, ARCHIVE_PIN, 'decoded splits archive')
    with ZipFile(io.BytesIO(splits_raw)) as outer:
        split = pinned(member(outer, BATTLE_SPLIT, 17000000), BATTLE_PIN, 'battle split')
    records, original_files = [], {}
    with ZipFile(io.BytesIO(split)) as archive:
        tree_raw = pinned(member(archive, 'lockTree.bytes', 1000000), TREE_PIN, 'lock tree')
        reader = Storage(tree_raw)
        tree = reader.value(reader.root)
        paths = tree_paths(tree)
        for lock in LOCKS:
            name = f'lock_{lock}.bytes'
            raw = member(archive, name, 1000000)
            reader = Storage(raw)
            require(reader.pos == len(raw), 'Original trigger bytes not fully consumed')
            value = reader.value(reader.root)
            parsed = json.loads(encoded(value))
            require(typed(value) == typed(parsed), 'Original trigger value changed after JSON round trip')
            sets = []
            for set_index, source_set in enumerate(value):
                require(source_set['kind'] == 'TriggerSetData' and len(source_set['fields']) == 2,
                        'Original TriggerSetData layout differs')
                set_name, triggers = source_set['fields']
                if lock in DEDICATED_LOCKS:
                    require(set_name.startswith('SET_DYNASTY_13'), 'Dedicated D13 source identity differs')
                rows = []
                for index, trigger in enumerate(triggers):
                    require(trigger['kind'] == 'TriggerData' and len(trigger['fields']) == 6,
                            'Original TriggerData layout differs')
                    fields = trigger['fields']
                    rows.append(dict(triggerIndex=index, rawSourceFields=copy.deepcopy(fields),
                        rawCompactTriggerFields=compact(fields), priority=compact(fields[2]),
                        events=compact(fields[3]), conditions=compact(fields[4]), actions=compact(fields[5])))
                sets.append(dict(sourceSetIndex=set_index, sourceSetName=set_name, triggers=rows))
            scope = 'dedicatedD13' if lock in DEDICATED_LOCKS else 'shuangouStyle' if lock in STYLE_LOCKS else 'sharedOrModeConditional'
            records.append(dict(sourceLock=lock, scope=scope, sourceFile=name, sourceBytes=len(raw),
                sourceSHA256=sha(raw), sourceTreePaths=paths[lock], sets=sets,
                sourceTypedValueSHA256=sha(encoded(typed(value))),
                jsonRoundTripTypedValueSHA256=sha(encoded(typed(parsed))), allSixTriggerFieldsPreserved=True))
            original_files[name] = raw
    original_files['lockTree.bytes'] = tree_raw
    return records, original_files


def build(args):
    levels = original_levels(args.prod.read_bytes())
    records, originals = original_triggers(args.splits.read_bytes())
    output = args.output.resolve()
    require(not output.exists() and Path(__file__).resolve().parents[1] not in output.parents,
            'Use a new private output outside the public repository')
    output.mkdir(parents=True, mode=0o700); (output/'original-sources').mkdir(mode=0o700)
    def save(name, value=None, raw=None):
        data = encoded(value) if raw is None else raw
        path = output/name
        with path.open('xb') as stream: stream.write(data)
        path.chmod(0o600)
        return dict(file=name, bytes=len(data), sha256=sha(data))
    header = dict(schema='original-d13-source-rules-v1', sourceOnly=True, runtimeBound=False,
        sourceDecodedArchiveSHA256=ARCHIVE_PIN[1], sourceProdArchiveSHA256=PROD_PIN[1],
        sourceBattleSplitSHA256=BATTLE_PIN[1], sourceLockTreeSHA256=TREE_PIN[1], conditionsEvaluated=False)
    products = [save('serpent-original-levels-v1.json', dict(**header, **levels))]
    for row in records: products.append(save(f"serpent-lock-{row['sourceLock']}-source-v1.json", dict(**header, **row)))
    for name, raw in originals.items(): save('original-sources/'+name, raw=raw)
    summary = dict(**header, sourceCollectionSHA256=COLLECTION_PIN[1], sourceItemsSHA256=ITEMS_PIN[1],
        dedicatedD13Locks=list(DEDICATED_LOCKS), shuangouStyleLocks=list(STYLE_LOCKS), sharedConditionalLocks=list(SHARED_LOCKS),
        sourceTriggerSets=sum(len(r['sets']) for r in records),
        sourceTriggers=sum(len(s['triggers']) for r in records for s in r['sets']),
        records=[{key: r[key] for key in ('sourceLock','scope','sourceFile','sourceBytes','sourceSHA256',
            'sourceTypedValueSHA256','jsonRoundTripTypedValueSHA256')} for r in records], products=products,
        javascriptExecuted=False, decryptionPerformed=False, networkBytes=0, nativeOrAppExecuted=False,
        boundary='Original data and all ancestor gates retained; no gate evaluation, effective-level merge, damage conversion or App activation.')
    receipt = save('receipt-private.json', summary)
    print(json.dumps(dict(output=str(output), receipt=receipt, locks=len(records),
        sets=summary['sourceTriggerSets'], triggers=summary['sourceTriggers'], levels=products[0]), ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('prod','splits','output'): parser.add_argument('--'+name, type=Path, required=True)
    build(parser.parse_args())
