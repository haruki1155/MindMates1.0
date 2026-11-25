import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_assessment_presentation.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_results_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _AssessmentStatusRepo extends AdminPortalRepository {
  _AssessmentStatusRepo(this.records);
  final List<AdminAssessmentRecord> records;

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream.value(records);
}

void main() {
  testWidgets(
    'Full and Quick assessments render semantic AdminStatusBadge with neutral fallback for unknown/missing',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _AssessmentStatusRepo([
        AdminAssessmentRecord(
          id: 'q1',
          userId: 'u1',
          type: 'quick',
          createdAt: DateTime(2026, 11, 20),
          status: 'generally_supported',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f1',
          userId: 'u1',
          type: 'full',
          createdAt: DateTime(2026, 11, 20),
          status: 'moderate',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f2',
          userId: 'u2',
          type: 'full',
          createdAt: DateTime(2026, 11, 19),
          status: 'severe',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f3',
          userId: 'u3',
          type: 'full',
          createdAt: DateTime(2026, 11, 18),
          status: '',
          role: 'Student',
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: repo,
                loadParticipants: (_) async => const {
                  'u1': AssessmentParticipantInfo(
                    userId: 'u1',
                    name: 'Alice',
                    role: 'Student',
                    college: 'College of Engineering',
                  ),
                  'u2': AssessmentParticipantInfo(
                    userId: 'u2',
                    name: 'Bob',
                    role: 'Student',
                    college: 'College of Engineering',
                  ),
                  'u3': AssessmentParticipantInfo(
                    userId: 'u3',
                    name: 'Cara',
                    role: 'Student',
                    college: 'College of Engineering',
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Quick tab shows AdminStatusBadge.
      expect(find.byType(AdminStatusBadge), findsOneWidget);
      expect(find.text('Supported'), findsOneWidget);

      // Switch to Full Assessment tab.
      await tester.tap(find.text('Full Assessment'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminStatusBadge), findsNWidgets(3));
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('Severe'), findsOneWidget);
      expect(find.text('Result unavailable'), findsOneWidget);
    },
  );

  testWidgets(
    'Assessments page renders cleanly at 390, 768, and 1280 px with status badges on Quick and Full tabs',
    (tester) async {
      addTearDown(tester.view.reset);

      final repo = _AssessmentStatusRepo([
        AdminAssessmentRecord(
          id: 'q1',
          userId: 'u1',
          type: 'quick',
          createdAt: DateTime(2026, 11, 20),
          status: 'generally_supported',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f1',
          userId: 'u1',
          type: 'full',
          createdAt: DateTime(2026, 11, 20),
          status: 'moderate',
          role: 'Student',
        ),
        AdminAssessmentRecord(
          id: 'f2',
          userId: 'u2',
          type: 'full',
          createdAt: DateTime(2026, 11, 19),
          status: 'severe',
          role: 'Student',
        ),
      ]);

      Future<Map<String, AssessmentParticipantInfo>> loadParticipants(
        Iterable<String> _,
      ) async => const {
        'u1': AssessmentParticipantInfo(
          userId: 'u1',
          name: 'Alice Student',
          role: 'Student',
          college: 'College of Engineering',
        ),
        'u2': AssessmentParticipantInfo(
          userId: 'u2',
          name: 'Bob Student',
          role: 'Student',
          college: 'College of Engineering',
        ),
      };

      for (final width in const [390.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminAssessmentResultsPage(
                  key: ValueKey(width),
                  repository: repo,
                  loadParticipants: loadParticipants,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'quick assessments overflow at $width',
        );
        expect(find.byType(AdminStatusBadge), findsOneWidget);
        expect(find.text('Supported'), findsOneWidget);

        await tester.tap(find.text('Full Assessment'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'full assessments overflow at $width',
        );
        expect(find.byType(AdminStatusBadge), findsNWidgets(2));
        expect(find.text('Moderate'), findsOneWidget);
        expect(find.text('Severe'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'Full Assessment V4 sentences, profileStatus, V3 legacy, and no-recalculation preserve semantic badge tones, colors, and icons',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _AssessmentStatusRepo([
        AdminAssessmentRecord.fromJson({
          'id': 'q-low',
          'userId': 'u1',
          'type': 'quick',
          'createdAt': '2026-11-20T00:00:00.000Z',
          'overallLevel': 'low',
          'role': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'q-vhigh',
          'userId': 'u2',
          'type': 'quick',
          'createdAt': '2026-11-20T00:00:00.000Z',
          'overallLevel': 'veryHigh',
          'role': 'student',
        }),
        // V4 with score=95 but profileStatus=generallySupported (must NOT recalculate)
        AdminAssessmentRecord.fromJson({
          'id': 'f-v4-supported',
          'userId': 'u1',
          'assessmentKind': 'full',
          'createdAt': '2026-11-20T00:00:00.000Z',
          'score': 95,
          'status': 'Well-being appears generally supported.',
          'result': {'profileStatus': 'generallySupported'},
          'populationRole': 'student',
        }),
        // V4 sentence-only (no result.profileStatus)
        AdminAssessmentRecord.fromJson({
          'id': 'f-v4-mostly',
          'userId': 'u2',
          'assessmentKind': 'full',
          'createdAt': '2026-11-19T00:00:00.000Z',
          'status': 'Mostly supported, with an area to explore.',
          'populationRole': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-v4-attention',
          'userId': 'u3',
          'assessmentKind': 'full',
          'createdAt': '2026-11-18T00:00:00.000Z',
          'status': 'Some areas may benefit from attention.',
          'populationRole': 'teaching',
        }),
        // V4 with score=2 but status=Support may be helpful right now. (must NOT recalculate)
        AdminAssessmentRecord.fromJson({
          'id': 'f-v4-help',
          'userId': 'u4',
          'assessmentKind': 'full',
          'createdAt': '2026-11-17T00:00:00.000Z',
          'score': 2,
          'status': 'Support may be helpful right now.',
          'populationRole': 'nonTeaching',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-v4-insufficient',
          'userId': 'u5',
          'assessmentKind': 'full',
          'createdAt': '2026-11-16T00:00:00.000Z',
          'status': 'More responses are needed for a complete profile.',
          'populationRole': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-v3-needs',
          'userId': 'u6',
          'type': 'full',
          'createdAt': '2026-11-15T00:00:00.000Z',
          'status': 'Needs Improvement',
          'role': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-unknown',
          'userId': 'u7',
          'type': 'full',
          'createdAt': '2026-11-14T00:00:00.000Z',
          'status': 'legacy_unmapped_band',
          'role': 'student',
        }),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: repo,
                loadParticipants: (_) async => const {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final quickBadges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(quickBadges, hasLength(2));
      expect(quickBadges[0].presentation.tone, AdminSemanticTone.green);
      expect(quickBadges[0].presentation.label, 'Low');
      expect(quickBadges[0].presentation.backgroundColor, AdminColors.greenBg);
      expect(quickBadges[0].presentation.icon, Icons.check_circle_outline);

      expect(quickBadges[1].presentation.tone, AdminSemanticTone.red);
      expect(quickBadges[1].presentation.label, 'Very high');
      expect(quickBadges[1].presentation.backgroundColor, AdminColors.redBg);
      expect(quickBadges[1].presentation.icon, Icons.priority_high_rounded);

      await tester.tap(find.text('Full Assessment'));
      await tester.pumpAndSettle();

      final fullBadges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(fullBadges, hasLength(7));

      expect(fullBadges[0].presentation.tone, AdminSemanticTone.green);
      expect(fullBadges[0].presentation.label, 'Supported');
      expect(fullBadges[0].presentation.backgroundColor, AdminColors.greenBg);
      expect(fullBadges[0].presentation.foregroundColor, AdminColors.greenFg);
      expect(fullBadges[0].presentation.icon, Icons.check_circle_outline);

      expect(fullBadges[1].presentation.tone, AdminSemanticTone.blue);
      expect(fullBadges[1].presentation.label, 'Mostly supported');
      expect(fullBadges[1].presentation.backgroundColor, AdminColors.blueBg);
      expect(fullBadges[1].presentation.foregroundColor, AdminColors.blueFg);
      expect(fullBadges[1].presentation.icon, Icons.info_outline);

      expect(fullBadges[2].presentation.tone, AdminSemanticTone.amber);
      expect(fullBadges[2].presentation.label, 'Some areas need attention');
      expect(fullBadges[2].presentation.backgroundColor, AdminColors.amberBg);
      expect(fullBadges[2].presentation.foregroundColor, AdminColors.amberFg);
      expect(fullBadges[2].presentation.icon, Icons.warning_amber_outlined);

      expect(fullBadges[3].presentation.tone, AdminSemanticTone.red);
      expect(fullBadges[3].presentation.label, 'Support may help');
      expect(fullBadges[3].presentation.backgroundColor, AdminColors.redBg);
      expect(fullBadges[3].presentation.foregroundColor, AdminColors.redFg);
      expect(fullBadges[3].presentation.icon, Icons.priority_high_rounded);

      expect(fullBadges[4].presentation.tone, AdminSemanticTone.neutral);
      expect(fullBadges[4].presentation.label, 'Insufficient responses');
      expect(fullBadges[4].presentation.backgroundColor, AdminColors.neutralBg);
      expect(fullBadges[4].presentation.icon, Icons.help_outline);

      expect(fullBadges[5].presentation.tone, AdminSemanticTone.amber);
      expect(fullBadges[5].presentation.label, 'Some areas need attention');
      expect(fullBadges[5].presentation.backgroundColor, AdminColors.amberBg);

      expect(fullBadges[6].presentation.tone, AdminSemanticTone.neutral);
      expect(fullBadges[6].presentation.label, 'legacy unmapped band');
      expect(fullBadges[6].presentation.backgroundColor, AdminColors.neutralBg);
      expect(fullBadges[6].presentation.icon, Icons.help_outline);
    },
  );
}
