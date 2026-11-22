import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_detail_screen.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/repositories/admin_status_repository.dart';

void main() {
  for (final version in const [
    'student_wellbeing_v4',
    'teaching_workplace_reflection_v4',
    'non_teaching_workplace_reflection_v4',
  ]) {
    testWidgets('simplifies $version V4 assessment details with semantic badges', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-1',
            userLabel: 'Student',
            repository: _Repository([_v4Record(version)]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_displayName(version)), findsNWidgets(2));
      expect(
        find.text('Well-being appears generally supported.'),
        findsOneWidget,
      );
      expect(find.text('Stored profile summary.'), findsOneWidget);
      expect(find.text('Follow-up guidance.'), findsOneWidget);
      expect(find.text('Response quality'), findsOneWidget);
      expect(find.text('Well-being areas'), findsOneWidget);
      expect(find.text('Current strengths'), findsOneWidget);
      expect(find.text('Areas to explore'), findsOneWidget);
      expect(find.text('Assessment information'), findsNothing);

      expect(find.text('What the responses suggest overall'), findsNothing);
      expect(find.text('Suggested next steps'), findsNothing);
      expect(find.text('Counselor discussion guide'), findsNothing);
      expect(find.text(version), findsNothing);

      // Header + _AreaPanel + _V4DomainReview + _AssessmentHistory all use semantic green AdminStatusBadge.
      final badges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(badges, hasLength(4));
      for (final badge in badges) {
        expect(badge.presentation.tone, AdminSemanticTone.green);
        expect(badge.presentation.label, 'Supported');
        expect(badge.presentation.backgroundColor, AdminColors.greenBg);
        expect(badge.presentation.foregroundColor, AdminColors.greenFg);
        expect(badge.presentation.icon, Icons.check_circle_outline);
      }

      // Hardcoded accentStrong status text is completely gone.
      final accentTexts = tester.widgetList<Text>(find.byType(Text)).where(
        (t) => t.style?.color == AdminColors.accentStrong,
      );
      expect(accentTexts, isEmpty);
    });
  }

  testWidgets(
    'V4 detail screen renders all 5 profileStatus tones plus unknown fallback cleanly',
    (tester) async {
      final cases = <(String?, AdminSemanticTone, String, Color, IconData, String)>[
        (
          'generallySupported',
          AdminSemanticTone.green,
          'Supported',
          AdminColors.greenBg,
          Icons.check_circle_outline,
          'Well-being appears generally supported.',
        ),
        (
          'mostlySupported',
          AdminSemanticTone.blue,
          'Mostly supported',
          AdminColors.blueBg,
          Icons.info_outline,
          'Mostly supported, with an area to explore.',
        ),
        (
          'someAreasNeedAttention',
          AdminSemanticTone.amber,
          'Some areas need attention',
          AdminColors.amberBg,
          Icons.warning_amber_outlined,
          'Some areas may benefit from attention.',
        ),
        (
          'supportMayHelp',
          AdminSemanticTone.red,
          'Support may help',
          AdminColors.redBg,
          Icons.priority_high_rounded,
          'Support may be helpful right now.',
        ),
        (
          'insufficientResponses',
          AdminSemanticTone.neutral,
          'Insufficient responses',
          AdminColors.neutralBg,
          Icons.help_outline,
          'More responses are needed for a complete profile.',
        ),
        (
          'unexpected_v4_band',
          AdminSemanticTone.neutral,
          'unexpected v4 band',
          AdminColors.neutralBg,
          Icons.help_outline,
          'More responses are needed for a complete profile.',
        ),
        (
          null,
          AdminSemanticTone.neutral,
          'Result unavailable',
          AdminColors.neutralBg,
          Icons.help_outline,
          'More responses are needed for a complete profile.',
        ),
      ];

      for (final (
            profileStatus,
            expectedTone,
            expectedLabel,
            expectedBg,
            expectedIcon,
            expectedHeadline,
          )
          in cases) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: AdminAssessmentDetailScreen(
              userId: 'user-1',
              userLabel: 'Student',
              repository: _Repository([
                {
                  'id': 'v4-$profileStatus',
                  'schemaVersion': 'assessment_record_v4',
                  'createdAt': '2026-10-01T00:00:00.000Z',
                  'instrument': {'version': 'student_wellbeing_v4'},
                  'result': {
                    'profileStatus': ?profileStatus,
                    'responseQuality': {
                      'answered': 50,
                      'presented': 50,
                      'confidence': 'high',
                    },
                    'domainResults': const [],
                  },
                  'interpretation': {
                    'userSummary': 'Summary.',
                    'disclaimer': 'Disclaimer.',
                  },
                },
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(expectedHeadline), findsOneWidget);
        final badges = tester
            .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
            .toList();
        // Header badge + history badge
        expect(badges, hasLength(2));
        expect(
          badges.first.presentation.tone,
          expectedTone,
          reason: 'tone for $profileStatus',
        );
        expect(
          badges.first.presentation.label,
          expectedLabel,
          reason: 'label for $profileStatus',
        );
        expect(
          badges.first.presentation.backgroundColor,
          expectedBg,
          reason: 'bg for $profileStatus',
        );
        expect(
          badges.first.presentation.icon,
          expectedIcon,
          reason: 'icon for $profileStatus',
        );
      }
    },
  );

  testWidgets(
    'V4 domain areas and domain review render mixed semantic badges and mixed history items render accurately',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-1',
            userLabel: 'Alex',
            assessmentId: 'v4-curr',
            repository: _Repository([
              {
                'id': 'v4-curr',
                'schemaVersion': 'assessment_record_v4',
                'createdAt': '2026-11-20T00:00:00.000Z',
                'instrument': {'version': 'student_wellbeing_v4'},
                'result': {
                  'profileStatus': 'someAreasNeedAttention',
                  'responseQuality': {
                    'answered': 40,
                    'presented': 50,
                    'confidence': 'moderate',
                  },
                  'domainResults': [
                    {
                      'domainId': 'academic',
                      'status': 'supported',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                    {
                      'domainId': 'financial',
                      'status': 'mostlySupported',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                    {
                      'domainId': 'socialAdjustment',
                      'status': 'someStrain',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                    {
                      'domainId': 'sleepRest',
                      'status': 'supportMayHelp',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                    {
                      'domainId': 'emotionalWellbeing',
                      'status': 'insufficientResponses',
                      'answeredCount': 2,
                      'presentedCount': 10,
                      'isScorable': false,
                    },
                  ],
                },
                'interpretation': {
                  'userSummary': 'Mixed domains summary.',
                  'disclaimer': 'Disclaimer.',
                  'domainSummaries': const [],
                },
              },
              {
                'id': 'v3-prev',
                'type': 'full',
                'createdAt': '2026-10-15T00:00:00.000Z',
                'status': 'Thriving',
              },
              {
                'id': 'quick-prev',
                'type': 'quick',
                'createdAt': '2026-09-10T00:00:00.000Z',
                'overallLevel': 'veryHigh',
              },
              {
                'id': 'unknown-prev',
                'type': 'full',
                'createdAt': '2026-08-01T00:00:00.000Z',
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mixed history should identify Quick Assessment & Psychological Assessment properly,
      // and never mislabel non-V4 items with V4 profile fallback text.
      expect(find.text('Psychological Assessment'), findsNWidgets(2));
      expect(find.text('Quick Assessment'), findsOneWidget);

      final badges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      final tones = badges.map((b) => b.presentation.tone).toSet();
      expect(
        tones,
        containsAll([
          AdminSemanticTone.green,
          AdminSemanticTone.blue,
          AdminSemanticTone.amber,
          AdminSemanticTone.red,
          AdminSemanticTone.neutral,
        ]),
      );

      // Verify specific history badges: V3 Thriving (green), Quick veryHigh (red), missing (neutral Result unavailable).
      expect(find.text('Very high'), findsOneWidget);
      expect(find.text('Result unavailable'), findsOneWidget);
    },
  );

  testWidgets(
    'Legacy V3 Full Assessment with interpretation and legacy fallback without interpretation render semantic badges',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-v3',
            userLabel: 'Pat',
            assessmentId: 'v3-full',
            repository: _Repository([
              {
                'id': 'v3-full',
                'type': 'full',
                'createdAt': '2026-11-12T00:00:00.000Z',
                'status': 'Needs Improvement',
                'responsePatternCode': 'someStrain',
                'interpretation': {
                  'responseQuality': {'confidenceLabel': 'High confidence'},
                  'userSummary': 'Legacy V3 summary.',
                  'domainResults': [
                    {
                      'domain': 'Academic',
                      'responsePatternCode': 'wellBeingSupported',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                    {
                      'domain': 'Emotional',
                      'responsePatternCode': 'supportMayHelp',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                  ],
                },
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(badges, hasLength(3));
      expect(badges[0].presentation.tone, AdminSemanticTone.amber);
      expect(badges[0].presentation.label, 'Some areas need attention');
      expect(badges[1].presentation.tone, AdminSemanticTone.green);
      expect(badges[1].presentation.label, 'Supported');
      expect(badges[2].presentation.tone, AdminSemanticTone.red);
      expect(badges[2].presentation.label, 'Support may help');

      // Legacy fallback without interpretation
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-legacy',
            userLabel: 'Sam',
            repository: _Repository([
              {
                'id': 'legacy-no-interp',
                'type': 'full',
                'createdAt': '2026-11-01T00:00:00.000Z',
                'status': 'At Risk',
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Legacy assessment'), findsOneWidget);
      final fallbackBadge = tester.widget<AdminStatusBadge>(
        find.byType(AdminStatusBadge),
      );
      expect(fallbackBadge.presentation.tone, AdminSemanticTone.red);
      expect(fallbackBadge.presentation.label, 'Support may help');
      expect(fallbackBadge.presentation.backgroundColor, AdminColors.redBg);
    },
  );

  testWidgets('Detail screen handles loading, empty, and error states cleanly', (
    tester,
  ) async {
    final completer = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: AdminAssessmentDetailScreen(
          userId: 'u-load',
          userLabel: 'Loading User',
          repository: _FutureRepo(() => completer.future),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No assessments available.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: AdminAssessmentDetailScreen(
          userId: 'u-err',
          userLabel: 'Error User',
          repository: _FutureRepo(() async => throw StateError('boom')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load assessments.'), findsOneWidget);
  });

  testWidgets(
    'legacy fallback card and history resolve wellBeingStatus and responsePatternCode without neutral Result unavailable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-legacy-wb',
            userLabel: 'Taylor',
            repository: _Repository([
              {
                'id': 'legacy-wellbeing',
                'type': 'full',
                'createdAt': '2026-11-10T00:00:00.000Z',
                'status': '   ',
                'wellBeingStatus': 'Needs Improvement',
                'responsePatternCode': 'someStrain',
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Legacy assessment'), findsOneWidget);
      expect(find.text('Result unavailable'), findsNothing);
      expect(find.textContaining('Needs Improvement'), findsOneWidget);
      final legacyBadge = tester.widget<AdminStatusBadge>(
        find.byType(AdminStatusBadge),
      );
      expect(legacyBadge.presentation.tone, AdminSemanticTone.amber);
      expect(legacyBadge.presentation.label, 'Some areas need attention');

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-history-wb',
            userLabel: 'Jordan',
            assessmentId: 'v4-main',
            repository: _Repository([
              _v4Record('student_wellbeing_v4')..['id'] = 'v4-main',
              {
                'id': 'hist-wellbeing',
                'type': 'full',
                'createdAt': '2026-10-05T00:00:00.000Z',
                'wellBeingStatus': 'At Risk',
              },
              {
                'id': 'hist-pattern',
                'type': 'full',
                'createdAt': '2026-09-05T00:00:00.000Z',
                'status': '',
                'responsePatternCode': 'someStrain',
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Result unavailable'), findsNothing);
      final badges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(
        badges.any(
          (b) =>
              b.presentation.tone == AdminSemanticTone.red &&
              b.presentation.label == 'Support may help',
        ),
        isTrue,
      );
      expect(
        badges.any(
          (b) =>
              b.presentation.tone == AdminSemanticTone.amber &&
              b.presentation.label == 'Some areas need attention',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'Workplace V4 missing domainSummaries and null domain status render accurate labels and consistent Insufficient responses badges',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-workplace',
            userLabel: 'Prof. Lee',
            repository: _Repository([
              {
                'id': 'wp-teaching',
                'schemaVersion': 'assessment_record_v4',
                'createdAt': '2026-11-18T00:00:00.000Z',
                'instrument': {'version': 'teaching_workplace_reflection_v4'},
                'result': {
                  'profileStatus': 'insufficientResponses',
                  'responseQuality': {
                    'answered': 25,
                    'presented': 50,
                    'confidence': 'limited',
                  },
                  'domainResults': [
                    {
                      'domainId': 'teachingWorkloadDemands',
                      'status': null,
                      'answeredCount': 3,
                      'presentedCount': 10,
                      'isScorable': false,
                    },
                    {
                      'domainId': 'teachingSupport',
                      'status': 'supported',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                    {
                      'domainId': 'nonTeachingWorkloadDemands',
                      'status': 'mostlySupported',
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                  ],
                },
                'interpretation': {
                  'userSummary': 'Workplace summary.',
                  'disclaimer': 'Disclaimer.',
                  'domainSummaries': const [],
                },
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Well-being area'), findsNothing);
      expect(find.text('Result unavailable'), findsNothing);
      expect(find.text('Teaching Workload & Role Demands'), findsNWidgets(2));
      expect(find.text('Collegial & Organizational Support'), findsNWidgets(2));
      expect(find.text('Workload & Role Demands'), findsNWidgets(2));

      final insufficientBadges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .where(
            (b) =>
                b.presentation.tone == AdminSemanticTone.neutral &&
                b.presentation.label == 'Insufficient responses',
          )
          .toList();
      // Header + _AreaPanel (null status) + _V4DomainReview (null status) + _AssessmentHistory
      expect(insufficientBadges, hasLength(4));
    },
  );

  testWidgets(
    '390x844 mobile viewport at 1.0x and 1.3x text scale renders legacy fallback and V4 history without layout exceptions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const longUnknownStatus =
          'unexpected_very_long_legacy_assessment_status_token_that_exceeds_narrow_mobile_width_cleanly';

      for (final scale in const [1.0, 1.3]) {
        // 1. Legacy fallback card (no interpretation) with wellBeingStatus: 'Needs Improvement'
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AdminAssessmentDetailScreen(
              userId: 'user-mobile-legacy-$scale',
              userLabel: 'Mobile Legacy',
              repository: _Repository([
                {
                  'id': 'legacy-mobile-$scale',
                  'type': 'full',
                  'createdAt': '2026-11-10T00:00:00.000Z',
                  'wellBeingStatus': 'Needs Improvement',
                },
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Legacy assessment'), findsOneWidget);
        expect(find.text('Some areas need attention'), findsOneWidget);

        // 2. Legacy fallback card with long unknown status string
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AdminAssessmentDetailScreen(
              userId: 'user-mobile-legacy-long-$scale',
              userLabel: 'Mobile Legacy Long',
              repository: _Repository([
                {
                  'id': 'legacy-mobile-long-$scale',
                  'type': 'full',
                  'createdAt': '2026-11-10T00:00:00.000Z',
                  'status': longUnknownStatus,
                },
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Legacy assessment'), findsOneWidget);

        // 3. V4 detail screen with _AssessmentHistory containing 'Some areas need attention',
        //    'Insufficient responses', and a long unknown status string.
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AdminAssessmentDetailScreen(
              userId: 'user-mobile-v4-$scale',
              userLabel: 'Mobile V4',
              assessmentId: 'v4-mobile-$scale',
              repository: _Repository([
                {
                  'id': 'v4-mobile-$scale',
                  'schemaVersion': 'assessment_record_v4',
                  'createdAt': '2026-11-20T00:00:00.000Z',
                  'instrument': {
                    'version': 'non_teaching_workplace_reflection_v4',
                  },
                  'result': {
                    'profileStatus': 'someAreasNeedAttention',
                    'responseQuality': {
                      'answered': 42,
                      'presented': 50,
                      'confidence': 'moderate',
                    },
                    'domainResults': [
                      {
                        'domainId': 'nonTeachingWorkloadDemands',
                        'status': 'someStrain',
                        'answeredCount': 10,
                        'presentedCount': 10,
                        'isScorable': true,
                      },
                    ],
                  },
                  'interpretation': {
                    'userSummary': 'Mobile summary.',
                    'disclaimer': 'Disclaimer.',
                    'domainSummaries': const [],
                  },
                },
                {
                  'id': 'hist-insufficient-$scale',
                  'schemaVersion': 'assessment_record_v4',
                  'createdAt': '2026-10-15T00:00:00.000Z',
                  'instrument': {'version': 'student_wellbeing_v4'},
                  'result': {'profileStatus': 'insufficientResponses'},
                },
                {
                  'id': 'hist-long-unknown-$scale',
                  'type': 'full',
                  'createdAt': '2026-09-10T00:00:00.000Z',
                  'status': longUnknownStatus,
                },
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Some areas need attention'), findsWidgets);
        expect(find.text('Insufficient responses'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'legacy non-V4 assessment with interpretation and no responsePatternCode never recalculates from score',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-legacy-score',
            userLabel: 'Legacy Score Test',
            assessmentId: 'legacy-interp-no-code',
            repository: _Repository([
              {
                'id': 'legacy-interp-no-code',
                'type': 'full',
                'createdAt': '2026-11-10T00:00:00.000Z',
                'status': 'Thriving',
                'overallScore': 95,
                'interpretation': {
                  'userSummary': 'Legacy summary.',
                  'domainResults': [
                    {
                      'domain': 'Academic',
                      'band': 'Thriving',
                      'score': 95,
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                  ],
                },
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Support may be useful'), findsNothing);
      expect(find.text('Support may help'), findsNothing);
      expect(find.textContaining('Support may be useful'), findsNothing);
      expect(find.text('Legacy summary.'), findsOneWidget);
      expect(find.text('Supported'), findsNWidgets(3));

      final badges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(badges, hasLength(2));
      for (final badge in badges) {
        expect(badge.presentation.tone, AdminSemanticTone.green);
        expect(badge.presentation.label, 'Supported');
      }

      // Missing all stored status fields with high numeric score must resolve to neutral Result unavailable (no score recalculation).
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminAssessmentDetailScreen(
            userId: 'user-legacy-no-status',
            userLabel: 'Legacy Missing Status',
            assessmentId: 'legacy-interp-missing-status',
            repository: _Repository([
              {
                'id': 'legacy-interp-missing-status',
                'type': 'full',
                'createdAt': '2026-11-10T00:00:00.000Z',
                'overallScore': 95,
                'interpretation': {
                  'domainResults': [
                    {
                      'domain': 'Academic',
                      'score': 95,
                      'answeredCount': 10,
                      'presentedCount': 10,
                      'isScorable': true,
                    },
                  ],
                },
              },
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Support may be useful'), findsNothing);
      expect(find.text('Support may help'), findsNothing);
      expect(find.textContaining('Support may be useful'), findsNothing);
      final missingBadges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(missingBadges, hasLength(2));
      for (final badge in missingBadges) {
        expect(badge.presentation.tone, AdminSemanticTone.neutral);
        expect(badge.presentation.label, 'Result unavailable');
      }
    },
  );
}

class _Repository extends AdminStatusRepository {
  _Repository(this.records);
  final List<Map<String, dynamic>> records;

  @override
  Future<List<Map<String, dynamic>>> fetchUserAssessments(
    String userId,
  ) async => records;
}

class _FutureRepo extends AdminStatusRepository {
  _FutureRepo(this.loader);
  final Future<List<Map<String, dynamic>>> Function() loader;

  @override
  Future<List<Map<String, dynamic>>> fetchUserAssessments(String userId) =>
      loader();
}

Map<String, dynamic> _v4Record(String version) => {
  'id': 'assessment-1',
  'schemaVersion': 'assessment_record_v4',
  'createdAt': '2026-09-29T00:00:00.000Z',
  'verificationStatus': 'Verified',
  'instrument': {'version': version, 'recallPeriodDays': 7},
  'result': {
    'profileStatus': 'generallySupported',
    'responseQuality': {'answered': 50, 'presented': 50, 'confidence': 'high'},
    'domainResults': [
      {
        'domainId': 'wellbeing',
        'status': 'generallySupported',
        'answeredCount': 10,
        'presentedCount': 10,
        'isScorable': true,
      },
    ],
  },
  'interpretation': {
    'userSummary': 'Stored profile summary.',
    'disclaimer': 'Follow-up guidance.',
    'overallResponseSummary': 'Removed overall response text.',
    'suggestedActions': ['Removed suggested action.'],
    'strengthInsights': ['Current strength.'],
    'focusInsights': ['Area to explore.'],
    'domainSummaries': [
      {
        'domainId': 'wellbeing',
        'domainLabel': 'Well-being',
        'focusInsight': 'A discussion guide source.',
      },
    ],
  },
};

String _displayName(String version) => switch (version) {
  'teaching_workplace_reflection_v4' =>
    'Teaching workplace well-being reflection',
  'non_teaching_workplace_reflection_v4' =>
    'Non-teaching workplace well-being reflection',
  _ => 'Student well-being reflection',
};
