import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/services/admin_report_pdf_service.dart';

void main() {
  final report = AdminReportAnalytics(
    generatedAt: DateTime.utc(2026, 9, 10),
    activeWindowDays: 30,
    population: CounselingPopulationConfig(
      schoolYear: '2026-2027',
      departments: const ['CAS', 'COE'],
      populations: const {'CAS': 100, 'COE': 100},
      configured: true,
      totalPopulation: 200,
      years: const [],
      status: 'current',
    ),
    userScopeKey: 'all',
    userScopeLabel: 'Whole app-user population',
    overallActivePercentage: 62.5,
    userCategoryOptions: const [
      ReportFilterOption(key: 'student', label: 'Students'),
    ],
    userCategories: const [
      UserCategoryReport(
        key: 'student',
        label: 'Students',
        populationPercentage: 80,
        activePercentage: 60,
      ),
    ],
    appointmentDepartmentScopeKey: 'all',
    totalAppointments: 100,
    uniqueStudentsServed: 80,
    counselingReach: 40,
    appointmentRate: 50,
    completionRate: 90,
    statusCounts: const {'completed': 90},
    appointmentDepartmentScopeLabel: 'All departments',
    appointmentDepartmentOptions: const [
      ReportFilterOption(key: 'cas', label: 'CAS'),
      ReportFilterOption(key: 'coe', label: 'COE'),
    ],
    appointmentsByDepartment: const [
      ReportPercentageItem(key: 'cas', label: 'CAS', percentage: 75),
      ReportPercentageItem(key: 'coe', label: 'COE', percentage: 25),
    ],
    appointmentsByCourse: const [],
    appointmentsByYearLevel: const [],
  );

  for (final chartType in ReportChartType.values) {
    test('builds a ${chartType.name} report PDF', () async {
      final bytes = await AdminReportPdfService.build(
        report: report,
        reportType: AdminReportType.appointments,
        chartType: chartType,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });
  }

  test(
    'builds all 3 report types with filters metadata and deterministic filename',
    () async {
      final filteredReport = AdminReportAnalytics.fromJson({
        'generatedAt': '2026-11-16T04:00:00Z',
        'dateRange': {
          'startDate': '2026-06-01T00:00:00+08:00',
          'endDate': '2026-12-01T00:00:00+08:00',
          'label': '1st semester',
        },
        'filters': {
          'schoolYear': '2026-2027',
          'periodLabel': '1st semester',
          'userCategory': 'student',
          'userCategoryLabel': 'Students',
          'collegeKey': 'cas',
          'collegeLabel': 'College of Arts and Sciences',
          'programKey': 'ba psychology',
          'programLabel': 'BA Psychology',
          'emotionalSource': 'mood',
          'emotionalSourceLabel': 'Mood check-ins only',
        },
        'population': {
          'schoolYear': '2026-2027',
          'configured': true,
          'status': 'current',
          'departments': ['CAS'],
          'populations': {'CAS': 120},
          'totalPopulation': 120,
        },
        'users': {
          'scopeKey': 'student',
          'scopeLabel': 'Students',
          'overallActivePercentage': 55.0,
          'categories': [
            {
              'key': 'student',
              'label': 'Students',
              'populationPercentage': 100.0,
              'activePercentage': 55.0,
            },
          ],
        },
        'appointments': {
          'totalAppointments': 14,
          'uniqueStudentsServed': 11,
          'counselingReach': 9.2,
          'appointmentRate': 11.7,
          'completionRate': 85.7,
          'departmentScopeKey': 'cas',
          'departmentScopeLabel': 'College of Arts and Sciences',
          'department': [
            {'key': 'cas', 'label': 'CAS', 'percentage': 100.0},
          ],
        },
        'emotionalActivity': {
          'status': 'ready',
          'suppressed': false,
          'suppressionThreshold': 10,
          'sourceScopeKey': 'mood',
          'sourceScopeLabel': 'Mood check-ins only',
          'schoolYear': '2026-2027',
          'dateRangeLabel': '1st semester',
          'participationRate': 20.0,
          'dominantValenceLabel': 'Positive (Levels 4-5)',
          'valenceBreakdown': [
            {
              'key': 'positive',
              'label': 'Positive (Levels 4-5)',
              'percentage': 75.0,
              'suppressed': false,
            },
          ],
        },
      });

      expect(
        AdminReportPdfService.filenameFor(
          filteredReport,
          AdminReportType.emotionalActivity,
        ),
        'mindmate_emotional_activity_2026_2027_college_of_arts_and_sciences_ba_psychology_2026-11-16.pdf',
      );

      for (final reportType in AdminReportType.values) {
        final bytes = await AdminReportPdfService.build(
          report: filteredReport,
          reportType: reportType,
          chartType: ReportChartType.bar,
          userCategoryKey: 'student',
        );
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(1000));
      }
    },
  );
}
