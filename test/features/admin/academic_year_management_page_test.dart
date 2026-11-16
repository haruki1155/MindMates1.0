import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/features/admin/screens/academic_year_management_page.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/report_generation_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _AcademicYearFakeRepository extends AdminPortalRepository {
  _AcademicYearFakeRepository({
    this.role = AccessRole.admin,
    List<AcademicYearRecord>? initialYears,
  }) : years = List<AcademicYearRecord>.of(
         initialYears ??
             const [
               AcademicYearRecord(
                 schoolYear: '2027-2028',
                 startDate: '2027-06-01',
                 endDate: '2028-05-31',
                 status: 'current',
               ),
               AcademicYearRecord(
                 schoolYear: '2026-2027',
                 startDate: '2026-06-01',
                 endDate: '2027-05-31',
                 status: 'current',
               ),
               AcademicYearRecord(
                 schoolYear: '2025-2026',
                 startDate: '2025-06-01',
                 endDate: '2026-05-31',
                 status: 'closed',
               ),
             ],
       );

  final AccessRole role;
  List<AcademicYearRecord> years;
  Object? fetchError;
  Object? createError;
  Object? closeError;
  Completer<List<AcademicYearRecord>>? pendingFetch;
  final createCalls = <Map<String, Object?>>[];
  final closeCalls = <String>[];

  @override
  AccessRole get currentAccessRole => role;

  @override
  Future<List<AcademicYearRecord>> fetchAcademicYears() async {
    if (pendingFetch != null) return pendingFetch!.future;
    if (fetchError != null) throw fetchError!;
    return List<AcademicYearRecord>.of(years);
  }

  @override
  Future<List<AcademicYearRecord>> createAcademicYear({
    required String schoolYear,
    String? startDate,
    String? endDate,
    String? copyFrom,
    bool copyPopulation = false,
  }) async {
    createCalls.add({
      'schoolYear': schoolYear,
      'startDate': startDate,
      'endDate': endDate,
      'copyFrom': copyFrom,
      'copyPopulation': copyPopulation,
    });
    if (createError != null) throw createError!;
    years = [
      AcademicYearRecord(
        schoolYear: schoolYear,
        startDate: startDate ?? '2028-06-01',
        endDate: endDate ?? '2029-05-31',
        status: 'current',
      ),
      ...years,
    ];
    return List<AcademicYearRecord>.of(years);
  }

  @override
  Future<List<AcademicYearRecord>> closeAcademicYear(String schoolYear) async {
    closeCalls.add(schoolYear);
    if (closeError != null) throw closeError!;
    years = years
        .map(
          (year) => year.schoolYear == schoolYear
              ? AcademicYearRecord(
                  schoolYear: year.schoolYear,
                  startDate: year.startDate,
                  endDate: year.endDate,
                  status: 'closed',
                )
              : year,
        )
        .toList();
    return List<AcademicYearRecord>.of(years);
  }

  @override
  Future<AdminReportAnalytics> fetchReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
  }) async => AdminReportAnalytics.fromJson({
    'generatedAt': '2026-11-16T00:00:00Z',
    'population': {
      'schoolYear': schoolYear ?? '2026-2027',
      'configured': true,
      'status': schoolYear == '2025-2026' ? 'closed' : 'current',
      'departments': ['College of Computing'],
      'populations': {'College of Computing': 100},
      'totalPopulation': 100,
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
    'appointments': {'totalAppointments': 5, 'uniqueStudentsServed': 4},
  });

  @override
  Future<List<ImportedWalkInFile>> listWalkInImports() async => [];
}

void main() {
  testWidgets(
    'Academic Year sits immediately below Reports for admins and is hidden for non-admins',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final role in [
        AccessRole.admin,
        AccessRole.counselor,
        AccessRole.portalStaff,
      ]) {
        AdminPortalPage? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: SizedBox(
                width: 280,
                height: 1000,
                child: PortalWorkspaceNavigation(
                  page: AdminPortalPage.dashboard,
                  onChanged: (page) => selected = page,
                  accessRole: role,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final academicYearFinder = find.text('Academic Year');
        if (role == AccessRole.admin) {
          expect(academicYearFinder, findsOneWidget);
          final reportsY = tester.getTopLeft(find.text('Reports')).dy;
          final academicYearY = tester.getTopLeft(academicYearFinder).dy;
          expect(academicYearY, greaterThan(reportsY));
          expect(academicYearY - reportsY, lessThan(80));
          await tester.tap(academicYearFinder);
          await tester.pumpAndSettle();
          expect(selected, AdminPortalPage.academicYear);
        } else {
          expect(academicYearFinder, findsNothing);
        }
      }
    },
  );

  testWidgets('non-admins see an authorization message on the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: AcademicYearManagementPage(
            repository: _AcademicYearFakeRepository(role: AccessRole.counselor),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(find.text('Create academic year'), findsNothing);
  });

  testWidgets('displays loading, error with retry, and empty states', (
    tester,
  ) async {
    final pending = Completer<List<AcademicYearRecord>>();
    final repo = _AcademicYearFakeRepository(initialYears: const [])
      ..pendingFetch = pending;

    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(body: AcademicYearManagementPage(repository: repo)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repo.pendingFetch = null;
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not load academic years'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No academic years configured yet'), findsOneWidget);
  });

  testWidgets(
    'displays current, upcoming, and closed years and keeps closed years read-only',
    (tester) async {
      final repo = _AcademicYearFakeRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: repo,
              nowProvider: () => DateTime(2026, 11, 16),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Current'), findsWidgets);
      expect(find.text('Upcoming'), findsWidgets);
      expect(find.text('Closed'), findsWidgets);
      expect(find.text('2026-2027'), findsOneWidget);
      expect(find.text('2027-2028'), findsOneWidget);
      expect(find.text('2025-2026'), findsOneWidget);
      // Only open years (2026-2027 and 2027-2028) show Close year; closed 2025-2026 shows Locked.
      expect(find.text('Close year'), findsNWidgets(2));
      expect(find.text('Locked · read-only'), findsOneWidget);
    },
  );

  testWidgets('admin creates an academic year and sees validation errors', (
    tester,
  ) async {
    final repo = _AcademicYearFakeRepository(
      initialYears: const [
        AcademicYearRecord(
          schoolYear: '2025-2026',
          startDate: '2025-06-01',
          endDate: '2026-05-31',
          status: 'closed',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: AcademicYearManagementPage(
            repository: repo,
            nowProvider: () => DateTime(2026, 11, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create academic year'));
    await tester.pumpAndSettle();

    // Invalid school year shows inline validation without calling backend.
    await tester.enterText(
      find.widgetWithText(TextField, 'School year'),
      '2026-2029',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('consecutive years'), findsOneWidget);
    expect(repo.createCalls, isEmpty);

    // Reversed start/end date range shows inline validation without calling backend.
    await tester.enterText(
      find.widgetWithText(TextField, 'School year'),
      '2026-2027',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Start date (YYYY-MM-DD)'),
      '2026-06-01',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'End date (YYYY-MM-DD)'),
      '2026-05-31',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Start date must be earlier'), findsOneWidget);
    expect(repo.createCalls, isEmpty);

    // Valid school year submits and shows the created year.
    await tester.enterText(
      find.widgetWithText(TextField, 'School year'),
      '2026-2027',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Start date (YYYY-MM-DD)'),
      '2026-06-01',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'End date (YYYY-MM-DD)'),
      '2027-05-31',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(repo.createCalls.single['schoolYear'], '2026-2027');
    expect(find.text('2026-2027'), findsOneWidget);
    expect(
      find.textContaining('Academic year 2026-2027 created'),
      findsOneWidget,
    );

    // Server rejection surfaces clearly.
    repo.createError = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'Close active academic year 2026-2027 first.',
    );
    await tester.tap(find.text('Create academic year'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'School year'),
      '2027-2028',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Close active academic year'), findsOneWidget);
  });

  testWidgets('admin closes an active academic year with confirmation', (
    tester,
  ) async {
    final repo = _AcademicYearFakeRepository(
      initialYears: const [
        AcademicYearRecord(
          schoolYear: '2026-2027',
          startDate: '2026-06-01',
          endDate: '2027-05-31',
          status: 'current',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: AcademicYearManagementPage(
            repository: repo,
            nowProvider: () => DateTime(2026, 11, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close year'));
    await tester.pumpAndSettle();

    final lockButton = find.widgetWithText(FilledButton, 'Lock year');
    expect(tester.widget<FilledButton>(lockButton).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Confirmation'),
      'CLOSE 2026-2027',
    );
    await tester.pump();
    await tester.tap(lockButton);
    await tester.pumpAndSettle();

    expect(repo.closeCalls, ['2026-2027']);
    expect(find.text('Locked · read-only'), findsOneWidget);
    expect(find.text('Close year'), findsNothing);
  });

  testWidgets(
    'Reports keeps Academic Year selection while management controls moved out',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: ReportGenerationPage(
              repository: _AcademicYearFakeRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();

      expect(find.text('Academic year'), findsWidgets);
      expect(find.text('Add academic year'), findsNothing);
      expect(find.text('Close this year'), findsNothing);
    },
  );

  for (final width in [360.0, 1280.0]) {
    testWidgets('lays out cleanly without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: _AcademicYearFakeRepository(),
              nowProvider: () => DateTime(2026, 11, 16),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
