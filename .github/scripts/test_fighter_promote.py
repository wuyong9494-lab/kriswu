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


if __name__ == '__main__': unittest.main()
