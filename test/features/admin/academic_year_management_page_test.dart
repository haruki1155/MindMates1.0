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
    this.superAdmin = false,
    this.extendedLifecycleEnabled = true,
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
  final bool superAdmin;
  final bool extendedLifecycleEnabled;
  List<AcademicYearRecord> years;
  Object? fetchError;
  Object? createError;
  Object? activateError;
  Object? closeError;
  Object? voidError;
  Completer<List<AcademicYearRecord>>? pendingFetch;
  final fetchIncludeVoidedCalls = <bool>[];
  final createCalls = <Map<String, Object?>>[];
  final activateCalls = <String>[];
  final closeCalls = <String>[];
  final closeCallPayloads = <Map<String, Object?>>[];
  final voidCalls = <Map<String, Object?>>[];

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  bool get isExtendedAcademicYearLifecycleEnabled => extendedLifecycleEnabled;

  @override
  Future<List<AcademicYearRecord>> fetchAcademicYears({
    bool includeVoided = false,
  }) async {
    fetchIncludeVoidedCalls.add(includeVoided);
    if (pendingFetch != null) return pendingFetch!.future;
    if (fetchError != null) throw fetchError!;
    return List<AcademicYearRecord>.of(
      includeVoided ? years : years.where((y) => !y.isVoided),
    );
  }

  @override
  Future<List<AcademicYearRecord>> createAcademicYear({
    required String schoolYear,
    String? startDate,
    String? endDate,
    String? copyFrom,
    bool copyPopulation = false,
    String? reinstateReason,
    int? expectedRevision,
  }) async {
    createCalls.add({
      'schoolYear': schoolYear,
      'startDate': startDate,
      'endDate': endDate,
      'copyFrom': copyFrom,
      'copyPopulation': copyPopulation,
      'reinstateReason': reinstateReason,
      'expectedRevision': expectedRevision,
    });
    if (createError != null) throw createError!;
    final hasCurrent = years.any((y) => y.isCurrent);
    final next = AcademicYearRecord(
      schoolYear: schoolYear,
      startDate: startDate ?? '2028-06-01',
      endDate: endDate ?? '2029-05-31',
      status: hasCurrent ? 'planned' : 'current',
    );
    years = [next, ...years.where((y) => y.schoolYear != schoolYear)];
    return List<AcademicYearRecord>.of(years);
  }

  @override
  Future<List<AcademicYearRecord>> activateAcademicYear(
    String schoolYear, {
    int? expectedRevision,
  }) async {
    activateCalls.add(schoolYear);
    if (activateError != null) throw activateError!;
    years = years
        .map(
          (year) => year.schoolYear == schoolYear
              ? AcademicYearRecord(
                  schoolYear: year.schoolYear,
                  startDate: year.startDate,
                  endDate: year.endDate,
                  status: 'current',
                  revision: year.revision + 1,
                )
              : year,
        )
        .toList();
    return List<AcademicYearRecord>.of(years);
  }

  @override
  Future<List<AcademicYearRecord>> closeAcademicYear(
    String schoolYear, {
    int? expectedRevision,
    String? confirmation,
  }) async {
    closeCalls.add(schoolYear);
    closeCallPayloads.add({
      'schoolYear': schoolYear,
      'expectedRevision': expectedRevision,
      'confirmation': confirmation,
    });
    if (closeError != null) throw closeError!;
    years = years
        .map(
          (year) => year.schoolYear == schoolYear
              ? AcademicYearRecord(
                  schoolYear: year.schoolYear,
                  startDate: year.startDate,
                  endDate: year.endDate,
                  status: 'closed',
                  revision: year.revision + 1,
                )
              : year,
        )
        .toList();
    return List<AcademicYearRecord>.of(years);
  }

  @override
  Future<List<AcademicYearRecord>> voidAcademicYear({
    required String schoolYear,
    required String reason,
    required String confirmationText,
    int? expectedRevision,
  }) async {
    voidCalls.add({
      'schoolYear': schoolYear,
      'reason': reason,
      'confirmation': confirmationText,
      'expectedRevision': expectedRevision,
    });
    if (voidError != null) throw voidError!;
    years = years
        .map(
          (year) => year.schoolYear == schoolYear
              ? AcademicYearRecord(
                  schoolYear: year.schoolYear,
                  startDate: year.startDate,
                  endDate: year.endDate,
                  status: 'voided',
                  revision: year.revision + 1,
                  voidReason: reason,
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

  testWidgets('admin closes an active academic year only after endDate with confirmation', (
    tester,
  ) async {
    final repo = _AcademicYearFakeRepository(
      initialYears: const [
        AcademicYearRecord(
          schoolYear: '2026-2027',
          startDate: '2026-06-01',
          endDate: '2027-05-31',
          status: 'current',
          revision: 2,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: AcademicYearManagementPage(
            key: const ValueKey('early-close-check'),
            repository: repo,
            nowProvider: () => DateTime.utc(2026, 11, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Before 2027-05-31 endDate, Close year is disabled with explanation.
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Close year'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Closure opens after 2027-05-31'), findsOneWidget);

    // After endDate (June 1, 2027 Manila), Close year enables and sends confirmation + expectedRevision.
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: AcademicYearManagementPage(
            key: const ValueKey('after-end-close-check'),
            repository: repo,
            nowProvider: () => DateTime.utc(2027, 6, 1),
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
    expect(repo.closeCallPayloads.single['confirmation'], 'CLOSE 2026-2027');
    expect(repo.closeCallPayloads.single['expectedRevision'], 2);
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

  testWidgets(
    'planning horizon rejects far-future year and Planned year disables Activate until eligible',
    (tester) async {
      final repo = _AcademicYearFakeRepository(
        initialYears: const [
          AcademicYearRecord(
            schoolYear: '2026-2027',
            startDate: '2026-06-01',
            endDate: '2027-05-31',
            status: 'current',
            revision: 1,
          ),
          AcademicYearRecord(
            schoolYear: '2027-2028',
            startDate: '2027-07-01',
            endDate: '2028-05-31',
            status: 'planned',
            revision: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: repo,
              nowProvider: () => DateTime.utc(2026, 11, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Planned row displays Activate year disabled with explicit explanation while 2026-2027 is current.
      final activateFinder = find.widgetWithText(
        FilledButton,
        'Activate year',
      );
      expect(activateFinder, findsOneWidget);
      expect(tester.widget<FilledButton>(activateFinder).onPressed, isNull);
      expect(
        find.textContaining('Close the active current academic year'),
        findsOneWidget,
      );

      // Far-future year 2028-2029 is blocked cleanly by planning horizon check.
      await tester.tap(find.text('Create academic year'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'School year'),
        '2028-2029',
      );
      await tester.pump();
      expect(find.textContaining('too far in the future'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(repo.createCalls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // After 2027-05-31 endDate (on 2027-06-01 Manila), close 2026-2027 -> Planned 2027-2028 shows start-date explanation until 2027-07-01.
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: repo,
              nowProvider: () => DateTime.utc(2027, 6, 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close year'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirmation'),
        'CLOSE 2026-2027',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lock year'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Activation opens on 2027-07-01'), findsOneWidget);

      // On July 1, 2027 Manila time, Activate year enables and confirms cleanly.
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: repo,
              nowProvider: () => DateTime.utc(2027, 7, 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Activate year'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirmation'),
        'ACTIVATE 2027-2028',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Activate year').last);
      await tester.pumpAndSettle();
      expect(repo.activateCalls, ['2027-2028']);
    },
  );

  testWidgets(
    'only super-admin can Void year with written reason and confirmation, and voided year can be reinstated',
    (tester) async {
      // Regular admin never sees Void year (nor Delete).
      final adminRepo = _AcademicYearFakeRepository(
        superAdmin: false,
        initialYears: const [
          AcademicYearRecord(
            schoolYear: '2028-2029',
            startDate: '2028-06-01',
            endDate: '2029-05-31',
            status: 'current',
            revision: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: adminRepo,
              nowProvider: () => DateTime.utc(2026, 11, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(adminRepo.fetchIncludeVoidedCalls, [true]);
      expect(find.text('Void year'), findsNothing);
      expect(find.textContaining('Delete'), findsNothing);

      // Super-admin voids 2028-2029 cleanly and can reinstate it with note.
      final superRepo = _AcademicYearFakeRepository(
        superAdmin: true,
        initialYears: const [
          AcademicYearRecord(
            schoolYear: '2026-2027',
            startDate: '2026-06-01',
            endDate: '2027-05-31',
            status: 'current',
            revision: 1,
          ),
          AcademicYearRecord(
            schoolYear: '2027-2028',
            startDate: '2027-06-01',
            endDate: '2028-05-31',
            status: 'planned',
            revision: 2,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              key: const ValueKey('super-admin-ay'),
              repository: superRepo,
              nowProvider: () => DateTime.utc(2026, 11, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Void year').last);
      await tester.pumpAndSettle();

      final submitVoid = find.widgetWithText(FilledButton, 'Void year');
      expect(tester.widget<FilledButton>(submitVoid).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Void reason (required)'),
        'Created before enrollment confirmation',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirmation'),
        'VOID 2027-2028',
      );
      await tester.pump();
      await tester.tap(submitVoid);
      await tester.pumpAndSettle();

      expect(superRepo.voidCalls.single['schoolYear'], '2027-2028');
      expect(superRepo.voidCalls.single['expectedRevision'], 2);
      expect(find.text('Voided · audit preserved'), findsOneWidget);
      expect(
        find.textContaining('Created before enrollment confirmation'),
        findsOneWidget,
      );

      // Reinstatement uses Create flow and shows Reinstatement note field.
      await tester.tap(find.text('Create academic year'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'School year'),
        '2027-2028',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Reinstatement note (optional)'),
        'Confirmed next school year schedule',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reinstate'));
      await tester.pumpAndSettle();
      expect(
        superRepo.createCalls.single['reinstateReason'],
        'Confirmed next school year schedule',
      );
      expect(superRepo.createCalls.single['expectedRevision'], 3);
    },
  );

  testWidgets(
    'when extended lifecycle is disabled on server, disables Activate/Void and explains future Create limits',
    (tester) async {
      final repo = _AcademicYearFakeRepository(
        superAdmin: true,
        extendedLifecycleEnabled: false,
        initialYears: const [
          AcademicYearRecord(
            schoolYear: '2026-2027',
            startDate: '2026-06-01',
            endDate: '2027-05-31',
            status: 'current',
            revision: 1,
          ),
          AcademicYearRecord(
            schoolYear: '2027-2028',
            startDate: '2027-06-01',
            endDate: '2028-05-31',
            status: 'planned',
            revision: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: repo,
              nowProvider: () => DateTime.utc(2026, 11, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Extended lifecycle transitions (Planned future years',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate year'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Void year').first,
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('disabled until updated report analytics'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'reinstating a previously voided year on or after startDate announces Current state accurately',
    (tester) async {
      final repo = _AcademicYearFakeRepository(
        superAdmin: true,
        initialYears: const [
          AcademicYearRecord(
            schoolYear: '2026-2027',
            startDate: '2026-06-01',
            endDate: '2027-05-31',
            status: 'closed',
            revision: 2,
          ),
          AcademicYearRecord(
            schoolYear: '2028-2029',
            startDate: '2028-06-01',
            endDate: '2029-05-31',
            status: 'voided',
            revision: 1,
            voidReason: 'Created prematurely',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: repo,
              nowProvider: () => DateTime.utc(2028, 6, 5),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create academic year'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'School year'),
        '2028-2029',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('activates it as Current'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Reinstate'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Academic year 2028-2029 reinstated as current.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'legacy Batch B1 getAcademicYears without extendedLifecycleEnabled loads years and hides extended mutations',
    (tester) async {
      final repo = _LegacyBatchB1RealRepository(
        callableInvoker: (name, _) async {
          expect(name, 'getAcademicYears');
          // Batch B1 shape: omits extendedLifecycleEnabled completely.
          return <Object?, Object?>{
            'years': <Object?>[
              <Object?, Object?>{
                'schoolYear': '2026-2027',
                'startDate': '2026-06-01',
                'endDate': '2027-05-31',
                'status': 'current',
              },
              <Object?, Object?>{
                'schoolYear': '2025-2026',
                'startDate': '2025-06-01',
                'endDate': '2026-05-31',
                'status': 'closed',
              },
              <Object?, Object?>{
                'schoolYear': '2027-2028',
                'startDate': '2027-06-01',
                'endDate': '2028-05-31',
                'status': 'planned',
              },
            ],
          };
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AcademicYearManagementPage(
              repository: repo,
              nowProvider: () => DateTime.utc(2026, 11, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.isExtendedAcademicYearLifecycleEnabled, isFalse);
      expect(find.text('2026-2027'), findsOneWidget);
      expect(find.text('2025-2026'), findsOneWidget);
      expect(
        find.textContaining('Extended lifecycle transitions (Planned future years'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Activate year'),
            )
            .onPressed,
        isNull,
      );
      final voidButtons = tester
          .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Void year'),
          )
          .toList();
      expect(voidButtons, hasLength(2));
      for (final button in voidButtons) {
        expect(button.onPressed, isNull);
      }
    },
  );
}

class _LegacyBatchB1RealRepository extends AdminPortalRepository {
  _LegacyBatchB1RealRepository({super.callableInvoker});

  @override
  AccessRole get currentAccessRole => AccessRole.admin;

  @override
  bool get isSuperAdmin => true;
}
