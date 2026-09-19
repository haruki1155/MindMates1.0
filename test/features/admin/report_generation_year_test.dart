import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/features/admin/screens/report_generation_page.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _ReportRepository extends AdminPortalRepository {
  final requestedYears = <String>[];
  bool configured = true;

  @override
  AccessRole get currentAccessRole => AccessRole.admin;

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
        'status': year == '2025-2026' ? 'closed' : 'current',
        'departments': ['College of Computing'],
        'populations': {
          'College of Computing': year == '2025-2026' ? 120 : 240,
        },
        'totalPopulation': configured ? (year == '2025-2026' ? 120 : 240) : 0,
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
  testWidgets('report actions fit on a narrow desktop viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
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
    expect(tester.takeException(), isNull);
  });

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
}
