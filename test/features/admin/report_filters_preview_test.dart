import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/features/admin/screens/report_generation_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
import 'package:mind_mates/services/admin_report_pdf_service.dart';

class _FiltersPreviewFakeRepository extends AdminPortalRepository {
  _FiltersPreviewFakeRepository();

  Completer<AdminReportAnalytics>? pendingFetch;
  Object? fetchError;
  final calls = <Map<String, Object?>>[];
  final auditEvents = <String>[];

  @override
  AccessRole get currentAccessRole => AccessRole.admin;

  @override
  bool get isSuperAdmin => true;

  @override
  Future<void> recordAuditEvent({
    required String action,
    required String category,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) async {
    auditEvents.add(action);
  }

  @override
  Future<AdminReportAnalytics> fetchFilteredReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String program = 'all',
    String? schoolYear,
    String? periodLabel,
    DateTime? startDate,
    DateTime? endDate,
    String emotionalSource = 'all',
  }) async {
    calls.add({
      'userCategory': userCategory,
      'appointmentDepartment': appointmentDepartment,
      'program': program,
      'schoolYear': schoolYear ?? '2026-2027',
      'periodLabel': periodLabel,
      'startDate': startDate?.toUtc().toIso8601String(),
      'endDate': endDate?.toUtc().toIso8601String(),
      'emotionalSource': emotionalSource,
    });
    if (pendingFetch != null) return pendingFetch!.future;
    if (fetchError != null) throw fetchError!;
    return _sampleReport(
      userCategory: userCategory,
      department: appointmentDepartment,
      program: program,
      schoolYear: schoolYear ?? '2026-2027',
      periodLabel: periodLabel,
      emotionalSource: emotionalSource,
    );
  }

  @override
  Future<AdminReportAnalytics> fetchEmotionalReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
    String emotionalSource = 'all',
  }) => fetchFilteredReportAnalytics(
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
  }) => fetchFilteredReportAnalytics(
    userCategory: userCategory,
    appointmentDepartment: appointmentDepartment,
    schoolYear: schoolYear,
    startDate: startDate,
    endDate: endDate,
  );

  @override
  Future<List<ImportedWalkInFile>> listWalkInImports() async => [];

  static AdminReportAnalytics _sampleReport({
    required String userCategory,
    required String department,
    required String program,
    required String schoolYear,
    required String? periodLabel,
    required String emotionalSource,
  }) {
    final programOptionsByCollege = {
      'cas': [
        {'key': 'ba psychology', 'label': 'BA Psychology'},
        {'key': 'ba english', 'label': 'BA English'},
      ],
      'coe': [
        {'key': 'bs civil engineering', 'label': 'BS Civil Engineering'},
      ],
    };
    final activePrograms = department == 'all'
        ? [
            {'key': 'ba english', 'label': 'BA English'},
            {'key': 'ba psychology', 'label': 'BA Psychology'},
            {'key': 'bs civil engineering', 'label': 'BS Civil Engineering'},
          ]
        : (programOptionsByCollege[department] ?? const []);

    return AdminReportAnalytics.fromJson({
      'generatedAt': '2026-11-16T04:00:00Z',
      'dateRange': {
        'startDate': '2026-06-01T00:00:00+08:00',
        'endDate': '2027-06-01T00:00:00+08:00',
        'label': periodLabel ?? 'Academic year $schoolYear',
      },
      'filters': {
        'schoolYear': schoolYear,
        'periodLabel': periodLabel ?? 'Whole academic year',
        'userCategory': userCategory,
        'userCategoryLabel': userCategory == 'student'
            ? 'Students'
            : userCategory == 'teaching'
            ? 'Teaching personnel'
            : userCategory == 'nonTeaching'
            ? 'Non-teaching personnel'
            : 'All categories',
        'collegeKey': department,
        'collegeLabel': department == 'cas'
            ? 'CAS'
            : department == 'coe'
            ? 'COE'
            : 'All colleges & departments',
        'programKey': program,
        'programLabel': program == 'ba psychology'
            ? 'BA Psychology'
            : program == 'bs civil engineering'
            ? 'BS Civil Engineering'
            : 'All programs',
        'emotionalSource': emotionalSource,
        'emotionalSourceLabel': emotionalSource == 'mood'
            ? 'Mood check-ins only'
            : 'All approved sources',
        'collegeOptions': [
          {'key': 'cas', 'label': 'CAS'},
          {'key': 'coe', 'label': 'COE'},
        ],
        'programOptions': activePrograms,
        'programOptionsByCollege': programOptionsByCollege,
      },
      'population': {
        'schoolYear': schoolYear,
        'configured': true,
        'status': 'current',
        'departments': ['CAS', 'COE'],
        'populations': {'CAS': 120, 'COE': 80},
        'totalPopulation': 200,
        'years': [
          {
            'schoolYear': '2026-2027',
            'startDate': '2026-06-01',
            'endDate': '2027-05-31',
            'status': 'current',
          },
        ],
      },
      'users': {
        'scopeKey': userCategory,
        'scopeLabel': userCategory == 'all'
            ? 'Whole app-user population'
            : userCategory,
        'overallActivePercentage': 62.5,
        'categoryOptions': [
          {'key': 'student', 'label': 'Students'},
          {'key': 'teaching', 'label': 'Teaching personnel'},
          {'key': 'nonTeaching', 'label': 'Non-teaching personnel'},
        ],
        'categories': [
          {
            'key': 'student',
            'label': 'Students',
            'populationPercentage': 70,
            'activePercentage': 65,
          },
        ],
      },
      'appointments': {
        'totalAppointments': 14,
        'uniqueStudentsServed': 11,
        'counselingReach': 5.5,
        'appointmentRate': 7.0,
        'completionRate': 85.7,
        'departmentScopeKey': department,
        'departmentScopeLabel': department == 'cas' ? 'CAS' : 'All departments',
        'departmentOptions': [
          {'key': 'cas', 'label': 'CAS'},
          {'key': 'coe', 'label': 'COE'},
        ],
        'department': [
          {'key': 'cas', 'label': 'CAS', 'percentage': 100},
        ],
        'course': [
          {'key': 'ba psychology', 'label': 'BA Psychology', 'percentage': 100},
        ],
      },
      'emotionalActivity': {
        'status': 'ready',
        'suppressed': false,
        'suppressionThreshold': 10,
        'sourceScopeKey': emotionalSource,
        'sourceScopeLabel': 'All approved sources',
        'schoolYear': schoolYear,
        'dateRangeLabel': periodLabel ?? 'Whole academic year',
        'participationRate': 18.0,
        'dominantValenceLabel': 'Positive (Levels 4-5)',
        'valenceBreakdown': [
          {
            'key': 'positive',
            'label': 'Positive (Levels 4-5)',
            'percentage': 70.0,
            'suppressed': false,
          },
        ],
      },
    });
  }
}

void main() {
  testWidgets(
    'selecting College limits Program options and resets prior Program cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _FiltersPreviewFakeRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: ReportGenerationPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();

      // Select College = CAS.
      await tester.tap(find.byKey(const ValueKey('appt-dept-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CAS').last);
      await tester.pumpAndSettle();

      expect(repo.calls.last['appointmentDepartment'], 'cas');
      expect(repo.calls.last['program'], 'all');

      // Open Program dropdown: CAS programs shown, COE program absent.
      await tester.tap(find.byKey(const ValueKey('appt-program-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('BA Psychology'), findsWidgets);
      expect(find.text('BS Civil Engineering'), findsNothing);
      await tester.tap(find.text('BA Psychology').last);
      await tester.pumpAndSettle();
      expect(repo.calls.last['program'], 'ba psychology');

      // Switch College to COE -> Program resets back to 'all'.
      await tester.tap(find.byKey(const ValueKey('appt-dept-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('COE').last);
      await tester.pumpAndSettle();
      expect(repo.calls.last['appointmentDepartment'], 'coe');
      expect(repo.calls.last['program'], 'all');
    },
  );

  testWidgets(
    'Preview and Print/Download use identical PDF byte snapshot and lock during reload',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _FiltersPreviewFakeRepository();
      Uint8List? previewedBytes;
      Uint8List? printedBytes;
      Uint8List? sharedBytes;
      String? sharedFilename;

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: ReportGenerationPage(
              repository: repo,
              pdfPreviewBuilder: (_, bytes) {
                previewedBytes = bytes;
                return const SizedBox(
                  key: ValueKey('mock-pdf-canvas'),
                  height: 120,
                  child: Center(child: Text('PDF Canvas')),
                );
              },
              onPrintPdf: (bytes) async => printedBytes = bytes,
              onSharePdf: (bytes, filename) async {
                sharedBytes = bytes;
                sharedFilename = filename;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Preview PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Report Preview'), findsOneWidget);
      expect(find.textContaining('CONFIDENTIAL'), findsOneWidget);
      expect(find.text('PDF Canvas'), findsOneWidget);
      expect(previewedBytes, isNotNull);

      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();
      expect(identical(printedBytes, previewedBytes), isTrue);
      expect(repo.auditEvents, contains('REPORT_VIEWED'));
      expect(repo.auditEvents, contains('REPORT_PRINTED'));

      await tester.tap(find.widgetWithText(FilledButton, 'Download PDF').last);
      await tester.pumpAndSettle();
      expect(identical(sharedBytes, previewedBytes), isTrue);
      expect(sharedFilename, contains('.pdf'));

      // Close preview dialog and verify stale-snapshot lock while reloading filters.
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();

      final pending = Completer<AdminReportAnalytics>();
      repo.pendingFetch = pending;
      await tester.tap(find.widgetWithText(ChoiceChip, 'Students'));
      await tester.pump();

      final previewButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Preview PDF'),
      );
      final downloadButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Download PDF'),
      );
      expect(previewButton.onPressed, isNull);
      expect(downloadButton.onPressed, isNull);

      pending.complete(
        _FiltersPreviewFakeRepository._sampleReport(
          userCategory: 'student',
          department: 'all',
          program: 'all',
          schoolYear: '2026-2027',
          periodLabel: null,
          emotionalSource: 'all',
        ),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'surfaces invalid filter errors cleanly with Reset filters and works at 360px',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _FiltersPreviewFakeRepository()
        ..fetchError = StateError('invalid filters');

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: ReportGenerationPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The report could not be loaded.'), findsOneWidget);
      expect(find.text('Reset filters'), findsOneWidget);

      repo.fetchError = null;
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(find.text('Reset filters'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'AdminReportPdfService generates deterministic PDF for same snapshot',
    () async {
      final repo = _FiltersPreviewFakeRepository();
      final report = await repo.fetchFilteredReportAnalytics(
        userCategory: 'student',
        appointmentDepartment: 'cas',
        program: 'ba psychology',
        periodLabel: '1st semester',
      );
      final bytesA = await AdminReportPdfService.build(
        report: report,
        reportType: AdminReportType.emotionalActivity,
        chartType: ReportChartType.bar,
      );
      final bytesB = await AdminReportPdfService.build(
        report: report,
        reportType: AdminReportType.emotionalActivity,
        chartType: ReportChartType.bar,
      );
      String normalizePdfMetadata(Uint8List bytes) =>
          String.fromCharCodes(bytes)
              .replaceAll(
                RegExp(r'/CreationDate\s*\([^)]*\)'),
                '/CreationDate ()',
              )
              .replaceAll(RegExp(r'/ID\s*\[[^\]]*\]'), '/ID []');
      expect(
        normalizePdfMetadata(bytesA),
        equals(normalizePdfMetadata(bytesB)),
      );
    },
  );

  testWidgets(
    'UserReport shows empty state instead of synthetic 100% when userCategories is empty',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _CustomReportRepository(
        report: AdminReportAnalytics.fromJson({
          'generatedAt': '2026-11-16T04:00:00Z',
          'population': {
            'schoolYear': '2026-2027',
            'configured': true,
            'status': 'current',
            'years': [
              {
                'schoolYear': '2026-2027',
                'startDate': '2026-06-01',
                'endDate': '2027-05-31',
                'status': 'current',
              },
            ],
          },
          'users': {
            'scopeKey': 'all',
            'scopeLabel': 'Whole app-user population',
            'overallActivePercentage': 0,
            'categories': const [],
          },
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: ReportGenerationPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No app-user activity data available for the selected filters.',
        ),
        findsOneWidget,
      );
      expect(find.text('100%'), findsNothing);
      expect(find.text('No recent activity'), findsNothing);
    },
  );

  testWidgets(
    'AppointmentReport distinguishes 0 appointments empty state from <5 unique students privacy banner',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyApptRepo = _CustomReportRepository(
        report: AdminReportAnalytics.fromJson({
          'generatedAt': '2026-11-16T04:00:00Z',
          'population': {
            'schoolYear': '2026-2027',
            'configured': true,
            'status': 'current',
            'departments': ['CAS'],
            'populations': {'CAS': 100},
            'totalPopulation': 100,
            'years': [
              {
                'schoolYear': '2026-2027',
                'startDate': '2026-06-01',
                'endDate': '2027-05-31',
                'status': 'current',
              },
            ],
          },
          'appointments': {'totalAppointments': 0, 'uniqueStudentsServed': 0},
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: ReportGenerationPage(
              key: const ValueKey('zero-appts'),
              repository: emptyApptRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();

      expect(
        find.text('No counseling appointments matched the selected filters.'),
        findsOneWidget,
      );
      expect(find.textContaining('fewer than 5 unique students'), findsNothing);

      final smallCohortRepo = _CustomReportRepository(
        report: AdminReportAnalytics.fromJson({
          'generatedAt': '2026-11-16T04:00:00Z',
          'population': {
            'schoolYear': '2026-2027',
            'configured': true,
            'status': 'current',
            'departments': ['CAS'],
            'populations': {'CAS': 100},
            'totalPopulation': 100,
            'years': [
              {
                'schoolYear': '2026-2027',
                'startDate': '2026-06-01',
                'endDate': '2027-05-31',
                'status': 'current',
              },
            ],
          },
          'appointments': {'totalAppointments': 4, 'uniqueStudentsServed': 3},
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: ReportGenerationPage(
              key: const ValueKey('small-cohort'),
              repository: smallCohortRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('fewer than 5 unique students'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ErrorPanel surfaces safe FirebaseFunctionsException messages while keeping Reset filters',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final entry in [
        (
          error: FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Planned academic years cannot generate official reports.',
          ),
          expected: 'Planned academic years cannot generate official reports.',
        ),
        (
          error: FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'raw secret path /users/123',
          ),
          expected: 'You do not have permission to complete this action.',
        ),
        (
          error: FirebaseFunctionsException(
            code: 'internal',
            message: 'Firestore stack trace /internal/doc',
          ),
          expected:
              'Check your filters, access scope, or report service connection, then try again.',
        ),
      ]) {
        final repo = _FiltersPreviewFakeRepository()..fetchError = entry.error;
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: ReportGenerationPage(
                key: ValueKey(entry.error.code),
                repository: repo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('The report could not be loaded.'), findsOneWidget);
        expect(find.text('Reset filters'), findsOneWidget);
        expect(find.text(entry.expected), findsOneWidget);
        expect(find.textContaining('/users/123'), findsNothing);
        expect(find.textContaining('/internal/doc'), findsNothing);
      }
    },
  );

  testWidgets(
    'Users tab filters Selected app-user category only table to selected categoryKey',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _CustomReportRepository(
        report: AdminReportAnalytics.fromJson({
          'generatedAt': '2026-11-16T04:00:00Z',
          'population': {
            'schoolYear': '2026-2027',
            'configured': true,
            'status': 'current',
            'years': [
              {
                'schoolYear': '2026-2027',
                'startDate': '2026-06-01',
                'endDate': '2027-05-31',
                'status': 'current',
              },
            ],
          },
          'users': {
            'scopeKey': 'students',
            'scopeLabel': 'Students',
            'overallActivePercentage': 50,
            'categoryOptions': [
              {'key': 'students', 'label': 'Students'},
              {'key': 'faculty', 'label': 'Faculty'},
            ],
            'categories': [
              {
                'key': 'students',
                'label': 'Students',
                'populationPercentage': 30,
                'activePercentage': 50,
              },
              {
                'key': 'faculty',
                'label': 'Faculty',
                'populationPercentage': 70,
                'activePercentage': 20,
              },
            ],
          },
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: ReportGenerationPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Students'));
      await tester.pumpAndSettle();

      expect(find.text('Selected app-user category only'), findsOneWidget);
      expect(find.text('30%'), findsWidgets);
      expect(find.text('70%'), findsNothing);
      expect(find.text('20%'), findsNothing);
    },
  );

  testWidgets(
    'renders compact two-column filters and color-coded metric badges cleanly across widths',
    (tester) async {
      final repo = _FiltersPreviewFakeRepository();
      for (final width in [360.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: ReportGenerationPage(
                key: ValueKey('layout-$width'),
                repository: repo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Engagement'), findsOneWidget);
        expect(find.text('Population'), findsOneWidget);

        await tester.tap(find.text('Counseling appointments'));
        await tester.pumpAndSettle();

        expect(find.text('Volume'), findsOneWidget);
        expect(find.text('Outcome'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

class _CustomReportRepository extends AdminPortalRepository {
  _CustomReportRepository({required this.report});

  final AdminReportAnalytics report;

  @override
  AccessRole get currentAccessRole => AccessRole.admin;

  @override
  bool get isSuperAdmin => true;

  @override
  Future<AdminReportAnalytics> fetchFilteredReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String program = 'all',
    String? schoolYear,
    String? periodLabel,
    DateTime? startDate,
    DateTime? endDate,
    String emotionalSource = 'all',
  }) async => report;

  @override
  Future<List<ImportedWalkInFile>> listWalkInImports() async => [];
}
