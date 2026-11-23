import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_assessment_presentation.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_results_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
import 'package:mind_mates/repositories/admin_status_repository.dart';

class _FakeRepository extends AdminPortalRepository {
  _FakeRepository([List<AdminAssessmentRecord>? records])
    : _records =
          records ??
          [
            AdminAssessmentRecord(
              id: 'quick-1',
              userId: 'u1',
              type: 'quick',
              createdAt: DateTime(2026, 11, 13),
              status: 'low',
              role: 'student',
            ),
            AdminAssessmentRecord(
              id: 'full-1',
              userId: 'u1',
              type: 'full',
              createdAt: DateTime(2026, 11, 13),
              status: 'someStrain',
              role: 'student',
            ),
          ];

  final List<AdminAssessmentRecord> _records;

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream.value(_records);
}

void main() {
  testWidgets(
    'subnavigation, whole-row selection and no view/archive buttons',
    (tester) async {
      String? selectedId;
      String? selectedName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: _FakeRepository(),
                onAssessmentOpen: (record, name) {
                  selectedId = record.id;
                  selectedName = name;
                },
                loadParticipants: (ids) async => {
                  'u1': const AssessmentParticipantInfo(
                    userId: 'u1',
                    name: 'Sample Student',
                    role: 'student',
                    college: 'CITE',
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quick Assessment'), findsWidgets);
      expect(find.text('Sample Student'), findsOneWidget);
      expect(find.byTooltip('View assessment results'), findsNothing);
      expect(find.byTooltip('Archive assessment'), findsNothing);
      await tester.ensureVisible(find.text('Sample Student'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample Student'));
      await tester.pump();
      expect(selectedId, 'quick-1');
      expect(selectedName, 'Sample Student');
      expect(find.text('Actions'), findsNothing);
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Full Assessment'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();
      expect(find.text('Sample Student'), findsOneWidget);
      expect(find.text('Some areas need attention'), findsOneWidget);
      expect(find.text('Low'), findsNothing);
      await tester.ensureVisible(find.text('Sample Student'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample Student'));
      await tester.pump();
      expect(selectedId, 'full-1');
    },
  );

  testWidgets(
    'small participant groups (1 and 4) show 1–4 participants without <5, while 5 and 8 show counts and bars',
    (tester) async {
      final records = <AdminAssessmentRecord>[];
      final participants = <String, AssessmentParticipantInfo>{};

      void addGroup({
        required String prefix,
        required int count,
        required String role,
        required String college,
      }) {
        for (var i = 1; i <= count; i++) {
          final uid = '$prefix-$i';
          records.add(
            AdminAssessmentRecord(
              id: 'rec-$uid',
              userId: uid,
              type: 'quick',
              createdAt: DateTime(2026, 11, 13),
              status: 'low',
              role: role,
            ),
          );
          participants[uid] = AssessmentParticipantInfo(
            userId: uid,
            name: 'Participant $uid',
            role: role,
            college: college,
          );
        }
      }

      // Students by college: counts of 1, 4, 5, and 8
      addGroup(prefix: 'cas', count: 1, role: 'student', college: 'CAS');
      addGroup(prefix: 'cite', count: 4, role: 'student', college: 'CITE');
      addGroup(prefix: 'cbaa', count: 5, role: 'student', college: 'CBAA');
      addGroup(prefix: 'chm', count: 8, role: 'student', college: 'CHM');

      // Employees by role: counts of 4 and 5
      addGroup(prefix: 'teach', count: 4, role: 'teaching', college: 'CAS');
      addGroup(
        prefix: 'nonteach',
        count: 5,
        role: 'nonteaching',
        college: 'Unassigned',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: _FakeRepository(records),
                onAssessmentOpen: (_, _) {},
                loadParticipants: (_) async => participants,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Updated privacy range explanation.
      expect(
        find.text(
          'Each person is counted once. For privacy, groups with fewer than 5 people are shown as a range.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Suppressed'), findsNothing);
      expect(find.text('<5'), findsNothing);

      // 3 small groups (CAS=1, CITE=4, Teaching=4) show "1–4 participants".
      expect(find.text('1–4 participants'), findsNWidgets(3));

      // Exact small counts and tooltips must never be revealed.
      expect(find.byTooltip('1 assessed participants'), findsNothing);
      expect(find.byTooltip('4 assessed participants'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('4'), findsNothing);

      // Groups >= 5 (CBAA=5, CHM=8, Non-Teaching=5) display progress bars, tooltips, and exact counts.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      expect(find.byTooltip('5 assessed participants'), findsNWidgets(2));
      expect(find.byTooltip('8 assessed participants'), findsOneWidget);
      expect(find.text('5'), findsNWidgets(2));
      expect(find.text('8'), findsOneWidget);
    },
  );

  testWidgets(
    'normalizes V4 status filter options, resets stale filters on tab switch, and pushes detail screen cleanly',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;

      final records = [
        AdminAssessmentRecord.fromJson({
          'id': 'q-1',
          'userId': 'u1',
          'type': 'quick',
          'createdAt': '2026-11-20T00:00:00.000Z',
          'overallLevel': 'low',
          'role': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-supported-key',
          'userId': 'u1',
          'assessmentKind': 'full',
          'createdAt': '2026-11-20T00:00:00.000Z',
          'status': 'Well-being appears generally supported.',
          'result': {'profileStatus': 'generallySupported'},
          'populationRole': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-supported-sentence',
          'userId': 'u2',
          'assessmentKind': 'full',
          'createdAt': '2026-11-19T00:00:00.000Z',
          'status': 'Well-being appears generally supported.',
          'populationRole': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-attention',
          'userId': 'u3',
          'assessmentKind': 'full',
          'createdAt': '2026-11-18T00:00:00.000Z',
          'status': 'Some areas may benefit from attention.',
          'populationRole': 'student',
        }),
      ];

      final statusRepo = _FakeStatusRepo({
        'u3': [
          {
            'id': 'f-attention',
            'schemaVersion': 'assessment_record_v4',
            'createdAt': '2026-11-18T00:00:00.000Z',
            'status': 'Some areas may benefit from attention.',
            'instrument': {'version': 'student_wellbeing_v4'},
            'result': {
              'profileStatus': 'someAreasNeedAttention',
              'responseQuality': {
                'answered': 50,
                'presented': 50,
                'confidence': 'high',
              },
              'domainResults': [
                {
                  'domainId': 'academic',
                  'status': 'someStrain',
                  'answeredCount': 10,
                  'presentedCount': 10,
                  'isScorable': true,
                },
              ],
            },
            'interpretation': {
              'userSummary': 'Attention summary.',
              'disclaimer': 'Disclaimer.',
              'domainSummaries': [
                {'domainId': 'academic', 'domainLabel': 'Academic'},
              ],
            },
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: _FakeRepository(records),
                statusRepository: statusRepo,
                loadParticipants: (_) async => const {
                  'u1': AssessmentParticipantInfo(
                    userId: 'u1',
                    name: 'Alice One',
                    role: 'student',
                    college: 'CITE',
                  ),
                  'u2': AssessmentParticipantInfo(
                    userId: 'u2',
                    name: 'Bob Two',
                    role: 'student',
                    college: 'CITE',
                  ),
                  'u3': AssessmentParticipantInfo(
                    userId: 'u3',
                    name: 'Cara Three',
                    role: 'student',
                    college: 'CAS',
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Full Assessment tab.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();
      expect(find.text('3 assessment records'), findsOneWidget);

      // Open Status dropdown and verify normalized options (Supported deduplicated, plus Some areas need attention).
      final statusField = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.key == const ValueKey('Status:All Statuses'),
      );
      await tester.tap(statusField);
      await tester.pumpAndSettle();

      // Raw sentence should NOT appear in normalized dropdown options.
      expect(
        find.text('Well-being appears generally supported.'),
        findsNothing,
      );
      expect(find.text('Supported').last, findsOneWidget);
      expect(find.text('Some areas need attention').last, findsOneWidget);

      // Filter by 'Some areas need attention'.
      await tester.tap(find.text('Some areas need attention').last);
      await tester.pumpAndSettle();

      expect(find.text('1 assessment records'), findsOneWidget);
      expect(find.text('Cara Three'), findsOneWidget);
      expect(find.text('Alice One'), findsNothing);

      // Switching back to Quick Assessment must reset stale _status filter so Quick rows remain visible.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Quick Assessment'));
      await tester.pumpAndSettle();
      expect(find.text('1 assessment records'), findsOneWidget);
      expect(find.text('Alice One'), findsOneWidget);

      // Switch to Full again, select 'Supported', verify both key-backed and sentence-only records appear.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();
      expect(find.text('3 assessment records'), findsOneWidget);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.key == const ValueKey('Status:All Statuses'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supported').last);
      await tester.pumpAndSettle();
      expect(find.text('2 assessment records'), findsOneWidget);
      expect(find.text('Alice One'), findsOneWidget);
      expect(find.text('Bob Two'), findsOneWidget);

      // Reset status to All Statuses, tap Cara Three to open detail screen cleanly via statusRepository.
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.key == const ValueKey('Status:Supported'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Statuses').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Cara Three'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cara Three'));
      await tester.pumpAndSettle();

      expect(find.text('Assessment review'), findsOneWidget);
      final detailBadges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(detailBadges, isNotEmpty);
      expect(
        detailBadges.every(
          (b) => b.presentation.tone == AdminSemanticTone.amber,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'long Status filter selection renders without overflow at 390, 768, and 1280 px',
    (tester) async {
      addTearDown(tester.view.reset);

      final repo = _FakeRepository([
        AdminAssessmentRecord.fromJson({
          'id': 'f-attention',
          'userId': 'u1',
          'assessmentKind': 'full',
          'createdAt': '2026-11-18T00:00:00.000Z',
          'status': 'Some areas may benefit from attention.',
          'populationRole': 'student',
        }),
      ]);

      for (final width in const [390.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminAssessmentResultsPage(
                  key: ValueKey('results-$width'),
                  repository: repo,
                  loadParticipants: (_) async => const {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Full Assessment'),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is DropdownButtonFormField<String> &&
                widget.key == const ValueKey('Status:All Statuses'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Some areas need attention').last);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'no layout overflow at $width',
        );
        expect(find.text('1 assessment records'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'live stream update removing selected Status option falls back to All Statuses and displays updated records',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;

      final controller = StreamController<List<AdminAssessmentRecord>>();
      addTearDown(controller.close);
      final repo = _StreamRepository(controller.stream);

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
                    name: 'Cara Three',
                    role: 'student',
                    college: 'CAS',
                  ),
                  'u2': AssessmentParticipantInfo(
                    userId: 'u2',
                    name: 'Alice One',
                    role: 'student',
                    college: 'CITE',
                  ),
                },
              ),
            ),
          ),
        ),
      );

      controller.add([
        AdminAssessmentRecord.fromJson({
          'id': 'f-attention',
          'userId': 'u1',
          'assessmentKind': 'full',
          'createdAt': '2026-11-18T00:00:00.000Z',
          'status': 'Some areas may benefit from attention.',
          'populationRole': 'student',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'f-supported',
          'userId': 'u2',
          'assessmentKind': 'full',
          'createdAt': '2026-11-19T00:00:00.000Z',
          'result': {'profileStatus': 'generallySupported'},
          'populationRole': 'student',
        }),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.key == const ValueKey('Status:All Statuses'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Some areas need attention').last);
      await tester.pumpAndSettle();

      expect(find.text('1 assessment records'), findsOneWidget);
      expect(find.text('Cara Three'), findsOneWidget);
      expect(find.text('Alice One'), findsNothing);

      // Stream emits updated list where 'Some areas need attention' no longer exists.
      controller.add([
        AdminAssessmentRecord.fromJson({
          'id': 'f-supported',
          'userId': 'u2',
          'assessmentKind': 'full',
          'createdAt': '2026-11-19T00:00:00.000Z',
          'result': {'profileStatus': 'generallySupported'},
          'populationRole': 'student',
        }),
      ]);
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.key == const ValueKey('Status:All Statuses'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 assessment records'), findsOneWidget);
      expect(find.text('Alice One'), findsOneWidget);
      expect(
        find.text('No assessment records match your filters.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'dropdown filters exclude sentinel strings when records contain All Statuses, All Roles, or All Years',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;

      final records = [
        AdminAssessmentRecord.fromJson({
          'id': 'sentinel-quick',
          'userId': 'u-sentinel',
          'type': 'quick',
          'createdAt': '2026-11-20T00:00:00.000Z',
          'status': 'All Statuses',
          'role': 'All Roles',
          'year': 'All Years',
        }),
        AdminAssessmentRecord.fromJson({
          'id': 'sentinel-full',
          'userId': 'u-sentinel',
          'type': 'full',
          'createdAt': '2026-11-20T00:00:00.000Z',
          'status': 'All Statuses',
          'role': 'All Roles',
          'year': 'All Years',
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminAssessmentResultsPage(
                repository: _FakeRepository(records),
                loadParticipants: (_) async => const {
                  'u-sentinel': AssessmentParticipantInfo(
                    userId: 'u-sentinel',
                    name: 'Sentinel User',
                    role: 'All Roles',
                    college: 'CITE',
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1 assessment records'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1 assessment records'), findsOneWidget);
    },
  );
}

class _StreamRepository extends AdminPortalRepository {
  _StreamRepository(this._stream);
  final Stream<List<AdminAssessmentRecord>> _stream;

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() => _stream;
}

class _FakeStatusRepo extends AdminStatusRepository {
  _FakeStatusRepo(this.recordsByUser);
  final Map<String, List<Map<String, dynamic>>> recordsByUser;

  @override
  Future<List<Map<String, dynamic>>> fetchUserAssessments(
    String userId,
  ) async => recordsByUser[userId] ?? const [];
}
