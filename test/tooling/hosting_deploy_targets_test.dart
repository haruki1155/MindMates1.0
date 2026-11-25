import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Firebase Hosting deployment boundaries: routine workflows only
/// ever reach mindmate-staging, credentials only reach trusted workflow code,
/// and production is manual and explicit.
void main() {
  const staging = 'mindmate-staging';
  const production = 'mind-mates-cd2cf';
  const pinnedDeployAction =
      'FirebaseExtended/action-hosting-deploy@500ac625ca2dd40cbd15f7659af953801858032a';
  const stagingKey = 'secrets.FIREBASE_SERVICE_ACCOUNT_MINDMATE_STAGING';
  const stagingRecaptchaKey = '6Le17JgtAAAAACbHth-LPHcS_P2n4ejBuddUYReM';

  const dir = '.github/workflows';
  const verifyWorkflow = '$dir/android-verify.yml';
  const buildWorkflow = '$dir/firebase-hosting-pull-request.yml';
  const previewDeployWorkflow = '$dir/firebase-hosting-preview-deploy.yml';
  const cleanupWorkflow = '$dir/firebase-hosting-preview-cleanup.yml';
  const mergeWorkflow = '$dir/firebase-hosting-merge.yml';
  const productionWorkflow = '$dir/firebase-hosting-production.yml';
  const stagingWorkflows = [
    buildWorkflow,
    previewDeployWorkflow,
    cleanupWorkflow,
    mergeWorkflow,
  ];

  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');
  List<String> lines(String path, String needle) => read(path)
      .split('\n')
      .where((line) => line.contains(needle))
      .map((line) => line.trim())
      .toList();
  String workflowName(String path) =>
      lines(path, 'name:').first.replaceFirst('name:', '').trim();
  List<String> allWorkflows() =>
      Directory(dir)
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.endsWith('.yml') || p.endsWith('.yaml'))
          .toList()
        ..sort();

  test('routine workflows never reach production or deploy backends', () {
    for (final workflow in stagingWorkflows) {
      final source = read(workflow);
      expect(source, isNot(contains(production)), reason: workflow);
      expect(source, isNot(contains('MIND_MATES_CD2CF')), reason: workflow);
      expect(source, isNot(contains('secrets.FIREBASE_SERVICE_ACCOUNT ')));
      expect(source, isNot(contains('secrets.FIREBASE_SERVICE_ACCOUNT}')));
      expect(source, isNot(contains('--only functions')), reason: workflow);
      expect(source, isNot(contains('firestore:rules')), reason: workflow);
      expect(source, isNot(contains('storage:rules')), reason: workflow);
      for (final line in lines(workflow, 'action-hosting-deploy@')) {
        expect(line, endsWith(pinnedDeployAction), reason: workflow);
        expect(source, contains('projectId: $staging'), reason: workflow);
      }
    }
  });

  test('the deploy credential only reaches main-only environments', () {
    for (final workflow in allWorkflows()) {
      final source = read(workflow);
      if (!source.contains(stagingKey)) continue;
      expect(
        source,
        anyOf(
          contains('environment: staging\n'),
          contains('environment: staging-preview\n'),
        ),
        reason: '$workflow uses the staging deploy credential',
      );
      expect(
        source,
        contains('ci/verify_hosting_deployer.sh "\$PROJECT_ID" "\$DEPLOYER"'),
        reason: workflow,
      );
      expect(
        source,
        contains(
          'DEPLOYER: github-hosting-deployer@$staging.iam.gserviceaccount.com',
        ),
        reason: workflow,
      );
    }
  });

  test('only the cleanup workflow uses pull_request_target, without PR code', () {
    for (final workflow in allWorkflows()) {
      if (workflow == cleanupWorkflow) continue;
      expect(read(workflow), isNot(contains('pull_request_target')));
    }
    final cleanup = read(cleanupWorkflow);
    expect(cleanup, contains('pull_request_target:'));
    expect(
      cleanup,
      contains(r'ref: ${{ github.event.repository.default_branch }}'),
    );
    expect(cleanup, isNot(contains('pull_request.head.sha')));
    expect(cleanup, isNot(contains('pull_request.head.ref')));
    expect(cleanup, isNot(contains('flutter')));
    expect(cleanup, isNot(contains('channelId')));
    expect(cleanup, contains(r'[[ "$CHANNEL_ID" =~ ^pr-[0-9]+$ ]]'));
    expect(
      cleanup,
      contains(r'CHANNEL_ID: pr-${{ github.event.pull_request.number }}'),
    );
  });

  test('the PR build has no secrets and keeps App Check off', () {
    final source = read(buildWorkflow);
    expect(source, contains('\n  pull_request:\n'));
    expect(source, isNot(contains('secrets.')));
    expect(source, isNot(contains('environment:')));
    expect(source, isNot(contains('action-hosting-deploy')));
    expect(source, contains('python3 ci/preview_deploy_gate_test.py'));
    final builds = lines(buildWorkflow, 'flutter build web');
    expect(builds, hasLength(1));
    expect(builds.single, contains('--target lib/admin_main.dart'));
    expect(builds.single, contains('--dart-define=APP_ENV=staging'));
    expect(builds.single, isNot(contains('ENABLE_STAGING_APP_CHECK')));
    expect(source, contains('name: admin-web-staging'));
  });

  test('previews deploy only after verification, from trusted code', () {
    final source = read(previewDeployWorkflow);
    // The names must match exactly, or workflow_run never fires.
    expect(
      source,
      contains(
        'workflows: ["${workflowName(verifyWorkflow)}", "${workflowName(buildWorkflow)}"]',
      ),
    );
    expect(source, contains('python3 ci/preview_deploy_gate.py'));
    expect(read('ci/preview_deploy_gate.py'), contains("'android-verify.yml'"));
    expect(
      read('ci/preview_deploy_gate.py'),
      contains("'firebase-hosting-pull-request.yml'"),
    );
    expect(source, contains("if: needs.gate.outputs.deploy == 'true'"));
    expect(source, contains('environment: staging-preview'));
    expect(
      source,
      contains(r'ref: ${{ github.event.repository.default_branch }}'),
    );
    expect(source, isNot(contains(r'ref: ${{ github.event.workflow_run')));
    expect(source, isNot(contains('flutter build')));
    expect(source, contains(r'run-id: ${{ needs.gate.outputs.build_run_id }}'));
    expect(
      source,
      contains(
        'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093',
      ),
    );
    expect(source, contains('path: build/web'));
    expect(source, contains(r'CHANNEL_ID: pr-${{ needs.gate.outputs.pr }}'));
    expect(source, contains(r'channelId: ${{ env.CHANNEL_ID }}'));
    expect(source, isNot(contains('channelId: live')));
    expect(source, contains('expires: 7d'));
    expect(source, contains(r'group: hosting-preview-pr-${{ needs.gate.outputs.pr }}'));
    expect(source, contains('cancel-in-progress: false'));
    expect(read(cleanupWorkflow), contains('cancel-in-progress: true'));
    expect(source, contains("if: steps.freshness.outputs.current == 'true'"));
    expect(read('ci/preview_deploy_gate.py'), contains("PROTECTED_PREFIXES = ('.github/', 'ci/')"));
    expect(read(cleanupWorkflow), contains(r'group: hosting-preview-pr-${{ github.event.pull_request.number }}'));
  });

  test('the merge workflow deploys verified main commits to staging live', () {
    final source = read(mergeWorkflow);
    expect(
      source,
      contains('workflows: ["${workflowName(verifyWorkflow)}"]'),
    );
    expect(source, contains("github.event.workflow_run.conclusion == 'success'"));
    expect(source, contains('actions: read'));
    expect(source, contains('environment: staging\n'));
    expect(source, contains('channelId: live'));
    expect(source, contains('group: hosting-staging-live'));
    expect(source, contains(r'ref: ${{ env.DEPLOY_SHA }}'));
    expect(source, isNot(contains('\n  push:')));
    expect(source, isNot(contains('\n  pull_request')));
    final builds = lines(mergeWorkflow, 'flutter build web');
    expect(builds, hasLength(1));
    expect(builds.single, contains('--target lib/admin_main.dart'));
    expect(builds.single, contains('--dart-define=APP_ENV=staging'));
    expect(builds.single, contains('--dart-define=ENABLE_STAGING_APP_CHECK=true'));
    expect(
      builds.single,
      contains(r'--dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=$STAGING_RECAPTCHA_SITE_KEY'),
    );
    expect(source, contains('STAGING_RECAPTCHA_SITE_KEY: $stagingRecaptchaKey'));
    expect(
      source,
      contains(r'ci/verify_staging_web_bundle.sh build/web "$STAGING_RECAPTCHA_SITE_KEY"'),
    );
  });

  test('production is manual, confirmed, main-only, without fallback', () {
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
    expect(source, isNot(contains('||')));
    expect(source, isNot(contains('secrets.FIREBASE_SERVICE_ACCOUNT }}')));
    expect(
      source,
      contains(
        'ci/verify_hosting_deployer.sh $production github-hosting-deployer@$production.iam.gserviceaccount.com',
      ),
    );
    final builds = lines(productionWorkflow, 'flutter build web');
    expect(builds, hasLength(1));
    expect(builds.single, contains('--dart-define=APP_ENV=production'));
    expect(builds.single, isNot(contains('ENABLE_STAGING_APP_CHECK')));
    for (final line in lines(productionWorkflow, 'action-hosting-deploy@')) {
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

  test('browsers revalidate every Flutter Web file after a deploy', () {
    // Flutter Web file names carry no content hash, and each build re-subsets
    // the icon fonts. A cached file from the previous deploy mixed with a new
    // one draws missing-glyph boxes, so every response must be revalidated.
    final hosting =
        (jsonDecode(read('firebase.json')) as Map<String, dynamic>)['hosting']
            as Map<String, dynamic>;
    expect(hosting['headers'], [
      {
        'source': '**',
        'headers': [
          {'key': 'Cache-Control', 'value': 'no-cache'},
        ],
      },
    ]);
  });
}
