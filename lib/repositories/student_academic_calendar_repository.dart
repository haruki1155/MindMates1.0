import 'package:cloud_functions/cloud_functions.dart';

import '../features/mood/domain/mood_v2_analytics.dart';
import '../services/firebase/firebase_callable_router.dart';

enum StudentSemesterRangeSource { configured, reportGrouping }

class StudentSemesterRange {
  const StudentSemesterRange({
    required this.id,
    required this.label,
    required this.startDateKey,
    required this.endExclusiveDateKey,
    required this.source,
  });

  final String id;
  final String label;
  final String startDateKey;
  final String endExclusiveDateKey;
  final StudentSemesterRangeSource source;

  MoodWeekRange get range => MoodWeekRange(
    startDateKey: startDateKey,
    endExclusiveDateKey: endExclusiveDateKey,
  );

  bool get isApproximateReportGrouping =>
      source == StudentSemesterRangeSource.reportGrouping;
}

class StudentAcademicYear {
  const StudentAcademicYear({
    required this.schoolYear,
    required this.startDateKey,
    required this.endExclusiveDateKey,
    required this.status,
    required this.semesterRanges,
  });

  final String schoolYear;
  final String startDateKey;
  final String endExclusiveDateKey;
  final String status;
  final List<StudentSemesterRange> semesterRanges;

  MoodWeekRange get range => MoodWeekRange(
    startDateKey: startDateKey,
    endExclusiveDateKey: endExclusiveDateKey,
  );

  bool get isCurrent => status == 'current';
}

class StudentAcademicCalendarRepository {
  StudentAcademicCalendarRepository({
    FirebaseFunctions? functions,
    Future<Map<String, dynamic>> Function()? caller,
  }) : _caller =
           caller ??
           (() async {
             final callable = (functions ?? FirebaseFunctions.instance)
                 .routedCallable('getStudentAcademicCalendar');
             final response = await callable.call<dynamic>();
             final raw = response.data;
             if (raw is Map) {
               return raw.map((key, value) => MapEntry(key.toString(), value));
             }
             return const <String, dynamic>{};
           });

  final Future<Map<String, dynamic>> Function() _caller;

  static final RegExp _schoolYearPattern = RegExp(r'^(\d{4})-(\d{4})$');
  static const Set<String> _allowedStatuses = {'current', 'closed', 'planned'};

  static bool _isValidDateKey(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    try {
      MoodManilaCalendar.dateForKey(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  static bool _isValidSchoolYear(String value) {
    final match = _schoolYearPattern.firstMatch(value);
    if (match == null) return false;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (start == null || end == null) return false;
    return start >= 2000 && start <= 2100 && end == start + 1;
  }

  Future<List<StudentAcademicYear>> fetchAcademicYears() async {
    final data = await _caller();
    return parseAcademicYears(data['years']);
  }

  static List<StudentAcademicYear> parseAcademicYears(Object? rawYears) {
    if (rawYears is! List) return const [];
    final parsed = <StudentAcademicYear>[];

    for (final rawItem in rawYears) {
      if (rawItem is! Map) continue;
      final item = rawItem.map((k, v) => MapEntry(k.toString(), v));
      final schoolYear = (item['schoolYear'] ?? '').toString().trim();
      final startDateKey = (item['startDateKey'] ?? '').toString().trim();
      final endExclusiveDateKey = (item['endExclusiveDateKey'] ?? '')
          .toString()
          .trim();
      final status = (item['status'] ?? '').toString().trim();

      if (!_isValidSchoolYear(schoolYear) ||
          !_allowedStatuses.contains(status) ||
          !_isValidDateKey(startDateKey) ||
          !_isValidDateKey(endExclusiveDateKey) ||
          startDateKey.compareTo(endExclusiveDateKey) >= 0) {
        continue;
      }

      final semesters = <StudentSemesterRange>[];
      final rawSemesters = item['semesterRanges'];
      if (rawSemesters is List) {
        for (final rawSem in rawSemesters) {
          if (rawSem is! Map) continue;
          final sem = rawSem.map((k, v) => MapEntry(k.toString(), v));
          final id = (sem['id'] ?? '').toString().trim();
          final label = (sem['label'] ?? '').toString().trim();
          final semStart = (sem['startDateKey'] ?? '').toString().trim();
          final semEnd = (sem['endExclusiveDateKey'] ?? '').toString().trim();
          final sourceStr = (sem['source'] ?? '').toString().trim();
          final source = switch (sourceStr) {
            'configured' => StudentSemesterRangeSource.configured,
            'reportGrouping' => StudentSemesterRangeSource.reportGrouping,
            _ => null,
          };

          if (id.isEmpty ||
              label.isEmpty ||
              source == null ||
              !_isValidDateKey(semStart) ||
              !_isValidDateKey(semEnd) ||
              semStart.compareTo(semEnd) >= 0 ||
              semStart.compareTo(startDateKey) < 0 ||
              semEnd.compareTo(endExclusiveDateKey) > 0) {
            continue;
          }
          semesters.add(
            StudentSemesterRange(
              id: id,
              label: label,
              startDateKey: semStart,
              endExclusiveDateKey: semEnd,
              source: source,
            ),
          );
        }
      }

      parsed.add(
        StudentAcademicYear(
          schoolYear: schoolYear,
          startDateKey: startDateKey,
          endExclusiveDateKey: endExclusiveDateKey,
          status: status,
          semesterRanges: List.unmodifiable(semesters),
        ),
      );
    }

    parsed.sort((a, b) => b.schoolYear.compareCompareToDesc(a.schoolYear));
    return List.unmodifiable(parsed);
  }
}

extension on String {
  int compareCompareToDesc(String other) => compareTo(other);
}
