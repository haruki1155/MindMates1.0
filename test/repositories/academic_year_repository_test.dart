import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

Map<Object?, Object?> _m(Map<Object?, Object?> v) => v;

class _RoleAwareTestRepository extends AdminPortalRepository {
  _RoleAwareTestRepository({required this.role, super.callableInvoker});

  final AccessRole role;

  @override
  AccessRole get currentAccessRole => role;
}

void main() {
  test(
    'AcademicYearRecord.periodState classifies closed, current and upcoming',
    () {
      const closed = AcademicYearRecord(
        schoolYear: '2025-2026',
        startDate: '2025-06-01',
        endDate: '2026-05-31',
        status: 'closed',
      );
      const current = AcademicYearRecord(
        schoolYear: '2026-2027',
        startDate: '2026-06-01',
        endDate: '2027-05-31',
        status: 'current',
      );
      const upcoming = AcademicYearRecord(
        schoolYear: '2027-2028',
        startDate: '2027-06-01',
        endDate: '2028-05-31',
        status: 'current',
      );

      final now = DateTime.utc(2026, 11, 16);
      expect(closed.periodState(now: now), AcademicYearPeriodState.closed);
      expect(current.periodState(now: now), AcademicYearPeriodState.current);
      expect(upcoming.periodState(now: now), AcademicYearPeriodState.upcoming);
    },
  );

  test(
    'fetchAcademicYears, createAcademicYear and closeAcademicYear call existing callables for admins',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repo = _RoleAwareTestRepository(
        role: AccessRole.admin,
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return _m({
            'years': <Object?>[
              _m({
                'schoolYear': '2026-2027',
                'startDate': '2026-06-01',
                'endDate': '2027-05-31',
                'status': 'current',
              }),
            ],
          });
        },
      );

      final fetched = await repo.fetchAcademicYears();
      expect(fetched.single.schoolYear, '2026-2027');

      await repo.createAcademicYear(
        schoolYear: '2027-2028',
        startDate: '2027-06-01',
        endDate: '2028-05-31',
        copyFrom: '2026-2027',
        copyPopulation: true,
      );

      await repo.closeAcademicYear('2026-2027');

      expect(calls[0].$1, 'getAcademicYears');
      expect(calls[0].$2, isEmpty);
      expect(calls[1].$1, 'createAcademicYear');
      expect(calls[1].$2, {
        'schoolYear': '2027-2028',
        'startDate': '2027-06-01',
        'endDate': '2028-05-31',
        'copyFrom': '2026-2027',
        'copyPopulation': true,
      });
      expect(calls[2].$1, 'closeAcademicYear');
      expect(calls[2].$2, {'schoolYear': '2026-2027'});
    },
  );

  test(
    'non-admins fail fast before invoking academic year callables',
    () async {
      final calls = <String>[];
      final counselorRepo = _RoleAwareTestRepository(
        role: AccessRole.counselor,
        callableInvoker: (name, _) async {
          calls.add(name);
          return _m(const {});
        },
      );

      await expectLater(counselorRepo.fetchAcademicYears(), throwsStateError);
      await expectLater(
        counselorRepo.createAcademicYear(schoolYear: '2027-2028'),
        throwsStateError,
      );
      await expectLater(
        counselorRepo.closeAcademicYear('2026-2027'),
        throwsStateError,
      );
      await expectLater(
        counselorRepo.fetchCounselingPopulation('2026-2027'),
        throwsStateError,
      );
      await expectLater(
        counselorRepo.saveCounselingPopulation(
          schoolYear: '2026-2027',
          populations: const {},
        ),
        throwsStateError,
      );
      expect(calls, isEmpty);
    },
  );
}
