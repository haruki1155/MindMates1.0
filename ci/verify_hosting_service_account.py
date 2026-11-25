"""Fail unless $FIREBASE_SERVICE_ACCOUNT is the expected Hosting-only deployer key.

Usage: verify_hosting_service_account.py <project_id> <service_account_email>

Only metadata is checked and nothing from the key is printed. Pinning the
email stops a broader key (for example the Firebase Admin SDK account) from
being used as the deploy credential.
"""
import json
import os
import sys


def main() -> None:
    project_id, expected_email = sys.argv[1], sys.argv[2]
    secret_hint = 'the GitHub Actions secret for ' + project_id
    raw = os.environ.get('FIREBASE_SERVICE_ACCOUNT')
    if not raw:
        sys.exit(f'Missing deploy credential: set {secret_hint}.')
    try:
        account = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(f'{secret_hint} must contain the service account JSON key.')
    if not isinstance(account, dict) or account.get('type') != 'service_account':
        sys.exit(f'{secret_hint} must contain a service account JSON key.')
    if account.get('project_id') != project_id:
        sys.exit(f'The deploy credential must belong to project {project_id}.')
    if not account.get('private_key'):
        sys.exit(f'{secret_hint} must contain the full JSON key.')
    if account.get('client_email') != expected_email:
        sys.exit(f'The deploy credential must be the Hosting-only account {expected_email}.')
    print(f'Deploy credential is {expected_email} on {project_id}.')


if __name__ == '__main__':
    main()
