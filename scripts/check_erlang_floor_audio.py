#!/usr/bin/env python3
"""Two targeted read-only checks of the new Floor binding; no decoding."""
import argparse
import json
from pathlib import Path

from build_erlang_source_assets import checked, sha
from bind_erlang_source_audio import FLOOR_INPUT_SHA, FLOOR_SOURCE_SHA
from sun_triad_assets import require


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('floor-input', 'old-runtime', 'new-runtime'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    floor = json.loads(checked(args.floor_input, FLOOR_INPUT_SHA, 512_000))
    expected = [
        ('walkForward', 10, 20), ('walkBackward', 10, 20), ('jump', 31, 62), ('getUp', 20, 40),
        ('victory', 28, 56), ('weapon1', 30, 60), ('weapon2', 30, 60), ('heavy', 32, 64),
        ('weaponForward', 12, 24), ('weaponUp', 15, 30), ('weaponDown', 26, 52), ('weaponBack', 26, 52),
        ('weaponForward2', 12, 24), ('weaponForward2', 28, 56),
        ('weaponForward3', 12, 24), ('weaponForward3', 28, 56), ('weaponForward3', 67, 134),
        ('kickForward', 27, 54), ('kickJump', 24, 48), ('kickJumpForward', 26, 52),
        ('erlangAvatarStance', 23, 46)]
    require([(e['role'], e['rawFrame'], e['sourceTick']) for e in floor['events']] == expected,
            'Actual source Floor marker positions differ')
    require(floor['floorSourceSHA256'] == FLOOR_SOURCE_SHA and floor['floorSource']['floor'] == 'Stone'
            and floor['floorSource']['sourceFloorValue'] == 2, 'Palace floor lacks its source enum binding')
    for event in floor['events']:
        choices = event['choices']
        if event['role'] in ('walkForward', 'walkBackward', 'weapon1', 'weapon2', 'heavy', 'weaponForward',
                             'weaponDown', 'weaponBack', 'weaponForward2', 'weaponForward3', 'erlangAvatarStance'):
            require(len(choices) == 3 and choices[1] == choices[2] and choices[0] != choices[1],
                    'Original repeated V2 alternative weighting was lost')
    require(sum(f['reusedExistingPCM'] for f in floor['files']) == 5 and len(floor['files']) == 7,
            'Original five reused/two new PCM boundary differs')
    print('PASS all 21 exact non-subtracted Floor frames, Stone enum and original duplicate alternatives')

    old = json.loads(args.old_runtime.read_bytes()); new = json.loads(args.new_runtime.read_bytes())
    require(old['schemaVersion'] == 3 and new['schemaVersion'] == 4, 'Expected the actual source extension')
    require(new['markers'][:98] == old['markers'] and len(new['markers']) == 119,
            'An existing actor/model marker changed while adding Floor')
    require(new['files'][:75] == old['files'] and len(new['files']) == 82
            and new['triggerSounds'] == old['triggerSounds'] and new['deferredTriggers'] == old['deferredTriggers'],
            'Existing original PCM or source trigger changed')
    require({c['file'] for e in floor['events'] for c in e['choices']} ==
            {f['name'] for f in new['files'][75:]}, 'New Floor PCM closure differs')
    for file in old['files']:
        raw = (args.new_runtime.parent/file['name']).read_bytes()
        require(len(raw) == file['bytes'] and sha(raw) == file['sha256'], 'Prior PCM bytes changed')
    print('PASS prior 75 PCM bytes, 98 marker records and source start/stop trigger are unchanged')
    print('2 new Floor source checks passed; no decoding, playback or native execution')


if __name__ == '__main__':
    main()
