import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/student_academic_calendar_repository.dart';
import 'package:mind_mates/services/firebase/firebase_callable_router.dart';

void main() {
  test(
    'FirebaseCallableRouter routes getStudentAcademicCalendar to Dev alias in staging only',
    () {
      const environment = String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      );
      expect(
        FirebaseCallableRouter.name('getStudentAcademicCalendar'),
        environment == 'staging'
            ? 'getStudentAcademicCalendarDev'
            : 'getStudentAcademicCalendar',
      );
    },
  );

  test(
    'StudentAcademicCalendarRepository parses valid years, preserves reportGrouping provenance, and fails closed on malformed or voided records',
    () async {
      final repo = StudentAcademicCalendarRepository(
        caller: () async => {
          'years': [
            {
              'schoolYear': '2026-2027',
              'startDateKey': '2026-06-01',
              'endExclusiveDateKey': '2027-06-01',
              'status': 'current',
              'semesterRanges': [
                {
                  'id': 'semester_1',
                  'label': 'Semester 1 (report grouping)',
                  'startDateKey': '2026-06-01',
                  'endExclusiveDateKey': '2026-12-01',
                  'source': 'reportGrouping',
                },
                {
                  'id': 'semester_2',
                  'label': 'Semester 2 (report grouping)',
                  'startDateKey': '2026-12-01',
                  'endExclusiveDateKey': '2027-06-01',
                  'source': 'reportGrouping',
                },
              ],
            },
            {
              'schoolYear': '2025-2026',
              'startDateKey': '2025-06-01',
              'endExclusiveDateKey': '2026-06-01',
              'status': 'closed',
              'semesterRanges': [
                {
                  'id': 'term_1',
                  'label': '1st Semester',
                  'startDateKey': '2025-06-01',
                  'endExclusiveDateKey': '2025-11-15',
                  'source': 'configured',
                },
              ],
            },
            // Voided year must be omitted even if returned.
            {
              'schoolYear': '2027-2028',
              'startDateKey': '2027-06-01',
              'endExclusiveDateKey': '2028-06-01',
              'status': 'voided',
              'semesterRanges': const [],
            },
            // Malformed dates must fail closed and be omitted.
            {
              'schoolYear': '2024-2025',
              'startDateKey': '2025-06-01',
              'endExclusiveDateKey': '2024-06-01',
              'status': 'closed',
            },
            {
              'schoolYear': 'invalid',
              'startDateKey': '2023-06-01',
              'endExclusiveDateKey': '2024-06-01',
              'status': 'closed',
            },
          ],
        },
      );

      final years = await repo.fetchAcademicYears();
      expect(years, hasLength(2));
      expect(years.first.schoolYear, '2026-2027');
      expect(years.first.isCurrent, isTrue);
      expect(years.first.semesterRanges, hasLength(2));
      expect(
        years.first.semesterRanges.first.source,
        StudentSemesterRangeSource.reportGrouping,
      );
      expect(
        years.first.semesterRanges.first.isApproximateReportGrouping,
        isTrue,
      );
      expect(
        years[1].semesterRanges.single.source,
        StudentSemesterRangeSource.configured,
      );
      expect(
        years[1].semesterRanges.single.isApproximateReportGrouping,
        isFalse,
      );
    },
  );
}
