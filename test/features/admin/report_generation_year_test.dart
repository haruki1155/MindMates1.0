import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/features/admin/screens/report_generation_page.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _ReportRepository extends AdminPortalRepository {
  _ReportRepository({
    this.role = AccessRole.admin,
    this.statusOverride,
    this.customYears,
  });

  final AccessRole role;
  final String? statusOverride;
  final List<Map<String, dynamic>>? customYears;
  final requestedYears = <String>[];
  bool configured = true;

  @override
  AccessRole get currentAccessRole => role;

  @override
  Future<AdminReportAnalytics> fetchReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final year = schoolYear ?? '2026-2027';
    requestedYears.add(year);
    return AdminReportAnalytics.fromJson({
      'generatedAt': '2026-09-19T00:00:00Z',
      'population': {
        'schoolYear': year,
        'configured': configured,
        'status': statusOverride ?? (year == '2025-2026' ? 'closed' : 'current'),
        'departments': ['College of Computing'],
        'populations': {
          'College of Computing': year == '2025-2026' ? 120 : 240,
        },
        'totalPopulation': configured ? (year == '2025-2026' ? 120 : 240) : 0,
        'years': customYears ?? [
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
      'appointments': {
        'totalAppointments': year == '2025-2026' ? 12 : 24,
        'uniqueStudentsServed': 8,
      },
    });
  }

  @override
  Future<List<ImportedWalkInFile>> listWalkInImports() async => [];
}

void main() {
  for (final width in [1440.0, 1000.0, 800.0]) {
    testWidgets('report actions fit at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportGenerationPage(repository: _ReportRepository()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Counseling appointments'));
      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();
      expect(find.text('Preview PDF'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unconfigured population still shows appointment totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ReportRepository()..configured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportGenerationPage(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Counseling appointments'));
    await tester.tap(find.text('Counseling appointments'));
    await tester.pumpAndSettle();

    expect(find.text('Total appointments'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('Unique students served'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Not available'), findsNWidgets(2));
    expect(
      find.textContaining('Complete and save the student population'),
      findsOneWidget,
    );
  });

  testWidgets('switching academic year updates population fields and results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportGenerationPage(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Counseling appointments'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Total appointments')).dy,
      lessThan(tester.getTopLeft(find.text('Student population setup')).dy),
    );
    await tester.ensureVisible(find.text('Student population setup'));
    await tester.tap(find.text('Student population setup'));
    await tester.pumpAndSettle();

    final yearField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'School year',
    );
    final populationField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'College of Computing',
    );
    expect(tester.widget<TextField>(yearField).controller!.text, '2026-2027');
    expect(tester.widget<TextField>(populationField).controller!.text, '240');

    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).first,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025-2026').last);
    await tester.pumpAndSettle();

    expect(repository.requestedYears.last, '2025-2026');
    expect(tester.widget<TextField>(yearField).controller!.text, '2025-2026');
    expect(tester.widget<TextField>(populationField).controller!.text, '120');
    expect(find.text('Academic year 2025-2026'), findsWidgets);
    expect(find.text('Population locked'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-2027').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(populationField).controller!.text, '240');
  });

  testWidgets('switching years preserves an unsaved population draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportGenerationPage(repository: _ReportRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Counseling appointments'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Student population setup'));
    await tester.tap(find.text('Student population setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit population'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();

    final populationField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'College of Computing',
    );
    await tester.enterText(populationField, '250');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final yearDropdown = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(yearDropdown);
    await tester.pumpAndSettle();
    await tester.tap(yearDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025-2026').last);
    await tester.pumpAndSettle();
    await tester.tap(yearDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-2027').last);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(populationField).controller!.text, '250');
    expect(tester.widget<TextField>(populationField).readOnly, isFalse);
  });

  testWidgets('appointment results precede admin report setup and imports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportGenerationPage(repository: _ReportRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Counseling appointments'));
    await tester.pumpAndSettle();

    for (final label in [
      'Report Generation',
      'REPORT CONTROLS',
      'Academic year',
      'Reporting period',
      'Department scope',
      'Group by',
      'Visualization',
      'Appointment results · 2026-2027',
      'Total appointments',
      'Unique students served',
      'Service details',
      'Report setup',
      'Student population setup',
      'Imported files',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    final resultsY = tester
        .getTopLeft(find.text('Appointment results · 2026-2027'))
        .dy;
    final setupY = tester.getTopLeft(find.text('Report setup')).dy;
    final populationY = tester
        .getTopLeft(find.text('Student population setup'))
        .dy;
    final importsY = tester.getTopLeft(find.text('Imported files')).dy;
    expect(resultsY, lessThan(setupY));
    expect(setupY, lessThan(populationY));
    expect(populationY, lessThan(importsY));
  });

  testWidgets('counselors see results without admin setup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportGenerationPage(
            repository: _ReportRepository(role: AccessRole.counselor),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Counseling appointments'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment results · 2026-2027'), findsOneWidget);
    expect(find.text('Report setup'), findsNothing);
    expect(find.text('Student population setup'), findsNothing);
    expect(find.text('Imported files'), findsNothing);
  });

  testWidgets(
    'academic year dropdown hides voided and unknown years and separates Current from Planned and Upcoming',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _ReportRepository(
        customYears: const [
          {
            'schoolYear': '2026-2027',
            'startDate': '2026-06-01',
            'endDate': '2027-05-31',
            'status': 'current',
          },
          {
            'schoolYear': '2027-2028',
            'startDate': '2027-06-01',
            'endDate': '2028-05-31',
            'status': 'planned',
          },
          {
            'schoolYear': '2028-2029',
            'startDate': '2028-06-01',
            'endDate': '2029-05-31',
            'status': 'voided',
          },
          {
            'schoolYear': '2099-2100',
            'startDate': '2099-06-01',
            'endDate': '2100-05-31',
            'status': 'corrupted',
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportGenerationPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('2026-2027'), findsWidgets);
      expect(find.text('2027-2028'), findsWidgets);
      expect(find.text('Planned'), findsWidgets);
      expect(find.text('2028-2029'), findsNothing);
      expect(find.text('2099-2100'), findsNothing);
    },
  );

  for (final lockedStatus in ['closed', 'voided', 'unknown']) {
    testWidgets('population setup locks for $lockedStatus status', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportGenerationPage(
              repository: _ReportRepository(statusOverride: lockedStatus),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();

      final popHeader = find.text('Student population setup');
      await tester.ensureVisible(popHeader);
      await tester.tap(popHeader);
      await tester.pumpAndSettle();

      expect(find.text('Population locked'), findsOneWidget);
      final popField = find.widgetWithText(TextField, 'College of Computing');
      expect(tester.widget<TextField>(popField).readOnly, isTrue);
    });
  }

  testWidgets(
    'academic year dropdown does not fabricate Current badge when no valid reporting years exist',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _ReportRepository(
        customYears: const [
          {
            'schoolYear': '2028-2029',
            'startDate': '2028-06-01',
            'endDate': '2029-05-31',
            'status': 'voided',
          },
          {
            'schoolYear': '2099-2100',
            'startDate': '2099-06-01',
            'endDate': '2100-05-31',
            'status': 'corrupted',
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportGenerationPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counseling appointments'));
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsWidgets);
      expect(find.text('Current'), findsNothing);
    },
  );
}
