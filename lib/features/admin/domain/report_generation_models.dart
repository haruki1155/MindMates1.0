enum ReportChartType { pie, bar }

enum AdminReportType { users, appointments, emotionalActivity }

enum EmotionalActivitySource {
  all('all', 'All sources'),
  mood('mood', 'Mood check-ins'),
  assessment('assessment', 'Assessments');

  const EmotionalActivitySource(this.wireKey, this.label);
  final String wireKey;
  final String label;
}

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

class ImportedWalkInFile {
  const ImportedWalkInFile({
    required this.id,
    required this.fileName,
    required this.rowCount,
    required this.importedAt,
    required this.archived,
  });

  final String id;
  final String fileName;
  final int rowCount;
  final DateTime importedAt;
  final bool archived;

  factory ImportedWalkInFile.fromJson(Map<String, dynamic> json) =>
      ImportedWalkInFile(
        id: json['id']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? 'Imported walk-in entries',
        rowCount: (json['rowCount'] as num?)?.toInt() ?? 0,
        importedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['importedAtMillis'] as num?)?.toInt() ?? 0,
        ).toLocal(),
        archived: json['archived'] == true,
      );
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
    this.dateRange = const ReportDateRange(
      startDate: null,
      endDate: null,
      label: 'Selected period',
    ),
    this.comparison,
    this.trends = const [],
    this.waitingTimeDays,
    this.rescheduledAppointments = 0,
    this.emotionalActivity = const EmotionalActivityReport.empty(),
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
  final ReportDateRange dateRange;
  final ReportComparison? comparison;
  final List<ReportTrendPoint> trends;
  final double? waitingTimeDays;
  final int rescheduledAppointments;
  final EmotionalActivityReport emotionalActivity;

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
      dateRange: ReportDateRange.fromJson(_map(json['dateRange'])),
      comparison: json['comparison'] is Map
          ? ReportComparison.fromJson(_map(json['comparison']))
          : null,
      trends: _list(
        json['trends'],
      ).map(ReportTrendPoint.fromJson).toList(growable: false),
      waitingTimeDays: _nullableNumber(appointments['waitingTimeDays']),
      rescheduledAppointments: _integer(
        appointments['rescheduledAppointments'],
        0,
      ),
      emotionalActivity: json['emotionalActivity'] is Map
          ? EmotionalActivityReport.fromJson(_map(json['emotionalActivity']))
          : const EmotionalActivityReport.empty(),
    );
  }
}

class EmotionalActivityBucket {
  const EmotionalActivityBucket({
    required this.key,
    required this.label,
    required this.percentage,
    required this.suppressed,
  });

  final String key;
  final String label;
  final double? percentage;
  final bool suppressed;

  factory EmotionalActivityBucket.fromJson(Map<String, dynamic> json) =>
      EmotionalActivityBucket(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Category',
        percentage: json['suppressed'] == true
            ? null
            : _nullableNumber(json['percentage']),
        suppressed: json['suppressed'] == true,
      );
}

class EmotionalActivityReport {
  const EmotionalActivityReport({
    required this.status,
    required this.suppressed,
    required this.suppressionThreshold,
    required this.suppressionReason,
    required this.sourceScopeKey,
    required this.sourceScopeLabel,
    required this.schoolYear,
    required this.dateRangeLabel,
    required this.participationRate,
    required this.appUserCohortShare,
    required this.dominantValenceLabel,
    required this.hasMixedCategories,
    required this.moodCheckInShare,
    required this.assessmentShare,
    required this.departmentOptions,
    required this.valenceBreakdown,
    required this.moodBreakdown,
    required this.assessmentBreakdown,
    required this.periodTrends,
    required this.departmentCoverageNote,
  });

  const EmotionalActivityReport.empty()
    : status = 'no_data',
      suppressed = false,
      suppressionThreshold = 10,
      suppressionReason = null,
      sourceScopeKey = 'all',
      sourceScopeLabel = 'All approved sources',
      schoolYear = '',
      dateRangeLabel = 'Selected period',
      participationRate = null,
      appUserCohortShare = null,
      dominantValenceLabel = null,
      hasMixedCategories = false,
      moodCheckInShare = null,
      assessmentShare = null,
      departmentOptions = const [],
      valenceBreakdown = const [],
      moodBreakdown = const [],
      assessmentBreakdown = const [],
      periodTrends = const [],
      departmentCoverageNote = '';

  final String status;
  final bool suppressed;
  final int suppressionThreshold;
  final String? suppressionReason;
  final String sourceScopeKey;
  final String sourceScopeLabel;
  final String schoolYear;
  final String dateRangeLabel;
  final double? participationRate;
  final double? appUserCohortShare;
  final String? dominantValenceLabel;
  final bool hasMixedCategories;
  final double? moodCheckInShare;
  final double? assessmentShare;
  final List<ReportFilterOption> departmentOptions;
  final List<EmotionalActivityBucket> valenceBreakdown;
  final List<EmotionalActivityBucket> moodBreakdown;
  final List<EmotionalActivityBucket> assessmentBreakdown;
  final List<EmotionalActivityBucket> periodTrends;
  final String departmentCoverageNote;

  bool get isReady => status == 'ready' && !suppressed;
  bool get isEmpty => status == 'no_data';

  factory EmotionalActivityReport.fromJson(Map<String, dynamic> json) =>
      EmotionalActivityReport(
        status: json['status']?.toString() ?? 'no_data',
        suppressed: json['suppressed'] == true,
        suppressionThreshold: _integer(json['suppressionThreshold'], 10),
        suppressionReason: json['suppressionReason']?.toString(),
        sourceScopeKey: json['sourceScopeKey']?.toString() ?? 'all',
        sourceScopeLabel:
            json['sourceScopeLabel']?.toString() ?? 'All approved sources',
        schoolYear: json['schoolYear']?.toString() ?? '',
        dateRangeLabel: json['dateRangeLabel']?.toString() ?? 'Selected period',
        participationRate: _nullableNumber(json['participationRate']),
        appUserCohortShare: _nullableNumber(json['appUserCohortShare']),
        dominantValenceLabel: json['dominantValenceLabel']?.toString(),
        hasMixedCategories: json['hasMixedCategories'] == true,
        moodCheckInShare: _nullableNumber(json['moodCheckInShare']),
        assessmentShare: _nullableNumber(json['assessmentShare']),
        departmentOptions: _options(json['departmentOptions']),
        valenceBreakdown: _list(
          json['valenceBreakdown'],
        ).map(EmotionalActivityBucket.fromJson).toList(growable: false),
        moodBreakdown: _list(
          json['moodBreakdown'],
        ).map(EmotionalActivityBucket.fromJson).toList(growable: false),
        assessmentBreakdown: _list(
          json['assessmentBreakdown'],
        ).map(EmotionalActivityBucket.fromJson).toList(growable: false),
        periodTrends: _list(
          json['periodTrends'],
        ).map(EmotionalActivityBucket.fromJson).toList(growable: false),
        departmentCoverageNote:
            json['departmentCoverageNote']?.toString() ?? '',
      );
}

double? _nullableNumber(Object? value) => value == null ? null : _number(value);

class ReportDateRange {
  const ReportDateRange({
    required this.startDate,
    required this.endDate,
    required this.label,
  });
  final DateTime? startDate;
  final DateTime? endDate;
  final String label;
  factory ReportDateRange.fromJson(Map<String, dynamic> json) =>
      ReportDateRange(
        startDate: DateTime.tryParse(json['startDate']?.toString() ?? ''),
        endDate: DateTime.tryParse(json['endDate']?.toString() ?? ''),
        label: json['label']?.toString() ?? 'Selected period',
      );
}

class ReportComparison {
  const ReportComparison({
    required this.schoolYear,
    required this.totalAppointments,
    required this.uniqueStudentsServed,
    required this.counselingReach,
    required this.completionRate,
  });
  final String schoolYear;
  final int totalAppointments;
  final int uniqueStudentsServed;
  final double counselingReach;
  final double completionRate;
  factory ReportComparison.fromJson(Map<String, dynamic> json) =>
      ReportComparison(
        schoolYear: json['schoolYear']?.toString() ?? '',
        totalAppointments: _integer(json['totalAppointments'], 0),
        uniqueStudentsServed: _integer(json['uniqueStudentsServed'], 0),
        counselingReach: _number(json['counselingReach']),
        completionRate: _number(json['completionRate']),
      );
}

class ReportTrendPoint {
  const ReportTrendPoint({
    required this.schoolYear,
    required this.totalAppointments,
    required this.uniqueStudentsServed,
    required this.counselingReach,
    required this.completedAppointments,
  });
  final String schoolYear;
  final int totalAppointments;
  final int uniqueStudentsServed;
  final double counselingReach;
  final int completedAppointments;
  factory ReportTrendPoint.fromJson(Map<String, dynamic> json) =>
      ReportTrendPoint(
        schoolYear: json['schoolYear']?.toString() ?? '',
        totalAppointments: _integer(json['totalAppointments'], 0),
        uniqueStudentsServed: _integer(json['uniqueStudentsServed'], 0),
        counselingReach: _number(json['counselingReach']),
        completedAppointments: _integer(json['completedAppointments'], 0),
      );
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

enum AcademicYearPeriodState { current, upcoming, closed }

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

  bool get isClosed => status == 'closed';

  AcademicYearPeriodState periodState({DateTime? now}) {
    if (isClosed) return AcademicYearPeriodState.closed;
    final reference = (now ?? DateTime.now()).toLocal();
    final todayKey =
        '${reference.year.toString().padLeft(4, '0')}-'
        '${reference.month.toString().padLeft(2, '0')}-'
        '${reference.day.toString().padLeft(2, '0')}';
    if (startDate.isNotEmpty && todayKey.compareTo(startDate) < 0) {
      return AcademicYearPeriodState.upcoming;
    }
    return AcademicYearPeriodState.current;
  }

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
