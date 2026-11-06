import unittest
from run_private_arena_rendering import summary_counts


class PrivateRenderingResultTests(unittest.TestCase):
    def setUp(self):
        self.result = {'result':'Passed','totalTestCount':2,'passedTests':2,'failedTests':0,'skippedTests':0}

    def test_both_actual_tests_are_required(self):
        self.assertTrue(summary_counts(self.result)[1])
        for key in self.result:
            with self.subTest(missing=key):
                self.assertFalse(summary_counts({k:v for k,v in self.result.items() if k != key})[1])

    def test_zero_skipped_extra_failed_and_boolean_counts_cannot_pass(self):
        for changed in [{'totalTestCount':0,'passedTests':0},{'passedTests':1,'skippedTests':1},
                        {'totalTestCount':3,'passedTests':3},{'passedTests':1,'failedTests':1},
                        {'failedTests':False},{'result':'Failed'}]:
            with self.subTest(changed=changed):
                self.assertFalse(summary_counts({**self.result,**changed})[1])

    def test_only_counts_escape_private_result(self):
        counts,passed = summary_counts({**self.result,'testFailures':['private diagnostic'],'testPlanName':'private'})
        self.assertTrue(passed)
        self.assertEqual(set(counts),{'totalTestCount','passedTests','failedTests','skippedTests'})


if __name__ == '__main__': unittest.main()
