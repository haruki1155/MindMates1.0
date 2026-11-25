"""Fail unless the caller can deploy Hosting and holds none of the sensitive permissions below.

Usage: GOOGLE_ACCESS_TOKEN=<token of the deploy identity> verify_deployer_least_privilege.py <project_id>

projects.testIamPermissions reports which of the listed permissions the caller
effectively holds (including through inherited and custom roles), and any
identity may ask it about itself. This checks real IAM, not key metadata.
"""
import json
import os
import sys
import urllib.error
import urllib.request

REQUIRED = {
    'firebasehosting.sites.get',
    'firebasehosting.sites.update',
}
FORBIDDEN = {
    'resourcemanager.projects.setIamPolicy',
    'resourcemanager.projects.getIamPolicy',
    'iam.serviceAccountKeys.create',
    'iam.serviceAccounts.actAs',
    'iam.serviceAccounts.getAccessToken',
    'iam.serviceAccounts.signBlob',
    'iam.serviceAccounts.signJwt',
    'iam.serviceAccounts.implicitDelegation',
    'serviceusage.services.enable',
    'resourcemanager.projects.delete',
    'storage.objects.create',
    'storage.objects.delete',
    'cloudfunctions.functions.create',
    'run.services.create',
    'datastore.entities.get',
    'datastore.entities.update',
    'firebaseauth.users.get',
    'firebaseauth.users.update',
    'firebaseauth.configs.update',
    'storage.objects.get',
    'storage.buckets.update',
    'cloudfunctions.functions.update',
    'run.services.update',
    'secretmanager.versions.access',
    'firebaserules.releases.update',
    'firebaseappcheck.services.update',
}


def granted(project_id: str, token: str) -> set[str]:
    request = urllib.request.Request(
        f'https://cloudresourcemanager.googleapis.com/v1/projects/{project_id}:testIamPermissions',
        data=json.dumps({'permissions': sorted(REQUIRED | FORBIDDEN)}).encode(),
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return set(json.load(response).get('permissions', []))
    except urllib.error.HTTPError as error:
        sys.exit(f'testIamPermissions failed with HTTP {error.code}.')


def main() -> None:
    project_id = sys.argv[1]
    token = os.environ.get('GOOGLE_ACCESS_TOKEN', '').strip()
    if not token:
        sys.exit('GOOGLE_ACCESS_TOKEN is not set.')
    have = granted(project_id, token)
    missing = REQUIRED - have
    excess = FORBIDDEN & have
    if missing:
        sys.exit(f'The deploy identity cannot deploy Hosting on {project_id}: missing {sorted(missing)}.')
    if excess:
        sys.exit(f'The deploy identity is broader than Hosting on {project_id}: it holds {sorted(excess)}.')
    print(f'The deploy identity holds Hosting deploy rights and none of the {len(FORBIDDEN)} checked sensitive permissions.')


if __name__ == '__main__':
    main()
