import copy
import json
import tempfile
import plistlib
from pathlib import Path
import unittest
from unittest.mock import patch
import fighter_promote as f


class GateTests(unittest.TestCase):
    def setUp(self):
        self.r = {'source_sha': 'a'*40, 'build_number': '501'}
        self.run = dict(head_sha='a'*40, head_branch=f.BRANCH, event='push', path='.github/workflows/fighter-lab.yml', status='completed', conclusion='success')
        self.jobs = [dict(name=n, conclusion='success', head_sha='a'*40) for n in ['core', 'envelope', 'device', 'native', 'character']]

    def validate(self):
        f.validate_run(self.r, self.run, self.jobs, 'fighter-lab.yml', ('core', 'envelope', 'device', 'native', 'character'))

    def test_all_pass(self):
        self.validate()

    def test_bad_run_fields(self):
        for field, value in [('head_sha', 'b'*40), ('head_branch', 'main'), ('event', 'pull_request'), ('path', '.github/workflows/ios.yml'), ('status', 'in_progress'), ('conclusion', 'failure')]:
            with self.subTest(field=field):
                old = self.run[field]
                self.run[field] = value
                with self.assertRaises(ValueError): self.validate()
                self.run[field] = old

    def test_character_cannot_skip(self):
        self.jobs[-1]['conclusion'] = 'skipped'
        with self.assertRaises(ValueError): self.validate()

    def test_character_cannot_be_missing(self):
        self.jobs.pop()
        with self.assertRaises(ValueError): self.validate()

    def test_duplicate_job_rejected(self):
        self.jobs.append(copy.deepcopy(self.jobs[-1]))
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_job_sha_rejected(self):
        self.jobs[-1]['head_sha'] = 'b'*40
        with self.assertRaises(ValueError): self.validate()

    def test_ios_number_matches(self):
        self.run.update(path='.github/workflows/ios.yml', run_number=502)
        with self.assertRaises(ValueError):
            f.validate_run(self.r, self.run, [], 'ios.yml', ())
        self.run['run_number'] = 501
        f.validate_run(self.r, self.run, [], 'ios.yml', ())

    def test_existing_number_is_not_success(self):
        with patch.object(f.asc, 'find_build', return_value={'id': 'existing'}):
            with self.assertRaises(ValueError): f.guard(self.r)

    def test_new_number_is_allowed(self):
        with patch.object(f.asc, 'find_build', return_value=None), patch.object(f.asc, 'github', return_value={'total_count': 0, 'artifacts': []}): f.guard(self.r)

    def test_prior_upload_intent_blocks_retry(self):
        with patch.object(f.asc, 'find_build', return_value=None), patch.object(f.asc, 'github', return_value={'total_count': 1, 'artifacts': [{'id': 12}]}):
            with self.assertRaises(ValueError): f.guard(self.r)

    def test_unknown_intent_response_blocks(self):
        with patch.object(f.asc, 'find_build', return_value=None), patch.object(f.asc, 'github', return_value={}):
            with self.assertRaises(ValueError): f.guard(self.r)

    def test_legacy_manifest_refused(self):
        with self.assertRaises(ValueError): f.load_request('.github/releases/testflight.json')

    def test_missing_real_model_refused(self):
        with tempfile.TemporaryDirectory() as d:
            app = Path(d) / 'ShiftReminder.app'
            app.mkdir()
            with self.assertRaises(ValueError): f.model.verify_app(app)

    def test_current_attempt_and_rerun_race(self):
        r = dict(self.r, source_run_id=1, fighter_run_id=2)
        ios = dict(self.run, path='.github/workflows/ios.yml', run_number=501, run_attempt=2)
        fighter = dict(self.run, run_attempt=3)
        ios_jobs = dict(total_count=3, jobs=[dict(name=n, head_sha='a'*40, conclusion='success') for n in ('build', 'core-tests-linux')] + [dict(name='arena-look', head_sha='a'*40, conclusion='skipped')])
        replies = [ios, ios_jobs, ios, fighter, dict(total_count=5, jobs=self.jobs), fighter]
        with patch.object(f.asc, 'github', side_effect=replies) as api:
            f.check_ci(r)
            self.assertIn('/attempts/2/jobs', api.call_args_list[1].args[0])
            self.assertIn('/attempts/3/jobs', api.call_args_list[4].args[0])
        with patch.object(f.asc, 'github', side_effect=[ios, ios_jobs, dict(ios, run_attempt=3)]):
            with self.assertRaises(ValueError): f.check_ci(r)

    def test_fighter_branches_require_exact_successful_five_job_run(self):
        for branch in (f.FIGHTER_BRANCH, f.HOST_BRANCH):
            with self.subTest(branch=branch):
                r = dict(self.r, source_branch=branch, fighter_run_id=42)
                run = dict(self.run, head_branch=branch, run_attempt=1)
                jobs = dict(total_count=5, jobs=self.jobs)
                with patch.object(f.asc, 'github', side_effect=[run, jobs, run]) as api:
                    f.check_ci(r)
                    self.assertEqual([c.args[0] for c in api.call_args_list], [
                        '/actions/runs/42', '/actions/runs/42/attempts/1/jobs?per_page=100',
                        '/actions/runs/42'])
                for name in ('core', 'envelope', 'device', 'native', 'character'):
                    for bad in ('missing', 'skipped', 'failure', 'wrong_sha'):
                        with self.subTest(job=name, state=bad):
                            changed = copy.deepcopy(self.jobs)
                            if bad == 'missing':
                                changed = [j for j in changed if j['name'] != name]
                            else:
                                job = next(j for j in changed if j['name'] == name)
                                if bad == 'wrong_sha':
                                    job['head_sha'] = 'b'*40
                                else:
                                    job['conclusion'] = bad
                            with patch.object(f.asc, 'github', side_effect=[run, dict(total_count=len(changed), jobs=changed), run]):
                                with self.assertRaises(ValueError):
                                    f.check_ci(r)
                with patch.object(f.asc, 'github', side_effect=[dict(run, head_branch=f.BRANCH), jobs, run]):
                    with self.assertRaises(ValueError):
                        f.check_ci(r)
                with patch.object(f.asc, 'github', side_effect=[dict(run, head_sha='b'*40), jobs, run]):
                    with self.assertRaises(ValueError):
                        f.check_ci(r)

    def load_manifest(self, **overrides):
        request = dict(self.r, channel='testflight-internal', bundle_id='com.kriswu.shiftreminder',
                       version='1.2', liu_sha256=f.model.SHA, fighter_run_id=42,
                       notes='Internal testing only', **overrides)
        with tempfile.TemporaryDirectory() as d:
            manifest = Path(d) / 'fighter-testflight.json'
            manifest.write_text(json.dumps(request))
            return f.load_request(manifest)

    def test_only_explicit_fighter_source_branches_are_allowed(self):
        for branch in (f.FIGHTER_BRANCH, f.HOST_BRANCH):
            with self.subTest(branch=branch):
                self.assertEqual(self.load_manifest(source_branch=branch)['source_branch'], branch)
        for branch in ('main', 'codex/fighter-lab-*', f.HOST_BRANCH + '-other',
                       'codex/fighter-lab-host-simulation-20261110', 'feature/shadow-skills'):
            with self.subTest(branch=branch), self.assertRaises(ValueError):
                self.load_manifest(source_branch=branch)

    def test_recovery_branch_still_requires_ios_run(self):
        for fields in ({}, {'source_branch': f.BRANCH}):
            with self.subTest(fields=fields):
                with self.assertRaises(ValueError):
                    self.load_manifest(**fields)
                self.assertEqual(self.load_manifest(source_run_id=7, **fields)['source_run_id'], 7)

    def test_incomplete_jobs_rejected(self):
        r = dict(self.r, source_run_id=1, fighter_run_id=2)
        with patch.object(f.asc, 'github', side_effect=[dict(self.run, run_attempt=1), dict(total_count=101, jobs=[])]):
            with self.assertRaises(ValueError): f.check_ci(r)

    def test_widget_identity(self):
        r = dict(self.r, bundle_id='com.kriswu.shiftreminder', version='1.2', source_run_id=1)
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            app = root / 'Products/Applications/ShiftReminder.app'
            widget = app / 'PlugIns/Widget.appex/Info.plist'
            widget.parent.mkdir(parents=True)
            info = dict(CFBundleIdentifier=r['bundle_id'], CFBundleShortVersionString='1.2', CFBundleVersion='501', ArenaCommitSHA='a'*40)
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            good = dict(CFBundleIdentifier=r['bundle_id']+'.widget', CFBundleShortVersionString='1.2', CFBundleVersion='501')
            for field, value in [('CFBundleIdentifier', 'wrong'), ('CFBundleShortVersionString', '9.0'), ('CFBundleVersion', '99')]:
                widget.write_bytes(plistlib.dumps(dict(good, **{field:value})))
                with self.assertRaises(ValueError): f.archive(r, root)
            widget.write_bytes(plistlib.dumps(good))
            with patch.object(f.model, 'verify_app') as verify, patch.object(f.asc, 'save_report'):
                f.archive(r, root)
                verify.assert_called_once_with(app)


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.r = dict(channel='testflight-internal', source_branch=f.CANDIDATE_BRANCH,
                      source_sha=f.CANDIDATE_SHA, fighter_run_id=f.CANDIDATE_RUN,
                      music_source_sha=f.MUSIC_SHA, build_number='702', version='1.2',
                      bundle_id='com.kriswu.shiftreminder', liu_sha256=f.model.SHA, notes='Internal only')
        self.run = dict(id=f.CANDIDATE_RUN, head_sha=f.CANDIDATE_SHA, head_branch=f.CANDIDATE_BRANCH,
                        event='push', path='.github/workflows/fighter-real-resource-acceptance.yml',
                        run_attempt=1, status='completed', conclusion='success')
        self.job = dict(name='real_resources', head_sha=f.CANDIDATE_SHA, run_id=f.CANDIDATE_RUN,
                        run_attempt=1, status='completed', conclusion='success',
                        steps=[dict(name=n, status='completed', conclusion='success') for n in f.ACCEPTANCE_STEPS])

    def check(self, run=None, job=None, latest=None, count=1):
        run = self.run if run is None else run
        job = self.job if job is None else job
        latest = run if latest is None else latest
        with patch.object(f.asc, 'github', side_effect=[run, dict(total_count=count, jobs=[job]), latest]):
            f.check_ci(self.r)

    def test_exact_candidate_manifest(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'fighter-testflight.json'
            p.write_text(json.dumps(self.r))
            self.assertEqual(f.load_request(p), self.r)
            for key, value in [('source_sha', 'a'*40), ('fighter_run_id', f.CANDIDATE_RUN+1),
                               ('music_source_sha', 'b'*40), ('build_number', '703'), ('version', '1.3')]:
                with self.subTest(key=key):
                    p.write_text(json.dumps(dict(self.r, **{key:value})))
                    with self.assertRaises(ValueError): f.load_request(p)

    def test_complete_acceptance(self):
        self.check()

    def test_every_required_step_must_complete_successfully_once(self):
        for name in f.ACCEPTANCE_STEPS:
            for fault in ('missing', 'duplicate', 'failure', 'skipped', 'in_progress'):
                with self.subTest(name=name, fault=fault):
                    job = copy.deepcopy(self.job)
                    step = next(s for s in job['steps'] if s['name'] == name)
                    if fault == 'missing': job['steps'].remove(step)
                    elif fault == 'duplicate': job['steps'].append(copy.deepcopy(step))
                    elif fault == 'in_progress': step['status'] = fault
                    else: step['conclusion'] = fault
                    with self.assertRaises(ValueError): self.check(job=job)

    def test_job_identity_attempt_and_pagination(self):
        for key, value in [('run_id', 1), ('run_attempt', 2), ('head_sha', 'a'*40),
                           ('status', 'queued'), ('name', 'native'), ('conclusion', 'skipped')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.check(job=dict(self.job, **{key:value}))
        with self.assertRaises(ValueError): self.check(count=101)
        with self.assertRaises(ValueError): self.check(count=2)

    def test_gate_recheck_rejects_races_and_wrong_source(self):
        for key, value in [('id', 1), ('run_attempt', 2), ('head_sha', 'a'*40),
                           ('head_branch', 'main'), ('status', 'in_progress'),
                           ('conclusion', 'failure'), ('event', 'pull_request'),
                           ('path', '.github/workflows/fighter-lab.yml')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.check(latest=dict(self.run, **{key:value}))

    def test_resource_exact_bytes_duplicate_missing_and_symlink(self):
        import hashlib
        with tempfile.TemporaryDirectory() as d:
            app = Path(d) / 'ShiftReminder.app'; app.mkdir()
            p = app / 'test.wav'; p.write_bytes(b'abc')
            sha = hashlib.sha256(b'abc').hexdigest()
            f.verify_resource(app, p.name, 3, sha)
            with self.assertRaises(ValueError): f.verify_resource(app, p.name, 3, '0'*64)
            with self.assertRaises(ValueError): f.verify_resource(app, p.name, 4, sha)
            (app / 'nested').mkdir(); (app / 'nested/test.wav').write_bytes(b'abc')
            with self.assertRaises(ValueError): f.verify_resource(app, p.name, 3, sha)
            (app / 'nested/test.wav').unlink(); p.unlink()
            with self.assertRaises(ValueError): f.verify_resource(app, p.name, 3, sha)
            (app / 'real').write_bytes(b'abc'); p.symlink_to('real')
            with self.assertRaises(OSError): f.verify_resource(app, p.name, 3, sha)

    def test_candidate_archive_requires_all_resource_validation_before_report(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            app = root / 'Products/Applications/ShiftReminder.app'
            widget = app / 'PlugIns/Widget.appex/Info.plist'; widget.parent.mkdir(parents=True)
            info = dict(CFBundleIdentifier=self.r['bundle_id'], CFBundleShortVersionString='1.2',
                        CFBundleVersion='702', ArenaCommitSHA=f.CANDIDATE_SHA)
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            widget.write_bytes(plistlib.dumps(dict(info, CFBundleIdentifier=self.r['bundle_id']+'.widget')))
            with patch.object(f.model, 'verify_app') as model, \
                 patch.object(f, 'verify_candidate_resources') as resources, \
                 patch.object(f.asc, 'save_report') as report:
                f.archive(self.r, root, Path('source'))
                model.assert_called_once_with(app)
                resources.assert_called_once_with(app, Path('source'))
                report.assert_called_once()
                report.reset_mock(); resources.side_effect = ValueError('corrupt music')
                with self.assertRaises(ValueError): f.archive(self.r, root, Path('source'))
                report.assert_not_called()

    def test_all_source_groups_and_three_music_files_are_checked(self):
        with patch.object(f.assets, 'verified_assets', side_effect=[{'sun':b'a'}, {'rig':b'b'}]) as a, \
             patch.object(f.distinct, 'verified_assets', return_value={'body':b'c'}) as b, \
             patch.object(f, 'verify_resource') as verify:
            f.verify_candidate_resources(Path('app'), Path('source'))
            self.assertEqual(a.call_count, 2); b.assert_called_once()
            self.assertEqual([c.args[1] for c in verify.call_args_list],
                             ['sun', 'rig', 'body'] + [row[0] for row in f.music.FILES])
        with self.assertRaises(ValueError): f.verify_candidate_resources(Path('app'), None)
        with patch.object(f.assets, 'verified_assets', side_effect=ValueError('corrupt')):
            with self.assertRaises(ValueError): f.verify_candidate_resources(Path('app'), Path('source'))


class SourceSkinCandidateTests(unittest.TestCase):
    def setUp(self):
        self.r = dict(channel='testflight-internal', source_branch=f.SOURCE_SKIN_BRANCH,
                      source_sha=f.SOURCE_SKIN_SHA, fighter_run_id=f.SOURCE_SKIN_RUN,
                      music_source_sha=f.MUSIC_SHA, build_number='703', version='1.2',
                      bundle_id='com.kriswu.shiftreminder', liu_sha256=f.model.SHA, notes='Internal only')
        self.run = dict(id=f.SOURCE_SKIN_RUN, head_sha=f.SOURCE_SKIN_SHA,
                        head_branch=f.SOURCE_SKIN_BRANCH, event='push', run_attempt=1,
                        path='.github/workflows/fighter-source-skins-followup.yml',
                        status='completed', conclusion='success')
        self.job = dict(name='visual', head_sha=f.SOURCE_SKIN_SHA, run_id=f.SOURCE_SKIN_RUN,
                        run_attempt=1, status='completed', conclusion='success',
                        steps=[dict(name=n, status='completed', conclusion='success') for n in f.SOURCE_SKIN_STEPS])

    def check(self, job=None, latest=None):
        with patch.object(f.asc, 'github', side_effect=[self.run,
                dict(total_count=1, jobs=[self.job if job is None else job]),
                self.run if latest is None else latest]):
            f.check_ci(self.r)

    def test_only_exact_requested_703_is_permitted(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'fighter-testflight.json'
            p.write_text(json.dumps(self.r)); self.assertEqual(f.load_request(p), self.r)
            for key, value in [('source_sha', f.CANDIDATE_SHA), ('fighter_run_id', f.SOURCE_SKIN_RUN+1),
                               ('music_source_sha', 'a'*40), ('build_number', '702'), ('version', '1.3')]:
                with self.subTest(key=key):
                    p.write_text(json.dumps(dict(self.r, **{key:value})))
                    with self.assertRaises(ValueError): f.load_request(p)

    def test_rendering_packaging_and_exact_native_scope_are_mandatory(self):
        self.check()
        for name in f.SOURCE_SKIN_STEPS:
            for fault in ('missing', 'duplicate', 'failure', 'skipped', 'in_progress'):
                with self.subTest(step=name, fault=fault):
                    job = copy.deepcopy(self.job)
                    step = next(s for s in job['steps'] if s['name'] == name)
                    if fault == 'missing': job['steps'].remove(step)
                    elif fault == 'duplicate': job['steps'].append(copy.deepcopy(step))
                    elif fault == 'in_progress': step['status'] = fault
                    else: step['conclusion'] = fault
                    with self.assertRaises(ValueError): self.check(job=job)

    def test_rerun_race_wrong_source_and_job_attempt_fail_closed(self):
        for field, value in [('id', 1), ('run_attempt', 2), ('head_sha', f.CANDIDATE_SHA),
                             ('head_branch', 'main'), ('status', 'in_progress'), ('conclusion', 'failure'),
                             ('path', '.github/workflows/fighter-real-resource-acceptance.yml')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.check(latest=dict(self.run, **{field:value}))
        for field, value in [('run_id', 1), ('run_attempt', 2), ('head_sha', f.CANDIDATE_SHA),
                             ('status', 'in_progress'), ('conclusion', 'skipped')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.check(job=dict(self.job, **{field:value}))

    def test_added_assets_require_pinned_manifest_and_actual_bundle_bytes(self):
        import hashlib
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); app = root/'app'; app.mkdir(); source = root/'source'; source.mkdir()
            (app/'trail.json').write_bytes(b'original')
            manifest = source/'manifest.json'
            manifest.write_text(json.dumps({'files':[dict(file='trail.json',bytes=8,
                sha256=hashlib.sha256(b'original').hexdigest())]}))
            expected = (('manifest.json', hashlib.sha256(manifest.read_bytes()).hexdigest(), 1),)
            with patch.object(f, 'SOURCE_SKIN_MANIFESTS', expected):
                self.assertEqual(f.verify_source_skin_resources(app, source), ['trail.json'])
                (app/'trail.json').write_bytes(b'modified')
                with self.assertRaises(ValueError): f.verify_source_skin_resources(app, source)
                (app/'trail.json').write_bytes(b'original'); manifest.write_text('{}')
                with self.assertRaises(ValueError): f.verify_source_skin_resources(app, source)
        with self.assertRaises(ValueError): f.verify_source_skin_resources(Path('app'), None)

    def test_703_cannot_report_archive_success_without_new_assets(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); app = root/'Products/Applications/ShiftReminder.app'
            widget = app/'PlugIns/Widget.appex/Info.plist'; widget.parent.mkdir(parents=True)
            info = dict(CFBundleIdentifier=self.r['bundle_id'], CFBundleShortVersionString='1.2',
                        CFBundleVersion='703', ArenaCommitSHA=f.SOURCE_SKIN_SHA)
            (app/'Info.plist').write_bytes(plistlib.dumps(info))
            widget.write_bytes(plistlib.dumps(dict(info, CFBundleIdentifier=self.r['bundle_id']+'.widget')))
            with patch.object(f.model, 'verify_app'), patch.object(f, 'verify_candidate_resources') as old, \
                 patch.object(f, 'verify_source_skin_resources', return_value=['trail.json']) as new, \
                 patch.object(f.asc, 'save_report') as report:
                f.archive(self.r, root, Path('source'))
                old.assert_called_once_with(app, Path('source'))
                new.assert_called_once_with(app, Path('source'))
                self.assertEqual(report.call_args.kwargs['additional_resources_verified'], ['trail.json'])
                report.reset_mock(); new.side_effect = ValueError('missing source skin')
                with self.assertRaises(ValueError): f.archive(self.r, root, Path('source'))
                report.assert_not_called()


if __name__ == '__main__': unittest.main()
