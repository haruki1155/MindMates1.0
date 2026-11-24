"""Decide whether a PR preview may be deployed for one commit.

Run by firebase-hosting-preview-deploy.yml (from main) with GH_TOKEN, REPO,
HEAD_SHA and optionally EVENT_PR set. Writes deploy/pr/build_run_id to
$GITHUB_OUTPUT. The decision itself is the pure function `decide`, covered by
ci/preview_deploy_gate_test.py.
"""
import json
import os
import subprocess
import sys

VERIFY_WORKFLOW = 'android-verify.yml'
# Both required checks run on pull_request, i.e. from the PR's own workflow
# files. A PR that changes them (or the CI helpers) could fake a pass, so it
# gets no preview; it deploys only after review and merge.
PROTECTED_PREFIXES = ('.github/', 'ci/')
BUILD_WORKFLOW = 'firebase-hosting-pull-request.yml'


def decide(repo, head_sha, pr, verify_run, build_run, changed_files=()):
    """Return (deploy, reason). Anything other than a clean pass is a skip."""
    if not pr:
        return False, f'No open same-repository PR into main for {head_sha}.'
    if pr.get('state') != 'open':
        return False, f'PR #{pr.get("number")} is {pr.get("state")}.'
    if pr.get('base', {}).get('ref') != 'main':
        return False, f'PR #{pr["number"]} does not target main.'
    if (pr.get('head', {}).get('repo') or {}).get('full_name') != repo:
        return False, f'PR #{pr["number"]} is not from this repository.'
    if pr.get('head', {}).get('sha') != head_sha:
        return False, f'Stale: PR #{pr["number"]} has moved on to {pr["head"].get("sha")}.'
    protected = sorted(f for f in changed_files if f.startswith(PROTECTED_PREFIXES))
    if protected:
        return False, (f'::notice::PR #{pr["number"]} changes CI definitions ({", ".join(protected[:5])}); '
                       'previews are not deployed for it.')
    for name, run in (('Verify Android flavors', verify_run), ('Build staging Admin Web preview', build_run)):
        if not run:
            return False, f'No {name} run for {head_sha} yet.'
        if run.get('head_sha') != head_sha:
            return False, f'The {name} run is for another commit.'
        if run.get('status') != 'completed':
            # Its own completion triggers the deploy workflow again.
            return False, f'{name} is still {run.get("status")} for {head_sha}.'
        if run.get('conclusion') != 'success':
            return False, f'::warning::{name} concluded {run.get("conclusion")} for {head_sha}; no preview is deployed.'
    return True, f'Gate passed for PR #{pr["number"]} at {head_sha}.'


def gh(path):
    result = subprocess.run(['gh', 'api', path], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def changed_files(repo, number):
    result = subprocess.run(
        ['gh', 'api', '--paginate', f'repos/{repo}/pulls/{number}/files?per_page=100', '--jq', '.[].filename'],
        check=True, capture_output=True, text=True)
    return result.stdout.split()


def latest_run(repo, workflow, head_sha):
    runs = gh(f'repos/{repo}/actions/workflows/{workflow}/runs?head_sha={head_sha}&event=pull_request&per_page=1')
    return (runs.get('workflow_runs') or [None])[0]


def find_pr(repo, head_sha, event_pr):
    if event_pr.isdigit():
        return gh(f'repos/{repo}/pulls/{event_pr}')
    for candidate in gh(f'repos/{repo}/commits/{head_sha}/pulls'):
        if candidate.get('state') == 'open' and candidate.get('base', {}).get('ref') == 'main':
            return gh(f'repos/{repo}/pulls/{candidate["number"]}')
    return None


def main():
    repo, head_sha = os.environ['REPO'], os.environ['HEAD_SHA']
    pr = find_pr(repo, head_sha, os.environ.get('EVENT_PR', '').strip())
    verify_run = latest_run(repo, VERIFY_WORKFLOW, head_sha) if pr else None
    build_run = latest_run(repo, BUILD_WORKFLOW, head_sha) if pr else None
    files = changed_files(repo, pr['number']) if pr else []
    deploy, reason = decide(repo, head_sha, pr, verify_run, build_run, files)
    print(reason)
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write(f'deploy={"true" if deploy else "false"}\n')
        if deploy:
            output.write(f'pr={pr["number"]}\nbuild_run_id={build_run["id"]}\n')


if __name__ == '__main__':
    sys.exit(main())
