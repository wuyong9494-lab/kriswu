#!/usr/bin/env python3
"""Fail-closed Liu TestFlight promotion. Never read the legacy release manifest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import asc_promote as asc
import fighter_private_model as model
import fighter_sf3_assets as assets
import fighter_sf3_distinct as distinct
import music_package as music

BRANCH = 'codex/plan-fighter-recovery-20261108'
FIGHTER_BRANCH = 'codex/fighter-lab-sf3-resources-20261108'
HOST_BRANCH = 'codex/fighter-lab-host-simulation-20261109'

CANDIDATE_BRANCH = 'codex/fighter-lab-compile-only-20261111'
CANDIDATE_SHA = '93de03a4fcc1a56189a808a3e8960f057b63a33a'
CANDIDATE_RUN = 43238606975
MUSIC_SHA = '36878beef5d9c8d86193b7eea04e5e381042691d'
ACCEPTANCE_STEPS = (
    'Stage verified private character',
    'Authenticate and stage independently encrypted music',
    'Select Xcode and generate existing app',
    'Build native and UI test bundles',
    'Verify music bytes inside compiled native app',
    'Prepare iPhone 17 Pro Max simulator',
    'Check interruption, input and SceneKit resource lifetime',
    'Play both characters and restore portrait app',
    'Export rendered evidence',
    'Seal bounded screenshots and failure summaries to private recipient',
    'Run actions/upload-artifact@v4',
)


def candidate(r):
    return r.get('source_branch') == CANDIDATE_BRANCH


def validate_candidate(r):
    require(r.get('source_sha') == CANDIDATE_SHA, 'Only the approved source is permitted')
    require(type(r.get('fighter_run_id')) is int and r['fighter_run_id'] == CANDIDATE_RUN,
            'Only the approved acceptance run is permitted')
    require(r.get('music_source_sha') == MUSIC_SHA, 'Pinned music source required')
    require(r.get('build_number') == '702' and r.get('version') == '1.2', 'Only approved 1.2 (702)')


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
    require(type(r.get('fighter_run_id')) is int and r['fighter_run_id'] > 0, 'Exact fighter CI run required')
    branch = r.get('source_branch', BRANCH)
    require(branch in (BRANCH, FIGHTER_BRANCH, HOST_BRANCH, CANDIDATE_BRANCH), 'Unapproved source branch')
    if candidate(r):
        validate_candidate(r)
    if branch == BRANCH:
        require(type(r.get('source_run_id')) is int and r['source_run_id'] > 0, 'Exact iOS CI run required')
    require(isinstance(r.get('notes'), str) and 0 < len(r['notes']) < 3800, 'Testing notes required')
    return r


def validate_run(r, run, jobs, workflow, names):
    require(run.get('head_sha') == r['source_sha'], 'CI tested different SHA')
    require(run.get('head_branch') == r.get('source_branch', BRANCH), 'Unexpected source branch')
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
    gates = [('fighter_run_id', 'fighter-lab.yml', ('core', 'envelope', 'device', 'native', 'character'))]
    if candidate(r):
        validate_candidate(r)
        gates = [('fighter_run_id', 'fighter-real-resource-acceptance.yml', ('real_resources',))]
    if r.get('source_branch', BRANCH) == BRANCH:
        gates.insert(0, ('source_run_id', 'ios.yml', ('build', 'core-tests-linux')))
    # These fighter branches intentionally exclude ios.yml. Their dedicated CI
    # must pass all five jobs on the exact immutable source SHA.
    for key, workflow, names in gates:
        run = asc.github('/actions/runs/' + str(r[key]))
        attempt = run['run_attempt']
        jobs = asc.github(f'/actions/runs/{r[key]}/attempts/{attempt}/jobs?per_page=100')
        require(jobs['total_count'] <= 100, 'Job pagination required; refusing incomplete gate')
        validate_run(r, run, jobs['jobs'], workflow, names)
        if candidate(r):
            require(type(attempt) is int and attempt > 0, 'Invalid attempt')
            require(run.get('id') == CANDIDATE_RUN, 'Wrong run identity')
            require(jobs['total_count'] == len(jobs['jobs']) == 1, 'Unexpected acceptance jobs')
            job = jobs['jobs'][0]
            require(job.get('status') == 'completed' and job.get('run_id') == CANDIDATE_RUN
                    and job.get('run_attempt') == attempt, 'Job attempt/status mismatch')
            for name in ACCEPTANCE_STEPS:
                steps = [s for s in job.get('steps', []) if s.get('name') == name]
                require(len(steps) == 1 and steps[0].get('status') == 'completed'
                        and steps[0].get('conclusion') == 'success', 'Required acceptance step failed: ' + name)
        latest = asc.github('/actions/runs/' + str(r[key]))
        if candidate(r):
            validate_run(r, latest, jobs['jobs'], workflow, names)
            require(latest.get('id') == CANDIDATE_RUN, 'Changed run identity')
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


def verify_resource(app, name, size, digest):
    matches = list(app.rglob(name))
    require(len(matches) == 1, 'Expected exactly one bundled resource: ' + name)
    resource = matches[0]
    directory = music.open_directory(resource.parent)
    try:
        data = music.read_regular(resource.name, size, directory)
    finally:
        os.close(directory)
    require(hashlib.sha256(data).hexdigest() == digest, 'Resource digest mismatch: ' + name)


def verify_candidate_resources(app, source):
    require(source is not None, 'Fixed source checkout required for resource verification')
    source = Path(source)
    # Re-authenticate encrypted source using the existing reviewed helpers, not
    # the mutable staged files or a caller-provided plaintext hash manifest.
    groups = [assets.verified_assets(source / '.github/private/sf3'),
              assets.verified_assets(source / '.github/private/sf3-original', assets.ORIGINAL_RIG),
              distinct.verified_assets(source / '.github/private/sf3-distinct')]
    seen = set()
    for group in groups:
        for name, data in group.items():
            require(name not in seen, 'Duplicate source resource identity')
            seen.add(name)
            verify_resource(app, name, len(data), hashlib.sha256(data).hexdigest())
    for name, size, digest in music.FILES:
        require(name not in seen, 'Resource collides with music identity')
        verify_resource(app, name, size, digest)


def archive(r, path, source=None):
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
    if candidate(r):
        validate_candidate(r)
        verify_candidate_resources(app, source)
    asc.save_report('promotion-archive.json', r, liu_sha256=model.SHA, app_and_extension_build_verified=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['preflight', 'stamp', 'archive', 'guard', 'finish'])
    p.add_argument('manifest')
    p.add_argument('--path', type=Path)
    p.add_argument('--source', type=Path)
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
        archive(r, a.path, a.source)
    elif a.command == 'guard':
        check_ci(r)
        guard(r)
    else:
        require(a.uploaded, 'Finish requires confirmed upload in this run; uncertain uploads need read-only reconciliation')
        asc.finish(r, True)


if __name__ == '__main__':
    main()
