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
}
