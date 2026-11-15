#!/usr/bin/env python3
"""Check the newly bound model markers without replaying or decoding audio."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

from bind_erlang_source_audio import INPUT_SHA, bind_marker


def read(path, pin):
    raw = path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == pin
    return json.loads(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-audio', 'bound-audio', 'profile'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--bound-sha256', required=True)
    args = parser.parse_args()
    source = read(args.source_audio, INPUT_SHA)
    bound = read(args.bound_audio, args.bound_sha256)
    profile = read(args.profile, bound['profileSHA256'])
    assert len(bound['files']) == 28 and len(bound['markers']) == 29 and not bound['pendingModels']
    assert sum(m['modelRole'] is None for m in bound['markers']) == 18
    model = [m for m in bound['markers'] if m['modelRole'] is not None]
    assert len(model) == 11
    for slot in range(1, 7):
        rows = [m for m in model if m['animationAlias'] == 'D15_Hovering_Sword_Model_Birth_' + str(slot)]
        assert len(rows) == 1
        marker = rows[0]
        assert marker['role'] == marker['modelRole'] == 'erlangSummon_swordBirth' + str(slot)
        assert marker['sourceFrame'] == 1 and marker['sourceFirstIndex'] == 0
        assert marker['sourceTick'] == 2 and marker['duration'] == 100
        assert marker['clip'] == 'd15_hovering_sword'
        track = next(t for t in profile['summonTracks'] if t['role'] == marker['role'])
        assert track['sourceSHA256'] == marker['sourceMotionSHA256']
    assert {d['sourceName']: d['reason'] for d in bound['deferredTriggers']} == {
        'd15_meditation': 'awaiting-exact-source-trigger',
        'd15_swords_explosion': 'no-active-reference-in-reviewed-source-scope'}
    assert bound['runtimePlaybackObserved'] is False
    print('PASS actual 29-marker manifest, six separate birth clocks and unplayed source scope')

    event = next(e for e in source['events'] if e['animationAlias'] == 'D15_Hovering_Sword_Model_Birth_1')
    wrong = {event['animationAlias']: dict(role='erlangSummon_sword',
        sourceMotionSHA256='0705dac47e95dee7d66f39c8a2ede4e4774762aa241f79c08e64129119f36632', sourceFirstIndex=0)}
    try:
        bind_marker(copy.deepcopy(event), profile, wrong)
    except ValueError:
        pass
    else:
        raise AssertionError('Birth was accepted on Attack despite matching raw motion and duration')
    print('PASS a birth cue cannot borrow the same-raw-motion Attack model clock')
    print('2 affected source binding checks passed; no media decode or playback')


if __name__ == '__main__':
    main()
