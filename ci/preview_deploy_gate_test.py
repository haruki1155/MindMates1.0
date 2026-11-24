"""Run with: python3 ci/preview_deploy_gate_test.py"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from preview_deploy_gate import decide  # noqa: E402

REPO = 'haruki1155/MindMates1.0'
SHA = 'a' * 40
NEWER = 'b' * 40


def pr(**overrides):
    value = {'number': 7, 'state': 'open', 'base': {'ref': 'main'},
             'head': {'sha': SHA, 'repo': {'full_name': REPO}}}
    value.update(overrides)
    return value


def run(status='completed', conclusion='success', head_sha=SHA):
    return {'id': 99, 'status': status, 'conclusion': conclusion, 'head_sha': head_sha}


class DecideTest(unittest.TestCase):
    def assert_skip(self, *args, contains=''):
        deploy, reason = decide(REPO, SHA, *args)
        self.assertFalse(deploy, reason)
        self.assertIn(contains, reason)

    def test_deploys_only_when_both_runs_succeeded_for_the_current_head(self):
        self.assertEqual(decide(REPO, SHA, pr(), run(), run())[0], True)

    def test_failed_or_cancelled_verification_never_deploys(self):
        for conclusion in ('failure', 'cancelled', 'timed_out', 'skipped', 'action_required', None):
            self.assert_skip(pr(), run(conclusion=conclusion), run(), contains='Verify Android flavors')
            self.assert_skip(pr(), run(), run(conclusion=conclusion), contains='Build staging Admin Web preview')

    def test_in_progress_or_missing_runs_wait(self):
        self.assert_skip(pr(), run(status='in_progress', conclusion=None), run(), contains='still in_progress')
        self.assert_skip(pr(), run(), run(status='queued', conclusion=None), contains='still queued')
        self.assert_skip(pr(), None, run(), contains='No Verify Android flavors run')
        self.assert_skip(pr(), run(), None, contains='No Build staging Admin Web preview run')

    def test_runs_for_another_commit_are_ignored(self):
        self.assert_skip(pr(), run(head_sha=NEWER), run(), contains='another commit')

    def test_stale_commit_never_overwrites_a_newer_preview(self):
        self.assert_skip(pr(head={'sha': NEWER, 'repo': {'full_name': REPO}}), run(), run(), contains='Stale')

    def test_prs_changing_ci_definitions_never_deploy(self):
        for path in ('.github/workflows/android-verify.yml', 'ci/verify_staging_web_bundle.sh'):
            self.assert_skip(pr(), run(), run(), [path, 'lib/main.dart'], contains='changes CI definitions')
        self.assertTrue(decide(REPO, SHA, pr(), run(), run(), ['lib/main.dart', 'docs/ci/notes.md'])[0])

    def test_closed_fork_and_wrong_base_prs_are_refused(self):
        self.assert_skip(None, run(), run(), contains='No open')
        self.assert_skip(pr(state='closed'), run(), run(), contains='closed')
        self.assert_skip(pr(base={'ref': 'develop'}), run(), run(), contains='does not target main')
        self.assert_skip(pr(head={'sha': SHA, 'repo': {'full_name': 'someone/fork'}}), run(), run(),
                         contains='not from this repository')
        self.assert_skip(pr(head={'sha': SHA, 'repo': None}), run(), run(), contains='not from this repository')


if __name__ == '__main__':
    unittest.main()
