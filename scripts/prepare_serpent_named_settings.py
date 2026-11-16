#!/usr/bin/env python3
"""Recover the original D13 / Shuangou animation fields from local plaintext.

This preserves source values, including absent defaults, enum handles and
Float32 values decoded into Python floats. It does not choose playable clips,
evaluate gameplay rules, download, decrypt, or activate an App asset.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
from pathlib import Path
import struct
from zipfile import ZipFile

from source_floorfall_audio import ANIMATION_FIELDS, Storage


ARCHIVE_PIN = (17325877, '02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a')
SPLIT = 'splits/split_animation_settings.bytes'
SPLIT_SHA = 'efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29'
SCHEMA_PIN = (11577, 'f8687443bcf2da87ff3c9f5d7c2059cb2dbe851a9a33c776655477e750b85111')
SCHEMA_CODE_SHA = 'ddd3a2c91d632bfc9270eeaba526999e9b98006643e74f06e5e3c597f0ff908a'
SOURCES = {
    'settings_sets_dynasty.bytes': (334225, '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701', 295),
    'settings_style_shuangou.bytes': (52412, '3c85fc3257fe4f0f92045818ff64a202194e62f1e1f9a4b6ccaa9ac45e64a20f', 31),
    'moves_settings.bytes': (86885, 'fcdecefdc0ef9cb5bc0a079c6511ccf2a9a352bb29aae8b016113236beac9a6b', 113),
    'settings_blocks.bytes': (84383, 'ecad88aefa412f8972d508ee63ab916190065f8a0c9dcc8bb8a2c7d8f716b091', 149),
    'settings_hits.bytes': (64690, 'd6daca4777b04dcab96375ce6aa899ec75a6b0aa5784b0beddd53f843aa9226a', 71),
    'settings_style_kicks.bytes': (109275, '15318c7a03085ea91c7010ab41a9407d820505666dea02880e1779f38bfa34cf', 71),
}
D13_INDICES = tuple(range(52, 71))


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode()


def pinned(raw, pin, name):
    require((len(raw), sha(raw)) == pin, f'Original {name} identity differs')
    return raw


def member(archive, name, maximum):
    matches = [item for item in archive.infolist() if item.filename == name]
    require(len(matches) == 1, f'Missing or duplicate original member: {name}')
    item = matches[0]
    require(0 < item.file_size <= maximum and not item.flag_bits & 1, 'Invalid original member size/flags')
    return archive.read(item)  # ZipFile verifies the member CRC.


def typed(value):
    """A type-sensitive inverse-projection identity, including float bits."""
    kind = type(value)
    if value is None: return ['null']
    if kind is bool: return ['bool', value]
    if kind is int: return ['int', value]
    if kind is float: return ['float64', struct.pack('>d', value).hex()]
    if kind is str: return ['string', value]
    if kind is list: return ['list', [typed(item) for item in value]]
    require(kind is dict and all(type(key) is str for key in value), 'Unsupported typed source value')
    return ['dict', [[key, typed(item)] for key, item in value.items()]]


class AnimationProjection:
    def __init__(self, schema_raw):
        schema = json.loads(pinned(schema_raw, SCHEMA_PIN, 'native schema receipt'))
        require(schema['nativeMethod'] == 16684 and schema['codeSHA256'] == SCHEMA_CODE_SHA,
                'Original animation constructor differs')
        rows = schema['fields']
        require(len(rows) == 125 and len({row['name'] for row in rows}) == 125,
                'Original native field inventory differs')
        def children(prefix):
            names = [row['name'] if not prefix else row['name'][len(prefix)+1:]
                     for row in rows if not prefix or row['name'].startswith(prefix+'.')]
            return tuple(name.removesuffix('[]') for name in names if '.' not in name)
        self.fields = {key: children(prefix) for key, prefix in (
            ('animation', ''), ('interval', 'Intervals[]'), ('damage', 'Intervals[].Damage'),
            ('sound', 'Sounds[]'), ('gender', 'Sounds[].Gender'), ('floor', 'Sounds[].Floor'))}
        require(self.fields['animation'] == ANIMATION_FIELDS and
                tuple(len(self.fields[key]) for key in ('animation','interval','damage','sound','gender','floor')) ==
                (29,28,5,4,3,4), 'Animation field layout differs')

    def mapping(self, value, key):
        require(type(value) is list and len(value) == len(self.fields[key]), 'Source field count differs')
        return dict(zip(self.fields[key], copy.deepcopy(value)))

    def named(self, raw):
        value = self.mapping(raw, 'animation')
        if value['Intervals'] is not None:
            value['Intervals'] = [self.mapping(row, 'interval') for row in value['Intervals']]
            for row in value['Intervals']:
                if row['Damage'] is not None: row['Damage'] = self.mapping(row['Damage'], 'damage')
        if value['Sounds'] is not None:
            value['Sounds'] = [self.mapping(row, 'sound') for row in value['Sounds']]
            for row in value['Sounds']:
                for key in ('Gender', 'Floor'):
                    if row[key] is not None: row[key] = self.mapping(row[key], key.lower())
        return value

    def unnamed(self, source):
        value = copy.deepcopy(source)
        if value['Intervals'] is not None:
            for row in value['Intervals']:
                if row['Damage'] is not None: row['Damage'] = [row['Damage'][key] for key in self.fields['damage']]
            value['Intervals'] = [[row[key] for key in self.fields['interval']] for row in value['Intervals']]
        if value['Sounds'] is not None:
            for row in value['Sounds']:
                for key in ('Gender','Floor'):
                    if row[key] is not None: row[key] = [row[key][child] for child in self.fields[key.lower()]]
            value['Sounds'] = [[row[key] for key in self.fields['sound']] for row in value['Sounds']]
        return [value[key] for key in self.fields['animation']]


def recover(archive_raw, schema_raw):
    projection = AnimationProjection(schema_raw)
    pinned(archive_raw, ARCHIVE_PIN, 'decoded archive')
    with ZipFile(io.BytesIO(archive_raw)) as outer:
        split = member(outer, SPLIT, 17000000)
    require(sha(split) == SPLIT_SHA, 'Original animation split differs')
    records, audits, sources, source_files = [], [], [], {}
    with ZipFile(io.BytesIO(split)) as archive:
        for name, (size, digest, count) in SOURCES.items():
            raw = pinned(member(archive, name, 1000000), (size, digest), name)
            reader = Storage(raw)
            require(reader.pos == len(raw), 'Original typed source has unconsumed bytes')
            values = reader.value(reader.root)
            require(type(values) is list and len(values) == count, 'Original record count differs')
            selected = []
            for index, row in enumerate(values):
                require(type(row) is list and len(row) == 29, 'Original animation row differs')
                if name == 'settings_sets_dynasty.bytes':
                    is_d13 = type(row[0]) is str and row[0].startswith('D13_')
                    require(is_d13 == (index in D13_INDICES), 'Original D13 selection differs')
                    if not is_d13: continue
                named = json.loads(encoded(projection.named(row)))
                before, after = typed(row), typed(projection.unnamed(named))
                require(before == after, 'Lossy animation naming or JSON round trip')
                identity = dict(sourceEntry=name, sourceSHA256=digest, sourceRecordIndex=index)
                records.append(dict(**identity, configuration=named))
                audits.append(dict(**identity, sourceAlias=row[0], allFieldsPreserved=True,
                    sourceTypedValueSHA256=sha(encoded(before)), roundTripTypedValueSHA256=sha(encoded(after)),
                    configurationSHA256=sha(encoded(named))))
                selected.append(index)
            sources.append(dict(entry=name, bytes=size, sha256=digest, sourceRecords=count,
                selectedRecordIndices=selected, allBytesConsumed=True))
            source_files[name] = raw
    require(len(records) == 454, 'Original combined selection differs')
    header = dict(schema='original-d13-named-animation-source-v1', sourceOnly=True, runtimeBound=False,
        suppliedClientVersion='1.46.1', packagedConfigurationVersion='1.46.0.16.16733-prod',
        sourceDecodedArchiveSHA256=ARCHIVE_PIN[1], sourceAnimationSplitSHA256=SPLIT_SHA,
        nativeSchemaMethod=16684, nativeSchemaReceiptSHA256=SCHEMA_PIN[1], nativeSchemaCodeSHA256=SCHEMA_CODE_SHA,
        originalValuesAndTypesPreserved=True, defaultsApplied=False)
    d13 = [row for row in records if row['sourceEntry'] == 'settings_sets_dynasty.bytes']
    return dict(**header, records=records), dict(**header, records=d13), audits, sources, source_files


def build(args):
    full, d13, audits, sources, raw_sources = recover(args.splits.read_bytes(), args.schema.read_bytes())
    output = args.output.resolve()
    require(not output.exists() and Path(__file__).resolve().parents[1] not in output.parents,
            'Use a new private output outside the public repository')
    output.mkdir(parents=True, mode=0o700)
    (output/'original-sources').mkdir(mode=0o700)
    def save(name, raw):
        path = output/name
        with path.open('xb') as stream: stream.write(raw)
        path.chmod(0o600)
        return dict(file=name, bytes=len(raw), sha256=sha(raw))
    products = [save(name, encoded(value)) for name, value in (
        ('serpent-animation-named-v1.json', d13),
        ('serpent-shuangou-animation-named-v1.json', full),
        ('record-round-trip-audit-private.json', audits))]
    for name, raw in raw_sources.items(): save('original-sources/'+name, raw)
    receipt = dict(schema='original-d13-named-animation-receipt-v1', sourceOnly=True, runtimeBound=False,
        sourceDecodedArchiveSHA256=ARCHIVE_PIN[1], sourceAnimationSplitSHA256=SPLIT_SHA,
        nativeSchemaReceiptSHA256=SCHEMA_PIN[1], sources=sources, products=products,
        d13Records=19, shuangouRecords=31, commonRecords=404, exactRoundTripVerifiedRecords=len(audits),
        defaultsApplied=False, networkBytes=0, decryptionPerformed=False, nativeOrAppExecuted=False,
        boundary='Original named fields only; no clip selection, collision conversion or gameplay activation.')
    proof = save('receipt-private.json', encoded(receipt))
    print(json.dumps(dict(output=str(output), receipt=proof, products=products), ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--splits', type=Path, required=True)
    parser.add_argument('--schema', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    build(parser.parse_args())
