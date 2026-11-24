import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Firebase Hosting deployment boundaries: routine workflows only
/// ever reach mindmate-staging, and production is manual and explicit.
void main() {
  const staging = 'mindmate-staging';
  const production = 'mind-mates-cd2cf';
  const pinnedDeployAction =
      'FirebaseExtended/action-hosting-deploy@500ac625ca2dd40cbd15f7659af953801858032a';

  String read(String path) => File(path).readAsStringSync();
  List<String> buildLines(String workflow) => read(
    workflow,
  ).split('\n').where((line) => line.contains('flutter build web')).toList();
  List<String> deployActions(String workflow) => read(workflow)
      .split('\n')
      .where((line) => line.contains('action-hosting-deploy'))
      .map((line) => line.trim())
      .toList();

  const prWorkflow = '.github/workflows/firebase-hosting-pull-request.yml';
  const mergeWorkflow = '.github/workflows/firebase-hosting-merge.yml';
  const productionWorkflow = '.github/workflows/firebase-hosting-production.yml';

  for (final workflow in [prWorkflow, mergeWorkflow]) {
    group(workflow, () {
      test('targets only the staging project and staging build', () {
        final source = read(workflow);
        expect(source, isNot(contains(production)));
        expect(source, isNot(contains('MIND_MATES_CD2CF')));
        // No fallback to a generic, possibly production, credential.
        expect(source, isNot(contains('secrets.FIREBASE_SERVICE_ACCOUNT ')));
        expect(source, isNot(contains('secrets.FIREBASE_SERVICE_ACCOUNT}')));
        expect(source, contains('projectId: $staging'));
        final builds = buildLines(workflow);
        expect(builds, hasLength(1));
        expect(builds.single, contains('--target lib/admin_main.dart'));
        expect(builds.single, contains('--dart-define=APP_ENV=staging'));
        expect(source, contains('ci/verify_staging_web_bundle.sh build/web'));
      });

      test('uses the pinned deploy action and a Hosting-only credential', () {
        final source = read(workflow);
        for (final line in deployActions(workflow)) {
          expect(line, endsWith(pinnedDeployAction));
        }
        expect(
          source,
          contains(
            'DEPLOYER: github-hosting-deployer@$staging.iam.gserviceaccount.com',
          ),
        );
        expect(source, contains('ci/verify_hosting_service_account.py'));
        expect(source, isNot(contains('pull_request_target')));
        // Routine Hosting deploys never ship backend resources.
        expect(source, isNot(contains('--only functions')));
        expect(source, isNot(contains('firestore:rules')));
        expect(source, isNot(contains('storage:rules')));
      });
    });
  }

  test('PR previews never touch the live channel', () {
    final source = read(prWorkflow);
    expect(source, isNot(contains('channelId: live')));
    expect(source, contains(r'CHANNEL_ID: pr-${{ github.event.pull_request.number }}'));
    expect(source, contains(r'channelId: ${{ env.CHANNEL_ID }}'));
    expect(source, contains('expires: 7d'));
    expect(source, contains(r'[[ "$CHANNEL_ID" =~ ^pr-[0-9]+$ ]]'));
    expect(source, contains('cancel-in-progress: true'));
  });

  test('the merge workflow deploys verified main commits to staging live', () {
    final source = read(mergeWorkflow);
    expect(source, contains('workflows: ["Verify Android flavors"]'));
    expect(source, contains("github.event.workflow_run.conclusion == 'success'"));
    expect(source, contains('channelId: live'));
    expect(source, contains('group: hosting-staging-live'));
    expect(source, contains(r'ref: ${{ env.DEPLOY_SHA }}'));
    expect(source, isNot(contains('\n  push:')));
    expect(source, isNot(contains('\n  pull_request')));
  });

  test('production is manual, confirmed, main-only and environment-gated', () {
    final source = read(productionWorkflow);
    expect(source, contains('workflow_dispatch:'));
    expect(source, isNot(contains('\n  push:')));
    expect(source, isNot(contains('\n  pull_request')));
    expect(source, isNot(contains('workflow_run')));
    expect(source, contains('confirm_production_deploy'));
    expect(source, contains("github.ref == 'refs/heads/main'"));
    expect(source, contains('environment: production'));
    expect(source, contains('projectId: $production'));
    expect(source, isNot(contains(staging)));
    final builds = buildLines(productionWorkflow);
    expect(builds, hasLength(1));
    expect(builds.single, contains('--dart-define=APP_ENV=production'));
    for (final line in deployActions(productionWorkflow)) {
      expect(line, endsWith(pinnedDeployAction));
    }
  });

  test('the Firebase CLI default project is not production', () {
    final projects =
        (jsonDecode(read('.firebaserc')) as Map<String, dynamic>)['projects']
            as Map<String, dynamic>;
    expect(projects['default'], staging);
    expect(projects['staging'], staging);
    expect(projects['production'], production);
  });

  test('Hosting serves the SPA for app routes such as /reset-password', () {
    final hosting =
        (jsonDecode(read('firebase.json')) as Map<String, dynamic>)['hosting']
            as Map<String, dynamic>;
    expect(hosting['public'], 'build/web');
    expect(hosting['rewrites'], [
      {'source': '**', 'destination': '/index.html'},
    ]);
  });
}
