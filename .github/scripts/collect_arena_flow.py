#!/usr/bin/env python3
"""Preserve and validate real UI-flow evidence; never synthesize results or retime media."""
import collections
import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
from capture_arena_sample import APP_ID, simctl


def validate_scene(scene, hero):
    if scene.get('kind') != 'three-hero-ui-flow' or scene.get('playerHero') != hero:
        raise ValueError('Wrong flow/player identity')
    if scene.get('map') != 'twin_gates_sample_v1' or scene.get('qualitySample') is not True:
        raise ValueError('Wrong sample scene')
    if scene.get('finishedNaturally') is not True or scene.get('forcedResult') is not False:
        raise ValueError('Result was missing or injected')
    if not 0 < scene.get('simulationTime', 0) <= 151:
        raise ValueError('Invalid match duration')
    for team in (0, 1):
        roster = [f['hero'] for f in scene.get('fighters', []) if f['team'] == team]
        if sorted(roster) != [1, 2, 3]:
            raise ValueError('Each side must contain the three distinct heroes')
    events = scene.get('events', [])
    times = [e.get('simulationTime', -1) for e in events]
    if any(t < 0 or t > scene['simulationTime'] for t in times) or any(b < a for a, b in zip(times, times[1:])):
        raise ValueError('Invalid event clock')
    mine = collections.Counter(e.get('kind') for e in events if e.get('fighter') == 0)
    if mine['attack'] < 1 or mine['super'] < 1:
        raise ValueError('Player did not demonstrate both normal attack and super')
    return dict(mine)


def is_scene_attachment(name, hero):
    prefix = f"arena-flow-hero-{hero}"
    return name == prefix + ".json" or (name.startswith(prefix + "_") and name.endswith(".json"))


def validate_recording_session(session, decoded):
    if (not session.get('complete') or session.get('testExit') != 0
            or session.get('recorderExit') != 0
            or not session.get('recordingReadyBeforeTestCommand')):
        raise ValueError('Continuous recording/test session did not complete')
    duration = session.get('testSeconds')
    if not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
        raise ValueError('Missing valid actual XCTest duration')
    if decoded['presentationSpanSeconds'] + 5 < duration:
        raise ValueError('Recording does not cover the full UI test duration (5s startup tolerance)')


def main():
    device, destination = sys.argv[1], pathlib.Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)
    report = {'sourceCommit': os.environ.get('GITHUB_SHA'), 'device': device,
              'status': 'incomplete', 'heroes': {}, 'media': [],
              'visualAcceptance': 'pending-human-review', 'devicePerformance': 'unmeasured'}
    errors = []
    heroes = (int(os.environ['ARENA_FLOW_HERO']),) if os.environ.get('ARENA_FLOW_HERO') else (1, 2, 3)
    def save():
        report['errors'] = errors
        (destination / 'flow-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    save()
    try:
        # Xcode may install each UI test with a randomized bundle identifier.
        # The test attaches the exact app-written JSON before that sandbox disappears.
        manifest = json.loads((destination / 'manifest.json').read_text())
        for test in manifest:
            for attachment in test.get('attachments', []):
                name = attachment.get('suggestedHumanReadableName', '')
                for hero in heroes:
                    if is_scene_attachment(name, hero):
                        shutil.copyfile(destination / attachment['exportedFileName'],
                                        destination / f'arena-flow-hero-{hero}.json')
        data = destination
        for hero in heroes:
            source = data / f'arena-flow-hero-{hero}.json'
            try:
                scene = json.loads(source.read_text())
                report['heroes'][str(hero)] = {'events': validate_scene(scene, hero), 'status': 'scene-verified'}
            except (OSError, ValueError, KeyError) as error:
                errors.append(f'hero {hero}: {error}')
        save()  # Persist scene failures before any long media decoding.
        movies = ([destination / os.environ['ARENA_FLOW_VIDEO']] if os.environ.get('ARENA_FLOW_VIDEO') else
                  sorted(p for p in destination.rglob('*') if p.suffix.lower() in ('.mp4', '.mov')))
        if len(movies) < len(heroes):
            errors.append('Missing continuous recordings for the requested flows')
        for path in movies:
            result = subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('check_arena_video.py')), str(path)], check=False)
            report['media'].append({'path': str(path.relative_to(destination)), 'decodeExit': result.returncode})
            if not result.returncode and os.environ.get('ARENA_FLOW_VIDEO'):
                session = json.loads((destination / 'recording-session.json').read_text())
                decoded = json.loads(path.with_suffix('.decode.json').read_text())
                try:
                    validate_recording_session(session, decoded)
                except ValueError as error:
                    errors.append(str(error))
            if result.returncode:
                errors.append(f'Undecodable/invalid movie: {path.name}')
            save()
    except (OSError, subprocess.SubprocessError) as error:
        errors.append(str(error))
    report['errors'] = errors
    if not errors:
        report['status'] = 'scene-and-media-verified-visual-review-pending'
    (destination / 'flow-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
