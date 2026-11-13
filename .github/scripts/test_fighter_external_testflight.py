import unittest
from unittest.mock import patch
import fighter_external_testflight as external
import fighter_promote as promotion


class ExternalCandidateTests(unittest.TestCase):
    def setUp(self):
        self.request = dict(channel='testflight-external', source_branch=promotion.SOURCE_SKIN_BRANCH,
            source_sha=promotion.PLAYABILITY_SHA, fighter_run_id=promotion.PLAYABILITY_RUN,
            build_number='705', version='1.2', music_source_sha=promotion.MUSIC_SHA,
            external_group_policy='existing-active-external', notify_external_testers=True)

    def test_candidate_pins_new_source_run_channel_and_audience(self):
        promotion.validate_playability_candidate(self.request)
        for key, value in [('source_sha', promotion.SOURCE_SKIN_SHA), ('fighter_run_id', promotion.SOURCE_SKIN_RUN),
                           ('build_number', '703'), ('channel', 'testflight-internal'),
                           ('external_group_policy', 'new-public-group'), ('notify_external_testers', False)]:
            with self.assertRaises(ValueError):
                promotion.validate_playability_candidate(dict(self.request, **{key: value}))

    def exercise(self, audience='APP_STORE_ELIGIBLE', state='READY_FOR_BETA_SUBMISSION', linked=False):
        calls = []
        notified = False
        build = {'id': 'build', 'attributes': {'processingState': 'VALID', 'buildAudienceType': audience}}
        def call(method, path, body=None):
            nonlocal state, linked, notified
            calls.append((method, path, body))
            if method == 'PATCH':
                self.assertEqual(body['data']['attributes'], {'autoNotifyEnabled': True})
                notified = True
                return {}
            if path.endswith('/relationships/betaGroups'):
                self.assertEqual(body['data'], [{'type': 'betaGroups', 'id': 'existing'}])
                linked = True
                return {}
            if method == 'POST' and path == '/betaAppReviewSubmissions':
                state = 'WAITING_FOR_BETA_REVIEW'
                return {'data': {'id': 'review'}}
            if path.endswith('/buildBetaDetail'):
                return {'data': {'id': 'detail', 'attributes': {
                    'externalBuildState': state, 'autoNotifyEnabled': notified}}}
            if path == '/betaGroups/existing/relationships/builds?limit=200':
                return {'data': [{'id': 'build'}] if linked else []}
            if path.startswith('/betaAppReviewSubmissions?'):
                return {'data': []}
            self.fail((method, path))
        with patch.object(external, 'inspect', return_value=('app', [{'id': 'existing', 'name': 'Existing'}])), \
             patch.object(external.asc, 'find_build', return_value=build), \
             patch.object(external.asc, 'call', side_effect=call), \
             patch.object(external.asc, 'save_report') as report:
            if audience == 'INTERNAL_ONLY':
                with self.assertRaisesRegex(ValueError, 'INTERNAL_ONLY'): external.submit(self.request)
                self.assertFalse(calls)
            else:
                external.submit(self.request)
                self.assertTrue(report.call_args.kwargs['groups_verified'])
                self.assertTrue(report.call_args.kwargs['auto_notify_enabled'])
                self.assertFalse(report.call_args.kwargs['installable_now'])
        return calls

    def test_internal_only_build_cannot_be_misreported_as_external(self):
        self.exercise(audience='INTERNAL_ONLY')

    def test_submit_links_only_existing_group_and_waits_for_apple(self):
        calls = self.exercise()
        self.assertEqual(sum(method == 'POST' for method, _, _ in calls), 2)

    def test_pending_review_is_not_submitted_or_linked_twice(self):
        calls = self.exercise(state='WAITING_FOR_BETA_REVIEW', linked=True)
        self.assertFalse(any(method == 'POST' for method, _, _ in calls))


if __name__ == '__main__':
    unittest.main()
