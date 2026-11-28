import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/features/admin/screens/report_generation_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
import 'package:mind_mates/services/admin_report_pdf_service.dart';

class _EmotionalReportFakeRepository extends AdminPortalRepository {
  _EmotionalReportFakeRepository({
    this.role = AccessRole.admin,
    this.status = 'ready',
  });

  final AccessRole role;
  String status;
  final calls = <Map<String, Object?>>[];

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => role == AccessRole.admin;

  @override
  Future<AdminReportAnalytics> fetchEmotionalReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
    String emotionalSource = 'all',
  }) async => _buildReport(
    userCategory: userCategory,
    appointmentDepartment: appointmentDepartment,
    schoolYear: schoolYear,
    startDate: startDate,
    endDate: endDate,
    emotionalSource: emotionalSource,
  );

  @override
  Future<AdminReportAnalytics> fetchReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
  }) async => _buildReport(
    userCategory: userCategory,
    appointmentDepartment: appointmentDepartment,
    schoolYear: schoolYear,
    startDate: startDate,
    endDate: endDate,
    emotionalSource: 'all',
  );

  AdminReportAnalytics _buildReport({
    required String userCategory,
    required String appointmentDepartment,
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
    required String emotionalSource,
  }) {
    calls.add({
      'userCategory': userCategory,
      'appointmentDepartment': appointmentDepartment,
      'schoolYear': schoolYear ?? '2026-2027',
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'emotionalSource': emotionalSource,
    });
    return AdminReportAnalytics.fromJson({
      'generatedAt': '2026-11-16T00:00:00Z',
      'population': {
        'schoolYear': schoolYear ?? '2026-2027',
        'configured': true,
        'status': schoolYear == '2025-2026' ? 'closed' : 'current',
        'departments': ['College of Nursing', 'College of Engineering'],
        'populations': {
          'College of Nursing': 100,
          'College of Engineering': 100,
        },
        'totalPopulation': 200,
        'years': [
          {
            'schoolYear': '2026-2027',
            'startDate': '2026-06-01',
            'endDate': '2027-05-31',
            'status': 'current',
          },
          {
            'schoolYear': '2025-2026',
            'startDate': '2025-06-01',
            'endDate': '2026-05-31',
            'status': 'closed',
          },
        ],
      },
      'users': {
        'scopeKey': userCategory,
        'scopeLabel': userCategory == 'student'
            ? 'Students'
            : 'Whole app-user population',
        'overallActivePercentage': 55.0,
        'categoryOptions': [
          {'key': 'student', 'label': 'Students'},
          {'key': 'teaching', 'label': 'Teaching personnel'},
        ],
        'categories': [
          {
            'key': 'student',
            'label': 'Students',
            'populationPercentage': 80,
            'activePercentage': 60,
          },
        ],
      },
      'appointments': {
        'totalAppointments': 12,
        'uniqueStudentsServed': 10,
        'departmentOptions': [
          {'key': 'college of nursing', 'label': 'College of Nursing'},
        ],
      },
      'emotionalActivity': {
        'status': status,
        'suppressed': status == 'suppressed',
        'suppressionThreshold': 10,
        'suppressionReason': status == 'suppressed'
            ? 'Suppressed to protect privacy: fewer than 10 unique participants matched the active filters.'
            : null,
        'sourceScopeKey': emotionalSource,
        'sourceScopeLabel': emotionalSource == 'mood'
            ? 'Mood check-ins only'
            : emotionalSource == 'assessment'
            ? 'Well-being assessments only'
            : 'All approved sources (mood check-ins & assessments)',
        'schoolYear': schoolYear ?? '2026-2027',
        'dateRangeLabel': 'Academic year ${schoolYear ?? '2026-2027'}',
        'participationRate': status == 'ready' ? 25.0 : null,
        'appUserCohortShare': status == 'ready' ? 30.0 : null,
        'dominantValenceLabel': status == 'ready'
            ? 'Positive (Levels 4-5)'
            : null,
        'hasMixedCategories': status == 'ready',
        'moodCheckInShare': status == 'ready' && emotionalSource == 'all'
            ? 62.5
            : null,
        'assessmentShare': status == 'ready' && emotionalSource == 'all'
            ? 37.5
            : null,
        'departmentOptions': [
          {'key': 'college of nursing', 'label': 'College of Nursing'},
          {'key': 'college of engineering', 'label': 'College of Engineering'},
        ],
        'valenceBreakdown': status == 'ready'
            ? [
                {
                  'key': 'positive',
                  'label': 'Positive (Levels 4-5)',
                  'percentage': 70.0,
                  'suppressed': false,
                },
                {
                  'key': 'neutral',
                  'label': 'Steady / Tired (Level 3)',
                  'percentage': null,
                  'suppressed': true,
                },
                {
                  'key': 'strained',
                  'label': 'Strained / Distressed (Levels 1-2)',
                  'percentage': null,
                  'suppressed': true,
                },
              ]
            : const [],
        'moodBreakdown': status == 'ready' && emotionalSource != 'assessment'
            ? [
                {
                  'key': 'great',
                  'label': 'Great',
                  'percentage': 60.0,
                  'suppressed': false,
                },
                {
                  'key': 'tired',
                  'label': 'Tired',
                  'percentage': null,
                  'suppressed': true,
                },
              ]
            : const [],
        'assessmentBreakdown': status == 'ready' && emotionalSource != 'mood'
            ? [
                {
                  'key': 'supported',
                  'label': 'Generally Supported',
                  'percentage': 75.0,
                  'suppressed': false,
                },
              ]
            : const [],
        'periodTrends': status == 'ready'
            ? [
                {
                  'key': '2026-09',
                  'label': 'Sep 2026',
                  'percentage': 60.0,
                  'suppressed': false,
                },
                {
                  'key': '2026-10',
                  'label': 'Oct 2026',
                  'percentage': null,
                  'suppressed': true,
                },
              ]
            : const [],
        'weeklyTrends': status == 'ready'
            ? [
                {
                  'weekKey': '2026-11-09',
                  'label': 'Nov 9-15, 2026',
                  'suppressed': false,
                  'activityShare': 45.0,
                  'averageMoodLevel': 3.85,
                  'dominantMoodKey': 'great',
                  'dominantMoodLabel': 'Great',
                  'strainedShare': 24.0,
                  'valenceBreakdown': [
                    {
                      'key': 'positive',
                      'label': 'Positive (Levels 4-5)',
                      'percentage': 61.0,
                      'suppressed': false,
                    },
                    {
                      'key': 'neutral',
                      'label': 'Steady / Tired (Level 3)',
                      'percentage': 15.0,
                      'suppressed': false,
                    },
                    {
                      'key': 'strained',
                      'label': 'Strained / Distressed (Levels 1-2)',
                      'percentage': 24.0,
                      'suppressed': false,
                    },
                  ],
                  'moodBreakdown': [
                    {
                      'key': 'great',
                      'label': 'Great',
                      'percentage': 61.0,
                      'suppressed': false,
                    },
                    {
                      'key': 'stressed',
                      'label': 'Stressed',
                      'percentage': 24.0,
                      'suppressed': false,
                    },
                  ],
                },
                {
                  'weekKey': '2026-11-16',
                  'label': 'Nov 16-22, 2026',
                  'suppressed': false,
                  'activityShare': 55.0,
                  'averageMoodLevel': 3.2,
                  'dominantMoodKey': 'stressed',
                  'dominantMoodLabel': 'Stressed',
                  'strainedShare': 42.0,
                  'valenceBreakdown': [
                    {
                      'key': 'positive',
                      'label': 'Positive (Levels 4-5)',
                      'percentage': 44.0,
                      'suppressed': false,
                    },
                    {
                      'key': 'neutral',
                      'label': 'Steady / Tired (Level 3)',
                      'percentage': 14.0,
                      'suppressed': false,
                    },
                    {
                      'key': 'strained',
                      'label': 'Strained / Distressed (Levels 1-2)',
                      'percentage': 42.0,
                      'suppressed': false,
                    },
                  ],
                  'moodBreakdown': [
                    {
                      'key': 'stressed',
                      'label': 'Stressed',
                      'percentage': 42.0,
                      'suppressed': false,
                    },
                    {
                      'key': 'great',
                      'label': 'Great',
                      'percentage': 44.0,
                      'suppressed': false,
                    },
                  ],
                },
              ]
            : const [],
        'elevatedMoodSignals': status == 'ready'
            ? [
                {
                  'key': 'stressed',
                  'label': 'Stressed',
                  'severity': 'elevated',
                  'currentWeekLabel': 'Nov 16-22, 2026',
                  'baselineLabel': 'Prior week (Nov 9-15, 2026)',
                  'currentPercentage': 42.0,
                  'baselinePercentage': 24.0,
                  'deltaPoints': 18.0,
                  'weekOverWeekDelta': 18.0,
                  'summary':
                      'Stressed is elevated at 42.0% in Nov 16-22, 2026 (+18.0 pp vs. prior week of 24.0%).',
                },
              ]
            : const [],
        'weekdayBreakdown': status == 'ready'
            ? [
                {
                  'key': '1_mon',
                  'label': 'Mon',
                  'activityShare': 55.0,
                  'strainedShare': 40.0,
                  'dominantMoodLabel': 'Stressed',
                  'suppressed': false,
                },
                {
                  'key': '3_wed',
                  'label': 'Wed',
                  'activityShare': 45.0,
                  'strainedShare': 20.0,
                  'dominantMoodLabel': 'Great',
                  'suppressed': false,
                },
              ]
            : const [],
        'moodEngagement': status == 'ready' && emotionalSource != 'assessment'
            ? {
                'averageMoodLevel': 3.52,
                'avgCheckInsPerParticipant': 3.4,
                'repeatParticipantRate': 72.0,
                'entryMethodBreakdown': [
                  {
                    'key': 'manual',
                    'label': 'Manual check-in',
                    'percentage': 74.0,
                    'suppressed': false,
                  },
                  {
                    'key': 'expression_assisted',
                    'label': 'Expression-assisted',
                    'percentage': 26.0,
                    'suppressed': false,
                  },
                ],
              }
            : null,
        'actionableInsights': status == 'ready'
            ? [
                'Stressed is elevated at 42.0% in Nov 16-22, 2026 (+18.0 pp vs. prior week of 24.0%).',
                'Aggregate wellness indicators reflect self-reported patterns (n >= 10) and are intended for preventive campus planning, not clinical diagnosis.',
              ]
            : const [],
        'departmentCoverageNote':
            'Includes all app-user colleges/departments within your access scope.',
      },
    });
  }

  @override
  Future<List<ImportedWalkInFile>> listWalkInImports() async => [];
}

void main() {
  testWidgets(
    'Emotional activity tab supports source, year, population and department filters',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _EmotionalReportFakeRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: ReportGenerationPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Emotional activity'));
      await tester.pumpAndSettle();

      expect(
        find.text('Emotional activity results · 2026-2027'),
        findsOneWidget,
      );
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('Positive (Levels 4-5)'), findsWidgets);
      expect(find.textContaining('Suppressed (n < 10)'), findsWidgets);
      expect(find.text('Generally Supported'), findsOneWidget);
      expect(
        find.byKey(const Key('emotional_elevation_watchlist')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('emotional_actionable_insights')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('emotional_chart_mode_toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('emotional_weekly_trends')), findsOneWidget);
      expect(
        find.byKey(const Key('emotional_weekday_pattern')),
        findsOneWidget,
      );
      expect(find.text('Log your Mood entry methods'), findsOneWidget);

      final valenceChip = find.widgetWithText(ChoiceChip, 'Valence');
      await tester.ensureVisible(valenceChip);
      await tester.tap(valenceChip);
      await tester.pumpAndSettle();
      expect(find.text('Emotional pattern distribution'), findsOneWidget);
      final moodsChip = find.widgetWithText(ChoiceChip, '7 Moods');
      await tester.ensureVisible(moodsChip);
      await tester.tap(moodsChip);
      await tester.pumpAndSettle();
      expect(find.text('Log your Mood distribution'), findsOneWidget);

      await tester.ensureVisible(find.text('Mood check-ins'));
      await tester.tap(find.text('Mood check-ins'));
      await tester.pumpAndSettle();
      expect(repo.calls.last['emotionalSource'], 'mood');

      await tester.ensureVisible(find.text('Students'));
      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();
      expect(repo.calls.last['userCategory'], 'student');
    },
  );

  testWidgets('renders suppressed and no_data states clearly without metrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final suppressedRepo = _EmotionalReportFakeRepository(status: 'suppressed');
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: ReportGenerationPage(
            key: const ValueKey('suppressed'),
            repository: suppressedRepo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emotional activity'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Suppressed to protect privacy'), findsWidgets);
    expect(find.text('25%'), findsNothing);

    final emptyRepo = _EmotionalReportFakeRepository(status: 'no_data');
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: ReportGenerationPage(
            key: const ValueKey('empty'),
            repository: emptyRepo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emotional activity'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No emotional activity data available'),
      findsOneWidget,
    );
  });

  testWidgets('lays out Emotional activity cleanly at 360px and 1280px', (
    tester,
  ) async {
    for (final width in [360.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: ReportGenerationPage(
              repository: _EmotionalReportFakeRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emotional activity'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('blocks non-clinical staff from viewing Reports', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: ReportGenerationPage(
            repository: _EmotionalReportFakeRepository(
              role: AccessRole.portalStaff,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Counselor or administrator access is required.'),
      findsOneWidget,
    );
  });

  test(
    'AdminReportPdfService builds PDF for Emotional activity ready and suppressed states',
    () async {
      final repo = _EmotionalReportFakeRepository();
      final readyReport = await repo.fetchEmotionalReportAnalytics(
        emotionalSource: 'all',
      );
      final readyBytes = await AdminReportPdfService.build(
        report: readyReport,
        reportType: AdminReportType.emotionalActivity,
        chartType: ReportChartType.bar,
      );
      expect(readyBytes.length, greaterThan(1000));

      repo.status = 'suppressed';
      final suppressedReport = await repo.fetchEmotionalReportAnalytics(
        emotionalSource: 'mood',
      );
      final suppressedBytes = await AdminReportPdfService.build(
        report: suppressedReport,
        reportType: AdminReportType.emotionalActivity,
        chartType: ReportChartType.pie,
      );
      expect(suppressedBytes.length, greaterThan(1000));

      final allCellSuppressed = AdminReportAnalytics.fromJson({
        'generatedAt': '2026-11-16T00:00:00Z',
        'population': {
          'schoolYear': '2026-2027',
          'configured': true,
          'departments': ['College of Nursing'],
          'populations': {'College of Nursing': 100},
          'totalPopulation': 100,
          'years': [],
        },
        'emotionalActivity': {
          'status': 'ready',
          'suppressed': false,
          'suppressionThreshold': 10,
          'valenceBreakdown': [
            {
              'key': 'positive',
              'label': 'Positive (Levels 4-5)',
              'percentage': null,
              'suppressed': true,
            },
          ],
        },
      });
      final cellSuppressedBytes = await AdminReportPdfService.build(
        report: allCellSuppressed,
        reportType: AdminReportType.emotionalActivity,
        chartType: ReportChartType.pie,
      );
      expect(cellSuppressedBytes.length, greaterThan(1000));
    },
  );
}
