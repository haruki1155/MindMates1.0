enum ReportChartType { pie, bar }

enum AdminReportType { users, appointments }

enum AppointmentReportDimension { department, course, yearLevel }

class WalkInAppointmentImportRow {
  const WalkInAppointmentImportRow({
    required this.fullName,
    required this.studentId,
    required this.department,
    required this.course,
    required this.yearLevel,
    this.loggedAt,
  });

  final String fullName;
  final String studentId;
  final String department;
  final String course;
  final String yearLevel;
  final DateTime? loggedAt;

  String get departmentCourse => course;

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'studentId': studentId,
    'department': department,
    'course': course,
    'yearLevel': yearLevel,
    if (loggedAt != null) 'loggedAt': loggedAt!.toIso8601String(),
  };
}

class ReportFilterOption {
  const ReportFilterOption({required this.key, required this.label});

  final String key;
  final String label;

  factory ReportFilterOption.fromJson(Map<String, dynamic> json) =>
      ReportFilterOption(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Not specified',
      );
}

class ReportPercentageItem {
  const ReportPercentageItem({
    required this.key,
    required this.label,
    required this.percentage,
  });

  final String key;
  final String label;
  final double percentage;

  factory ReportPercentageItem.fromJson(Map<String, dynamic> json) =>
      ReportPercentageItem(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Not specified',
        percentage: _number(json['percentage']),
      );
}

class UserCategoryReport {
  const UserCategoryReport({
    required this.key,
    required this.label,
    required this.populationPercentage,
    required this.activePercentage,
  });

  final String key;
  final String label;
  final double populationPercentage;
  final double activePercentage;

  factory UserCategoryReport.fromJson(Map<String, dynamic> json) =>
      UserCategoryReport(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Category',
        populationPercentage: _number(json['populationPercentage']),
        activePercentage: _number(json['activePercentage']),
      );
}

class AdminReportAnalytics {
  const AdminReportAnalytics({
    required this.generatedAt,
    required this.activeWindowDays,
    required this.population,
    required this.userScopeKey,
    required this.userScopeLabel,
    required this.overallActivePercentage,
    required this.userCategoryOptions,
    required this.userCategories,
    required this.appointmentDepartmentScopeKey,
    required this.totalAppointments,
    required this.uniqueStudentsServed,
    required this.counselingReach,
    required this.appointmentRate,
    required this.completionRate,
    required this.statusCounts,
    required this.appointmentDepartmentScopeLabel,
    required this.appointmentDepartmentOptions,
    required this.appointmentsByDepartment,
    required this.appointmentsByCourse,
    required this.appointmentsByYearLevel,
  });

  final DateTime generatedAt;
  final int activeWindowDays;
  final CounselingPopulationConfig population;
  final String userScopeKey;
  final String userScopeLabel;
  final double overallActivePercentage;
  final List<ReportFilterOption> userCategoryOptions;
  final List<UserCategoryReport> userCategories;
  final String appointmentDepartmentScopeKey;
  final int totalAppointments;
  final int uniqueStudentsServed;
  final double counselingReach;
  final double appointmentRate;
  final double completionRate;
  final Map<String, int> statusCounts;
  final String appointmentDepartmentScopeLabel;
  final List<ReportFilterOption> appointmentDepartmentOptions;
  final List<ReportPercentageItem> appointmentsByDepartment;
  final List<ReportPercentageItem> appointmentsByCourse;
  final List<ReportPercentageItem> appointmentsByYearLevel;

  List<ReportPercentageItem> appointmentsFor(
    AppointmentReportDimension dimension,
  ) => switch (dimension) {
    AppointmentReportDimension.department => appointmentsByDepartment,
    AppointmentReportDimension.course => appointmentsByCourse,
    AppointmentReportDimension.yearLevel => appointmentsByYearLevel,
  };

  factory AdminReportAnalytics.fromJson(Map<String, dynamic> json) {
    final users = _map(json['users']);
    final appointments = _map(json['appointments']);
    return AdminReportAnalytics(
      generatedAt:
          DateTime.tryParse(json['generatedAt']?.toString() ?? '') ??
          DateTime.now(),
      activeWindowDays: _integer(json['activeWindowDays'], 30),
      population: CounselingPopulationConfig.fromJson(_map(json['population'])),
      userScopeKey: users['scopeKey']?.toString() ?? 'all',
      userScopeLabel:
          users['scopeLabel']?.toString() ?? 'Whole app-user population',
      overallActivePercentage: _number(users['overallActivePercentage']),
      userCategoryOptions: _options(users['categoryOptions']),
      userCategories: _list(
        users['categories'],
      ).map(UserCategoryReport.fromJson).toList(growable: false),
      appointmentDepartmentScopeKey:
          appointments['departmentScopeKey']?.toString() ?? 'all',
      totalAppointments: _integer(appointments['totalAppointments'], 0),
      uniqueStudentsServed: _integer(appointments['uniqueStudentsServed'], 0),
      counselingReach: _number(appointments['counselingReach']),
      appointmentRate: _number(appointments['appointmentRate']),
      completionRate: _number(appointments['completionRate']),
      statusCounts: _integerMap(appointments['statusCounts']),
      appointmentDepartmentScopeLabel:
          appointments['departmentScopeLabel']?.toString() ?? 'All departments',
      appointmentDepartmentOptions: _options(appointments['departmentOptions']),
      appointmentsByDepartment: _percentageItems(appointments['department']),
      appointmentsByCourse: _percentageItems(appointments['course']),
      appointmentsByYearLevel: _percentageItems(appointments['yearLevel']),
    );
  }
}

class CounselingPopulationConfig {
  const CounselingPopulationConfig({
    required this.schoolYear,
    required this.departments,
    required this.populations,
    required this.configured,
    required this.totalPopulation,
    required this.years,
    required this.status,
  });

  final String schoolYear;
  final List<String> departments;
  final Map<String, int> populations;
  final bool configured;
  final int totalPopulation;
  final List<AcademicYearRecord> years;
  final String status;

  factory CounselingPopulationConfig.fromJson(Map<String, dynamic> json) {
    final rawPopulations = json['populations'];
    final populations = <String, int>{};
    if (rawPopulations is Map) {
      for (final entry in rawPopulations.entries) {
        final value = entry.value;
        if (value is num && value > 0) {
          populations[entry.key.toString()] = value.toInt();
        }
      }
    }
    return CounselingPopulationConfig(
      schoolYear: json['schoolYear']?.toString() ?? '',
      departments: json['departments'] is List
          ? (json['departments'] as List)
                .map((item) => item.toString())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const [],
      populations: populations,
      configured: json['configured'] == true,
      totalPopulation: _integer(json['totalPopulation'], 0),
      status: json['status']?.toString() ?? 'current',
      years: json['years'] is List
          ? (json['years'] as List)
                .whereType<Map>()
                .map(
                  (item) => AcademicYearRecord.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class AcademicYearRecord {
  const AcademicYearRecord({
    required this.schoolYear,
    required this.startDate,
    required this.endDate,
    required this.status,
  });
  final String schoolYear;
  final String startDate;
  final String endDate;
  final String status;
  factory AcademicYearRecord.fromJson(Map<String, dynamic> json) =>
      AcademicYearRecord(
        schoolYear: json['schoolYear']?.toString() ?? '',
        startDate: json['startDate']?.toString() ?? '',
        endDate: json['endDate']?.toString() ?? '',
        status: json['status']?.toString() ?? 'current',
      );
}

List<ReportPercentageItem> _percentageItems(Object? value) =>
    _list(value).map(ReportPercentageItem.fromJson).toList(growable: false);

List<ReportFilterOption> _options(Object? value) =>
    _list(value).map(ReportFilterOption.fromJson).toList(growable: false);

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

double _number(Object? value) => value is num
    ? value.toDouble().clamp(0, double.infinity)
    : (double.tryParse(value?.toString() ?? '') ?? 0).clamp(0, double.infinity);

int _integer(Object? value, int fallback) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;

Map<String, int> _integerMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.value is num)
        entry.key.toString(): (entry.value as num).toInt(),
  };
}
