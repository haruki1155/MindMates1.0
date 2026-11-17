import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/report_generation_models.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

Map<Object?, Object?> _m(Map<Object?, Object?> v) => v;

class _RoleAwareTestRepository extends AdminPortalRepository {
  _RoleAwareTestRepository({
    required this.role,
    this.superAdmin = false,
    super.callableInvoker,
  });

  final AccessRole role;
  final bool superAdmin;

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;
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

      await repo.closeAcademicYear(
        '2026-2027',
        expectedRevision: 0,
        confirmation: 'CLOSE 2026-2027',
      );

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
      expect(calls[2].$2, {
        'schoolYear': '2026-2027',
        'expectedRevision': 0,
        'confirmation': 'CLOSE 2026-2027',
      });
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

  test(
    'manilaTodayDateKey and AcademicYearRecord fail closed on unknown and distinguish planned/voided',
    () {
      expect(manilaTodayDateKey(DateTime.utc(2026, 5, 31, 15, 59)), '2026-05-31');
      expect(manilaTodayDateKey(DateTime.utc(2026, 5, 31, 16, 0)), '2026-06-01');
      expect(manilaCurrentSchoolStartYear(DateTime.utc(2026, 5, 31, 15, 59)), 2025);
      expect(manilaCurrentSchoolStartYear(DateTime.utc(2026, 5, 31, 16, 0)), 2026);

      final planned = AcademicYearRecord.fromJson(const {
        'schoolYear': '2027-2028',
        'startDate': '2027-06-01',
        'endDate': '2028-05-31',
        'status': 'planned',
        'revision': 2,
      });
      final voided = AcademicYearRecord.fromJson(const {
        'schoolYear': '2028-2029',
        'startDate': '2028-06-01',
        'endDate': '2029-05-31',
        'status': 'voided',
        'revision': 3,
        'voidReason': 'Created prematurely',
      });
      final unknown = AcademicYearRecord.fromJson(const {
        'schoolYear': '2029-2030',
        'startDate': '2029-06-01',
        'endDate': '2030-05-31',
        'status': 'corrupted_value',
      });
      final missing = AcademicYearRecord.fromJson(const {
        'schoolYear': '2030-2031',
        'startDate': '2030-06-01',
        'endDate': '2031-05-31',
      });

      expect(planned.periodState(), AcademicYearPeriodState.planned);
      expect(planned.revision, 2);
      expect(voided.periodState(), AcademicYearPeriodState.voided);
      expect(voided.voidReason, 'Created prematurely');
      expect(unknown.status, 'unknown');
      expect(unknown.periodState(), AcademicYearPeriodState.unknown);
      expect(missing.status, 'unknown');
    },
  );

  test(
    'fetchAcademicYears(includeVoided), activateAcademicYear and super-admin voidAcademicYear call callables',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      Future<Object?> invoker(String name, Map<String, Object?> data) async {
        calls.add((name, data));
        return _m({
          'years': <Object?>[
            _m({
              'schoolYear': '2027-2028',
              'startDate': '2027-06-01',
              'endDate': '2028-05-31',
              'status': 'current',
              'revision': 3,
            }),
          ],
        });
      }

      final adminRepo = _RoleAwareTestRepository(
        role: AccessRole.admin,
        superAdmin: false,
        callableInvoker: invoker,
      );
      await adminRepo.fetchAcademicYears(includeVoided: true);
      await adminRepo.activateAcademicYear('2027-2028', expectedRevision: 2);
      await expectLater(
        adminRepo.voidAcademicYear(
          schoolYear: '2028-2029',
          reason: 'Accidental future year',
          confirmationText: 'VOID 2028-2029',
          expectedRevision: 1,
        ),
        throwsStateError,
      );

      final superRepo = _RoleAwareTestRepository(
        role: AccessRole.admin,
        superAdmin: true,
        callableInvoker: invoker,
      );
      await superRepo.voidAcademicYear(
        schoolYear: '2028-2029',
        reason: 'Accidental future year',
        confirmationText: 'VOID 2028-2029',
        expectedRevision: 1,
      );

      expect(calls[0].$1, 'getAcademicYears');
      expect(calls[0].$2, {'includeVoided': true});
      expect(calls[1].$1, 'activateAcademicYear');
      expect(calls[1].$2, {'schoolYear': '2027-2028', 'expectedRevision': 2});
      expect(calls[2].$1, 'voidAcademicYear');
      expect(calls[2].$2, {
        'schoolYear': '2028-2029',
        'reason': 'Accidental future year',
        'confirmation': 'VOID 2028-2029',
        'expectedRevision': 1,
      });
      expect(calls[2].$2.containsKey('confirmationText'), isFalse);
      expect(calls.length, 3);
    },
  );

  test(
    'absent extendedLifecycleEnabled defaults and resets to false for Batch B1 compatibility',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      var serverFlagResponse = <Object?, Object?>{};
      final repo = _RoleAwareTestRepository(
        role: AccessRole.admin,
        superAdmin: true,
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return _m({
            ...serverFlagResponse,
            'years': <Object?>[],
          });
        },
      );

      // Before any server call, extended lifecycle MUST default to false.
      expect(repo.isExtendedAcademicYearLifecycleEnabled, isFalse);

      // Legacy Batch B1 getAcademicYears response omits extendedLifecycleEnabled -> stays false.
      await repo.fetchAcademicYears(includeVoided: true);
      expect(repo.isExtendedAcademicYearLifecycleEnabled, isFalse);

      // Explicit true enables it.
      serverFlagResponse = {'extendedLifecycleEnabled': true};
      await repo.fetchAcademicYears(includeVoided: true);
      expect(repo.isExtendedAcademicYearLifecycleEnabled, isTrue);

      // Explicit false disables it.
      serverFlagResponse = {'extendedLifecycleEnabled': false};
      await repo.fetchAcademicYears(includeVoided: true);
      expect(repo.isExtendedAcademicYearLifecycleEnabled, isFalse);

      // Transition from true back to legacy absent response fails closed to false.
      serverFlagResponse = {'extendedLifecycleEnabled': true};
      await repo.fetchAcademicYears();
      expect(repo.isExtendedAcademicYearLifecycleEnabled, isTrue);
      serverFlagResponse = {};
      await repo.fetchAcademicYears();
      expect(repo.isExtendedAcademicYearLifecycleEnabled, isFalse);

      await repo.createAcademicYear(
        schoolYear: '2028-2029',
        expectedRevision: 1,
        reinstateReason: 'Confirmed 2028 enrollment dates',
      );
      expect(calls.last.$1, 'createAcademicYear');
      expect(calls.last.$2['expectedRevision'], 1);
      expect(
        calls.last.$2['reinstateReason'],
        'Confirmed 2028 enrollment dates',
      );
    },
  );
}
