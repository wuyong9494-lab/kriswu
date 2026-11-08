#!/usr/bin/env python3
"""Fail-closed Liu TestFlight promotion. Never read the legacy release manifest."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import asc_promote as asc
import fighter_private_model as model

BRANCH = 'codex/plan-fighter-recovery-20261108'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_request(path):
    require(Path(path).name == 'fighter-testflight.json', 'Dedicated fighter manifest required')
    r = json.loads(Path(path).read_text())
    require(r.get('channel') == 'testflight-internal', 'Internal TestFlight only')
    require(re.fullmatch('[0-9a-f]{40}', r.get('source_sha', '')), 'Full source SHA required')
    require(re.fullmatch('[1-9][0-9]*', r.get('build_number', '')), 'Explicit build number required')
    require(r.get('bundle_id') == 'com.kriswu.shiftreminder', 'Unexpected app')
    require(re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', r.get('version', '')), 'Version required')
    require(r.get('liu_sha256') == model.SHA, 'Actual Liu identity required')
    require(all(type(r.get(k)) is int and r[k] > 0 for k in ('source_run_id', 'fighter_run_id')), 'Both exact CI run IDs required')
    require(isinstance(r.get('notes'), str) and 0 < len(r['notes']) < 3800, 'Testing notes required')
    return r


def validate_run(r, run, jobs, workflow, names):
    require(run.get('head_sha') == r['source_sha'], 'CI tested different SHA')
    require(run.get('head_branch') == BRANCH, 'Unexpected source branch')
    require(run.get('event') in ('push', 'workflow_dispatch'), 'Untrusted CI event')
    require(run.get('path') == '.github/workflows/' + workflow, 'Unexpected workflow')
    require(run.get('status') == 'completed' and run.get('conclusion') == 'success', 'CI not successful')
    if workflow == 'ios.yml':
        require(str(run.get('run_number')) == r['build_number'], 'Build must match iOS run number')
    for name in names:
        matches = [j for j in jobs if j.get('name') == name]
        require(len(matches) == 1 and matches[0].get('conclusion') == 'success', 'Required job missing, skipped or failed: ' + name)
        require(matches[0].get('head_sha') == r['source_sha'], 'Job SHA mismatch')


def check_ci(r):
    for key, workflow, names in [
        ('source_run_id', 'ios.yml', ('build', 'core-tests-linux')),
        ('fighter_run_id', 'fighter-lab.yml', ('core', 'envelope', 'device', 'native', 'character')),
    ]:
        run = asc.github('/actions/runs/' + str(r[key]))
        attempt = run['run_attempt']
        jobs = asc.github(f'/actions/runs/{r[key]}/attempts/{attempt}/jobs?per_page=100')
        require(jobs['total_count'] <= 100, 'Job pagination required; refusing incomplete gate')
        validate_run(r, run, jobs['jobs'], workflow, names)
        latest = asc.github('/actions/runs/' + str(r[key]))
        require(latest.get('run_attempt') == attempt and latest.get('status') == 'completed'
                and latest.get('conclusion') == 'success' and latest.get('head_sha') == r['source_sha'],
                'CI changed during gate; recheck before release')


def guard(r):
    # Existing number is a collision, never proof this source was uploaded.
    require(asc.find_build(r) is None, 'Build number already exists; do not upload or claim source identity')
    # Retained across failed/cancelled attempts. Missing Apple visibility is not
    # permission to repeat an uncertain upload. An artifact API error aborts.
    attempts = asc.github('/actions/artifacts?name=fighter-upload-attempt-' + r['build_number'] + '&per_page=100')
    require(attempts.get('total_count') == 0 and attempts.get('artifacts') == [],
            'Prior upload intent exists; reconcile read-only, do not retry')


def archive(r, path):
    app = path / 'Products/Applications/ShiftReminder.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == r['bundle_id'], 'Wrong bundle')
    require(info.get('CFBundleShortVersionString') == r['version'], 'Wrong version')
    require(info.get('ArenaCommitSHA') == r['source_sha'], 'Wrong source identity')
    extensions = list(app.glob('PlugIns/*.appex/Info.plist'))
    require(len(extensions) == 1, 'Expected exactly one widget extension')
    widget = plistlib.loads(extensions[0].read_bytes())
    require(widget.get('CFBundleIdentifier') == 'com.kriswu.shiftreminder.widget', 'Wrong widget bundle')
    require(widget.get('CFBundleShortVersionString') == r['version'], 'Wrong widget marketing version')
    for file in [app / 'Info.plist', *extensions]:
        require(str(plistlib.loads(file.read_bytes()).get('CFBundleVersion')) == r['build_number'], 'Wrong build number')
    model.verify_app(app)
    asc.save_report('promotion-archive.json', r, liu_sha256=model.SHA, app_and_extension_build_verified=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['preflight', 'stamp', 'archive', 'guard', 'finish'])
    p.add_argument('manifest')
    p.add_argument('--path', type=Path)
    p.add_argument('--uploaded', action='store_true')
    a = p.parse_args()
    r = load_request(a.manifest)
    if a.command == 'preflight':
        check_ci(r)
        guard(r)
        for key in ('source_sha', 'build_number'):
            asc.output(key, r[key])
        asc.output('upload_required', 'true')
        asc.save_report('promotion-preflight.json', r, fighter_run_id=r['fighter_run_id'], liu_sha256=model.SHA)
    elif a.command == 'stamp':
        asc.stamp(r, a.path)
    elif a.command == 'archive':
        archive(r, a.path)
    elif a.command == 'guard':
        check_ci(r)
        guard(r)
    else:
        require(a.uploaded, 'Finish requires confirmed upload in this run; uncertain uploads need read-only reconciliation')
        asc.finish(r, True)


if __name__ == '__main__':
    main()
