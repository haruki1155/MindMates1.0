import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/services/admin_report_pdf_service.dart';

String extractPdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final matches = RegExp(r'stream\n([\s\S]*?)\nendstream').allMatches(raw);
  final streamText = StringBuffer();
  for (final m in matches) {
    final chunk = latin1.encode(m.group(1)!);
    try {
      streamText.writeln(latin1.decode(zlib.decode(chunk)));
    } catch (_) {
      streamText.writeln(m.group(1)!);
    }
  }
  final tokens = RegExp(r'\[\(((?:\\.|[^\\)])*)\)\]TJ')
      .allMatches(streamText.toString())
      .map(
        (m) => m
            .group(1)!
            .replaceAll(r'\(', '(')
            .replaceAll(r'\)', ')')
            .replaceAll(r'\\', r'\'),
      );
  return tokens.join(' ');
}

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

  test(
    'Appointments PDF renders KPI totals and enforces uniqueStudentsServed < 5 privacy gate across dimensions and chart types',
    () async {
      final fullBytes = await AdminReportPdfService.build(
        report: report,
        reportType: AdminReportType.appointments,
        chartType: ReportChartType.pie,
      );
      final fullText = extractPdfText(fullBytes);
      expect(fullText, contains('Total appointments'));
      expect(fullText, contains('100'));
      expect(fullText, contains('Unique students served'));
      expect(fullText, contains('80'));
      expect(fullText, contains('Counseling reach'));
      expect(fullText, contains('Completion rate'));

      final smallCohort = AdminReportAnalytics(
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
        overallActivePercentage: 50,
        userCategoryOptions: const [],
        userCategories: const [],
        appointmentDepartmentScopeKey: 'all',
        totalAppointments: 4,
        uniqueStudentsServed: 3,
        counselingReach: 1.5,
        appointmentRate: 2.0,
        completionRate: 75,
        statusCounts: const {'completed': 3},
        appointmentDepartmentScopeLabel: 'All departments',
        appointmentDepartmentOptions: const [],
        appointmentsByDepartment: const [
          ReportPercentageItem(key: 'cas', label: 'CAS', percentage: 3),
        ],
        appointmentsByCourse: const [
          ReportPercentageItem(key: 'bs psych', label: 'BS Psych', percentage: 3),
        ],
        appointmentsByYearLevel: const [
          ReportPercentageItem(key: 'year 1', label: 'Year 1', percentage: 3),
        ],
      );

      for (final dim in AppointmentReportDimension.values) {
        for (final chart in ReportChartType.values) {
          final text = extractPdfText(
            await AdminReportPdfService.build(
              report: smallCohort,
              reportType: AdminReportType.appointments,
              chartType: chart,
              appointmentDimension: dim,
            ),
          );
          expect(text, contains('fewer than 5 unique students'));
          expect(text, isNot(contains('BS Psych')));
          expect(text, isNot(contains('Percentage summary')));
        }
      }
    },
  );

  test(
    'Appointments PDF hides distribution on unconfigured population and guards zero-percentage pie charts',
    () async {
      final unconfigured = AdminReportAnalytics(
        generatedAt: DateTime.utc(2026, 9, 10),
        activeWindowDays: 30,
        population: const CounselingPopulationConfig(
          schoolYear: '2026-2027',
          departments: ['CAS'],
          populations: {},
          configured: false,
          totalPopulation: 0,
          years: [],
          status: 'current',
        ),
        userScopeKey: 'all',
        userScopeLabel: 'Whole app-user population',
        overallActivePercentage: 0,
        userCategoryOptions: const [],
        userCategories: const [],
        appointmentDepartmentScopeKey: 'all',
        totalAppointments: 6,
        uniqueStudentsServed: 5,
        counselingReach: 0,
        appointmentRate: 0,
        completionRate: 100,
        statusCounts: const {'completed': 6},
        appointmentDepartmentScopeLabel: 'All departments',
        appointmentDepartmentOptions: const [],
        appointmentsByDepartment: const [
          ReportPercentageItem(key: 'cas', label: 'CAS', percentage: 0),
        ],
        appointmentsByCourse: const [],
        appointmentsByYearLevel: const [],
      );

      final unconfiguredBytes = await AdminReportPdfService.build(
        report: unconfigured,
        reportType: AdminReportType.appointments,
        chartType: ReportChartType.pie,
      );
      expect(unconfiguredBytes.length, greaterThan(1000));
      final unconfiguredText = extractPdfText(unconfiguredBytes);
      expect(unconfiguredText, contains('Complete and save the student population'));
      expect(unconfiguredText, isNot(contains('Percentage summary')));

      final allZeroConfigured = AdminReportAnalytics(
        generatedAt: DateTime.utc(2026, 9, 10),
        activeWindowDays: 30,
        population: const CounselingPopulationConfig(
          schoolYear: '2026-2027',
          departments: ['CAS'],
          populations: {'CAS': 100},
          configured: true,
          totalPopulation: 100,
          years: [],
          status: 'current',
        ),
        userScopeKey: 'all',
        userScopeLabel: 'Whole app-user population',
        overallActivePercentage: 0,
        userCategoryOptions: const [],
        userCategories: const [],
        appointmentDepartmentScopeKey: 'all',
        totalAppointments: 6,
        uniqueStudentsServed: 5,
        counselingReach: 5,
        appointmentRate: 6,
        completionRate: 100,
        statusCounts: const {'completed': 6},
        appointmentDepartmentScopeLabel: 'All departments',
        appointmentDepartmentOptions: const [],
        appointmentsByDepartment: const [
          ReportPercentageItem(key: 'cas', label: 'CAS', percentage: 0),
        ],
        appointmentsByCourse: const [],
        appointmentsByYearLevel: const [],
      );
      final zeroPieText = extractPdfText(
        await AdminReportPdfService.build(
          report: allZeroConfigured,
          reportType: AdminReportType.appointments,
          chartType: ReportChartType.pie,
        ),
      );
      expect(zeroPieText, contains('Chart omitted'));
    },
  );

  test(
    'Users PDF shows empty state when userCategories is empty without fabricating 0% / 100%',
    () async {
      final emptyUsers = AdminReportAnalytics.fromJson({
        'generatedAt': '2026-09-10T00:00:00.000Z',
        'population': {'schoolYear': '2026-2027', 'status': 'current'},
        'users': {
          'scopeKey': 'all',
          'scopeLabel': 'Whole app-user population',
          'overallActivePercentage': 0,
          'categories': const [],
        },
      });
      final text = extractPdfText(
        await AdminReportPdfService.build(
          report: emptyUsers,
          reportType: AdminReportType.users,
          chartType: ReportChartType.pie,
        ),
      );
      expect(text, contains('No reportable data is available'));
      expect(text, isNot(contains('No activity in reporting window')));
    },
  );

  test('8-item bar chart renders all 7 top labels plus Remaining categories without truncation', () async {
    final nineItems = List.generate(
      9,
      (i) => ReportPercentageItem(
        key: 'course-$i',
        label: 'ProgramLabel${i + 1}',
        percentage: 10.0 - i,
      ),
    );
    final manyCourses = AdminReportAnalytics(
      generatedAt: DateTime.utc(2026, 9, 10),
      activeWindowDays: 30,
      population: const CounselingPopulationConfig(
        schoolYear: '2026-2027',
        departments: ['CAS'],
        populations: {'CAS': 100},
        configured: true,
        totalPopulation: 100,
        years: [],
        status: 'current',
      ),
      userScopeKey: 'all',
      userScopeLabel: 'Whole app-user population',
      overallActivePercentage: 50,
      userCategoryOptions: const [],
      userCategories: const [],
      appointmentDepartmentScopeKey: 'all',
      totalAppointments: 25,
      uniqueStudentsServed: 20,
      counselingReach: 20,
      appointmentRate: 25,
      completionRate: 80,
      statusCounts: const {'completed': 20},
      appointmentDepartmentScopeLabel: 'All departments',
      appointmentDepartmentOptions: const [],
      appointmentsByDepartment: const [],
      appointmentsByCourse: nineItems,
      appointmentsByYearLevel: const [],
    );
    final text = extractPdfText(
      await AdminReportPdfService.build(
        report: manyCourses,
        reportType: AdminReportType.appointments,
        chartType: ReportChartType.bar,
        appointmentDimension: AppointmentReportDimension.course,
      ),
    );
    for (var i = 1; i <= 7; i++) {
      expect(text, contains('ProgramLabel$i'));
    }
    expect(text, contains('Remaining categories'));
  });

  test('Emotional Activity PDF includes summary metrics matching preview', () async {
    final emotionalReport = AdminReportAnalytics.fromJson({
      'generatedAt': '2026-11-16T04:00:00Z',
      'population': {
        'schoolYear': '2026-2027',
        'configured': true,
        'status': 'current',
        'departments': ['CAS'],
        'populations': {'CAS': 100},
        'totalPopulation': 100,
      },
      'emotionalActivity': {
        'status': 'ready',
        'suppressed': false,
        'suppressionThreshold': 10,
        'sourceScopeKey': 'all',
        'sourceScopeLabel': 'All approved sources',
        'schoolYear': '2026-2027',
        'dateRangeLabel': 'Academic year 2026-2027',
        'participationRate': 25.0,
        'dominantValenceLabel': 'Positive (Levels 4-5)',
        'moodCheckInShare': 62.5,
        'assessmentShare': 37.5,
        'valenceBreakdown': [
          {
            'key': 'positive',
            'label': 'Positive (Levels 4-5)',
            'percentage': 70.0,
            'suppressed': false,
          },
        ],
      },
    });
    final text = extractPdfText(
      await AdminReportPdfService.build(
        report: emotionalReport,
        reportType: AdminReportType.emotionalActivity,
        chartType: ReportChartType.bar,
      ),
    );
    expect(text, contains('Population participation'));
    expect(text, contains('25%'));
    expect(text, contains('Primary emotional pattern'));
    expect(text, contains('Positive (Levels 4-5)'));
  });

  test('Emotional Activity PDF falls back to appUserCohortShare when participationRate is null', () async {
    final cohortOnlyReport = AdminReportAnalytics.fromJson({
      'generatedAt': '2026-11-16T04:00:00Z',
      'population': {
        'schoolYear': '2026-2027',
        'configured': false,
        'status': 'current',
      },
      'emotionalActivity': {
        'status': 'ready',
        'suppressed': false,
        'suppressionThreshold': 10,
        'sourceScopeKey': 'all',
        'sourceScopeLabel': 'All approved sources',
        'schoolYear': '2026-2027',
        'dateRangeLabel': 'Academic year 2026-2027',
        'participationRate': null,
        'appUserCohortShare': 42.5,
        'dominantValenceLabel': 'Positive (Levels 4-5)',
        'valenceBreakdown': [
          {
            'key': 'positive',
            'label': 'Positive (Levels 4-5)',
            'percentage': 70.0,
            'suppressed': false,
          },
        ],
      },
    });
    final text = extractPdfText(
      await AdminReportPdfService.build(
        report: cohortOnlyReport,
        reportType: AdminReportType.emotionalActivity,
        chartType: ReportChartType.bar,
      ),
    );
    expect(text, contains('42.5%'));
    expect(text, isNot(contains('Not available')));
  });

  test('Users PDF renders Selected app-user category only table when userCategoryKey != all', () async {
    final multiCategoryReport = AdminReportAnalytics.fromJson({
      'generatedAt': '2026-11-16T04:00:00Z',
      'population': {
        'schoolYear': '2026-2027',
        'configured': true,
        'status': 'current',
      },
      'users': {
        'scopeKey': 'students',
        'scopeLabel': 'Students',
        'overallActivePercentage': 50,
        'categories': [
          {
            'key': 'students',
            'label': 'Students',
            'populationPercentage': 30,
            'activePercentage': 50,
          },
          {
            'key': 'faculty',
            'label': 'Faculty',
            'populationPercentage': 70,
            'activePercentage': 20,
          },
        ],
      },
    });
    final text = extractPdfText(
      await AdminReportPdfService.build(
        report: multiCategoryReport,
        reportType: AdminReportType.users,
        chartType: ReportChartType.bar,
        userCategoryKey: 'students',
      ),
    );
    expect(text, contains('Selected app-user category only'));
    expect(text, contains('Students'));
    expect(text, contains('30%'));
    expect(text, contains('50%'));
    expect(text, isNot(contains('Faculty')));
    expect(text, isNot(contains('70%')));
  });

  test('AdminReportPdfService pie chart safely handles NaN and Infinity percentages without throwing', () async {
    final badItemsReport = AdminReportAnalytics.fromJson({
      'generatedAt': '2026-11-16T04:00:00Z',
      'population': {
        'schoolYear': '2026-2027',
        'configured': true,
        'status': 'current',
        'departments': ['CAS'],
        'populations': {'CAS': 100},
        'totalPopulation': 100,
      },
      'appointments': {
        'totalAppointments': 10,
        'uniqueStudentsServed': 8,
        'department': [
          {'key': 'x', 'label': 'X', 'percentage': 'NaN'},
          {'key': 'y', 'label': 'Y', 'percentage': 'Infinity'},
        ],
      },
    });
    final bytes = await AdminReportPdfService.build(
      report: badItemsReport,
      reportType: AdminReportType.appointments,
      chartType: ReportChartType.pie,
    );
    expect(bytes.length, greaterThan(1000));
  });
}
