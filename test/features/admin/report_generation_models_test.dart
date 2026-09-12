import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';

void main() {
  test('parses privacy-safe report analytics', () {
    final report = AdminReportAnalytics.fromJson({
      'generatedAt': '2026-09-10T00:00:00.000Z',
      'activeWindowDays': 30,
      'users': {
        'scopeKey': 'student',
        'scopeLabel': 'Students',
        'overallActivePercentage': 62.5,
        'categoryOptions': [
          {'key': 'student', 'label': 'Students'},
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
        'departmentScopeKey': 'cas',
        'departmentScopeLabel': 'CAS',
        'departmentOptions': [
          {'key': 'cas', 'label': 'CAS'},
        ],
        'department': [
          {'key': 'cas', 'label': 'CAS', 'percentage': 75},
        ],
        'course': [],
        'yearLevel': [],
      },
    });

    expect(report.overallActivePercentage, 62.5);
    expect(report.userScopeLabel, 'Students');
    expect(report.appointmentDepartmentScopeLabel, 'CAS');
    expect(report.userCategories.single.label, 'Students');
    expect(
      report
          .appointmentsFor(AppointmentReportDimension.department)
          .single
          .percentage,
      75,
    );
  });
}
