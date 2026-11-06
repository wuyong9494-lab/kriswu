#!/usr/bin/env python3
"""Export source localization plus its locale-specific patch, privately."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import zipfile


def table(data, locale):
    rows = csv.reader(io.StringIO(data.decode('utf-8-sig')))
    header = next(rows)
    assert header[0] == 'TID' and header.count(locale) == 1, 'Missing or ambiguous locale'
    column = header.index(locale)
    types = next(rows)
    assert len(types) == len(header) and all(t == 'string' for t in types), 'Unexpected localization schema'
    strings = {}
    for row in rows:
        if not row:
            continue
        assert len(row) == len(header), 'Truncated localization row'
        key = row[0]
        assert key and len(key.encode()) <= 240 and all(32 <= ord(c) < 127 for c in key), 'Invalid localization key'
        assert key not in strings, 'Duplicate localization key'
        strings[key] = row[column]
    return strings


def export(ipa, locale, output):
    assert locale in ['CN', 'CNT', 'EN'], 'Unreviewed locale'
    member = 'texts' if locale == 'EN' else locale.lower()
    paths = [f'Payload/NB.app/res/localization/{member}.csv', 'Payload/NB.app/res/localization/texts_patch.csv']
    with zipfile.ZipFile(ipa) as archive:
        payloads = [archive.read(path) for path in paths]
    strings = table(payloads[0], locale)
    # An empty patch cell means no locale override, not an empty UI label.
    overrides = {key:value for key,value in table(payloads[1], locale).items() if value}
    strings.update(overrides)
    digest = hashlib.sha256()
    with ipa.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    result = {'schemaVersion':1, 'locale':locale, 'sourceIPASHA256':digest.hexdigest(),
              'sources':[{'member':path,'sha256':hashlib.sha256(data).hexdigest()} for path,data in zip(paths,payloads)],
              'strings':strings}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    return {'strings':len(strings),'patchOverrides':len(overrides)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa',type=Path,required=True)
    parser.add_argument('--locale',default='CN')
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    assert not args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]), 'Private output must be outside checkout'
    print(json.dumps(export(args.ipa,args.locale,args.output)))
