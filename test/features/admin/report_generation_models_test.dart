import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _ClinicalReportRepository extends AdminPortalRepository {
  _ClinicalReportRepository({super.callableInvoker});

  @override
  AccessRole get currentAccessRole => AccessRole.admin;
}

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

  test(
    'CounselingPopulationConfig.preferredReportableYear prefers current, then latest closed, else null',
    () {
      final withCurrent = CounselingPopulationConfig.fromJson({
        'schoolYear': '2026-2027',
        'status': 'unknown',
        'years': [
          {
            'schoolYear': '2027-2028',
            'startDate': '2027-06-01',
            'endDate': '2028-05-31',
            'status': 'planned',
          },
          {
            'schoolYear': '2025-2026',
            'startDate': '2025-06-01',
            'endDate': '2026-05-31',
            'status': 'current',
          },
          {
            'schoolYear': '2024-2025',
            'startDate': '2024-06-01',
            'endDate': '2025-05-31',
            'status': 'closed',
          },
        ],
      });
      expect(withCurrent.isReportable, isFalse);
      expect(withCurrent.preferredReportableYear?.schoolYear, '2025-2026');

      final onlyClosed = CounselingPopulationConfig.fromJson({
        'schoolYear': '2026-2027',
        'status': 'unknown',
        'years': [
          {
            'schoolYear': '2027-2028',
            'startDate': '2027-06-01',
            'endDate': '2028-05-31',
            'status': 'planned',
          },
          {
            'schoolYear': '2024-2025',
            'startDate': '2024-06-01',
            'endDate': '2025-05-31',
            'status': 'closed',
          },
          {
            'schoolYear': '2023-2024',
            'startDate': '2023-06-01',
            'endDate': '2024-05-31',
            'status': 'closed',
          },
        ],
      });
      expect(onlyClosed.preferredReportableYear?.schoolYear, '2024-2025');

      final noneReportable = CounselingPopulationConfig.fromJson({
        'schoolYear': '2026-2027',
        'status': 'unknown',
        'years': [
          {
            'schoolYear': '2027-2028',
            'startDate': '2027-06-01',
            'endDate': '2028-05-31',
            'status': 'planned',
          },
          {
            'schoolYear': '2025-2026',
            'startDate': '2025-06-01',
            'endDate': '2026-05-31',
            'status': 'voided',
          },
          {
            'schoolYear': '2024-2025',
            'startDate': '2024-06-01',
            'endDate': '2025-05-31',
            'status': 'unknown',
          },
        ],
      });
      expect(noneReportable.preferredReportableYear, isNull);
    },
  );

  test(
    'AdminPortalRepository.fetchFilteredReportAnalytics routes via callableInvoker and parses report',
    () async {
      String? calledName;
      Map<String, Object?>? calledData;
      final repo = _ClinicalReportRepository(
        callableInvoker: (name, data) async {
          calledName = name;
          calledData = data;
          return {
            'report': {
              'generatedAt': '2026-09-10T00:00:00.000Z',
              'population': {'schoolYear': '2025-2026', 'status': 'current'},
              'appointments': {
                'totalAppointments': 7,
                'uniqueStudentsServed': 6,
              },
            },
          };
        },
      );

      final report = await repo.fetchFilteredReportAnalytics(
        userCategory: 'student',
        appointmentDepartment: 'cas',
        program: 'bsit',
        periodLabel: '1st semester',
      );
      expect(calledName, 'getReportAnalytics');
      expect(calledData?['userCategory'], 'student');
      expect(calledData?['appointmentDepartment'], 'cas');
      expect(calledData?['program'], 'bsit');
      expect(calledData?.containsKey('schoolYear'), isFalse);
      expect(report.population.schoolYear, '2025-2026');
      expect(
        report.appointmentsFor(AppointmentReportDimension.department),
        isEmpty,
      );
      expect(report.totalAppointments, 7);
      expect(
        () => _ClinicalReportRepository(
          callableInvoker: (_, _) async => throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Planned',
          ),
        ).fetchFilteredReportAnalytics(),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    },
  );

  test('ReportPercentageItem.fromJson normalizes NaN and Infinity to 0.0', () {
    final nanItem = ReportPercentageItem.fromJson({
      'key': 'x',
      'label': 'X',
      'percentage': 'NaN',
    });
    final infItem = ReportPercentageItem.fromJson({
      'key': 'y',
      'label': 'Y',
      'percentage': 'Infinity',
    });
    final doubleNanItem = ReportPercentageItem.fromJson({
      'key': 'z',
      'label': 'Z',
      'percentage': double.nan,
    });

    expect(nanItem.percentage, 0.0);
    expect(nanItem.percentage.isFinite, isTrue);
    expect(infItem.percentage, 0.0);
    expect(infItem.percentage.isFinite, isTrue);
    expect(doubleNanItem.percentage, 0.0);
    expect(doubleNanItem.percentage.isFinite, isTrue);
  });
}
