import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';

class _QueryCall {
  _QueryCall({
    required this.collection,
    required this.whereEquals,
    required this.whereArrayContains,
    required this.whereIn,
  });

  final String collection;
  final Map<String, Object?> whereEquals;
  final Map<String, Object?> whereArrayContains;
  final Map<String, List<Object?>> whereIn;
}

class _FakeFirestoreService extends FirestoreService {
  final List<_QueryCall> calls = <_QueryCall>[];
  final StreamController<Map<String, dynamic>?> userProfileStream =
      StreamController<Map<String, dynamic>?>.broadcast();
  final StreamController<List<Map<String, dynamic>>> appointmentsStream =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final List<StreamController<List<Map<String, dynamic>>>> queryControllers =
      <StreamController<List<Map<String, dynamic>>>>[];
  bool usePerQueryStreams = false;

  @override
  Stream<Map<String, dynamic>?> watchDocument(
    String collection,
    String documentId,
  ) {
    if (collection == 'users') {
      return userProfileStream.stream;
    }
    return const Stream.empty();
  }

  @override
  Stream<List<Map<String, dynamic>>> watchDocuments(
    String collection, {
    Map<String, Object?> whereEquals = const {},
    Map<String, Object?> whereArrayContains = const {},
    Map<String, List<Object?>> whereIn = const {},
    String? orderBy,
    bool descending = true,
    int? limit,
  }) {
    calls.add(
      _QueryCall(
        collection: collection,
        whereEquals: Map<String, Object?>.from(whereEquals),
        whereArrayContains: Map<String, Object?>.from(whereArrayContains),
        whereIn: whereIn.map((k, v) => MapEntry(k, List<Object?>.from(v))),
      ),
    );
    if (usePerQueryStreams) {
      final controller =
          StreamController<List<Map<String, dynamic>>>.broadcast();
      queryControllers.add(controller);
      return controller.stream;
    }
    return appointmentsStream.stream;
  }

  Future<void> dispose() async {
    await userProfileStream.close();
    await appointmentsStream.close();
    for (final c in queryControllers) {
      await c.close();
    }
  }
}

class _TestAdminPortalRepository extends AdminPortalRepository {
  _TestAdminPortalRepository({
    required this.role,
    required this.superAdmin,
    required this.uid,
    required super.firestoreService,
  });

  final AccessRole role;
  final bool superAdmin;
  final String? uid;

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  String? get currentUserId => uid;
}

void main() {
  test('counselor watchAppointments queries verified students in assignedCollegeIds only and updates on revocation', () async {
    final fs = _FakeFirestoreService();
    final repo = _TestAdminPortalRepository(
      role: AccessRole.counselor,
      superAdmin: false,
      uid: 'counselor-1',
      firestoreService: fs,
    );

    final emissions = <List<AppointmentModel>>[];
    final sub = repo.watchAppointments().listen(emissions.add);

    // 1. Counselor has ['cite'] assigned -> structured query must include verification + collegeId whereIn.
    fs.userProfileStream.add({
      'accessRole': 'counselor',
      'staffAccountStatus': 'approved',
      'accountStatus': 'active',
      'assignedCollegeIds': ['cite'],
    });
    await Future<void>.delayed(Duration.zero);

    expect(fs.calls.length, 1);
    expect(fs.calls.last.collection, 'appointments');
    expect(fs.calls.last.whereEquals, {'studentVerificationStatus': 'verified'});
    expect(fs.calls.last.whereIn, {'collegeId': ['cite']});

    fs.appointmentsStream.add([
      {
        'id': 'appt-1',
        'userId': 'student-1',
        'fullName': 'Ana Cruz',
        'collegeId': 'cite',
        'studentVerificationStatus': 'verified',
        'scheduledAt': DateTime.utc(2026, 11, 20, 9),
        'scheduledTime': '9:00 AM',
        'location': 'PACC',
        'status': 'requested',
        'concern': 'Stress',
        'contactNumber': '',
        'email': '',
        'preferredContactMethod': 'email',
        'createdAt': DateTime.utc(2026, 11, 18, 9),
      },
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last.map((a) => a.id).toList(), ['appt-1']);

    // 2. Counselor loses college assignment -> must emit [] immediately without querying.
    final callCountBeforeRevoke = fs.calls.length;
    fs.userProfileStream.add({
      'accessRole': 'counselor',
      'staffAccountStatus': 'approved',
      'accountStatus': 'active',
      'assignedCollegeIds': <String>[],
    });
    await Future<void>.delayed(Duration.zero);
    expect(fs.calls.length, callCountBeforeRevoke);
    expect(emissions.last, isEmpty);

    await sub.cancel();
    await fs.userProfileStream.close();
    await fs.appointmentsStream.close();
  });

  test(
    'counselor watchMyAssignedAppointments queries verified + assignedCollegeIds without assignedStaffId',
    () async {
      final fs = _FakeFirestoreService();
      final repo = _TestAdminPortalRepository(
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'counselor-1',
        firestoreService: fs,
      );

      final emissions = <List<AppointmentModel>>[];
      final sub = repo.watchMyAssignedAppointments().listen(emissions.add);
      fs.userProfileStream.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': ['cite', 'cas'],
      });
      await Future<void>.delayed(Duration.zero);

      expect(fs.calls.length, 1);
      expect(fs.calls.last.collection, 'appointments');
      expect(fs.calls.last.whereEquals, {
        'studentVerificationStatus': 'verified',
      });
      expect(fs.calls.last.whereIn, {
        'collegeId': ['cas', 'cite'],
      });

      // Synthetic appointment without assignedStaffId must appear in My Cases.
      fs.appointmentsStream.add([
        {
          'id': 'appt-no-staff-id',
          'userId': 'student-1',
          'fullName': 'Ana Cruz',
          'collegeId': 'cite',
          'studentVerificationStatus': 'verified',
          'scheduledAt': DateTime.utc(2026, 11, 20, 9),
          'scheduledTime': '9:00 AM',
          'location': 'PACC',
          'status': 'confirmed',
          'concern': 'Stress',
          'contactNumber': '',
          'email': '',
          'preferredContactMethod': 'email',
          'createdAt': DateTime.utc(2026, 11, 18, 9),
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last.map((a) => a.id).toList(), ['appt-no-staff-id']);

      await sub.cancel();
      await fs.userProfileStream.close();
      await fs.appointmentsStream.close();
    },
  );

  test('suspended counselor profile emits empty list immediately without querying appointments', () async {
    final fs = _FakeFirestoreService();
    final repo = _TestAdminPortalRepository(
      role: AccessRole.counselor,
      superAdmin: false,
      uid: 'counselor-suspended',
      firestoreService: fs,
    );

    final emissions = <List<AppointmentModel>>[];
    final sub = repo.watchAppointments().listen(emissions.add);
    fs.userProfileStream.add({
      'accessRole': 'counselor',
      'staffAccountStatus': 'disabled',
      'accountStatus': 'suspended',
      'assignedCollegeIds': ['cite'],
    });
    await Future<void>.delayed(Duration.zero);

    expect(fs.calls, isEmpty);
    expect(emissions, hasLength(1));
    expect(emissions.single, isEmpty);

    await sub.cancel();
    await fs.userProfileStream.close();
    await fs.appointmentsStream.close();
  });

  test('portalStaff and non-super admin are refused by watchAppointments without querying appointments', () async {
    for (final role in [AccessRole.portalStaff, AccessRole.admin]) {
      final fs = _FakeFirestoreService();
      final repo = _TestAdminPortalRepository(
        role: role,
        superAdmin: false,
        uid: 'actor-1',
        firestoreService: fs,
      );
      await expectLater(repo.watchAppointments(), emitsError(isStateError));
      expect(fs.calls, isEmpty);
      await fs.dispose();
    }
  });

  test(
    'watchMyAssignedAppointments fails closed for non-counselors, super-admin, and signed-out callers',
    () async {
      for (final scenario in [
        (AccessRole.portalStaff, false, 'staff-1'),
        (AccessRole.admin, false, 'admin-1'),
        (AccessRole.admin, true, 'super-admin-1'),
        (AccessRole.appUser, false, 'student-1'),
        (AccessRole.counselor, false, null),
        (AccessRole.counselor, false, '   '),
      ]) {
        final fs = _FakeFirestoreService();
        final repo = _TestAdminPortalRepository(
          role: scenario.$1,
          superAdmin: scenario.$2,
          uid: scenario.$3,
          firestoreService: fs,
        );
        final result = await repo.watchMyAssignedAppointments().first;
        expect(result, isEmpty);
        expect(fs.calls, isEmpty);
        await fs.dispose();
      }
    },
  );

  test(
    'live scope change clears prior cases immediately on college switch, empty revocation, and suspension',
    () async {
      final fs = _FakeFirestoreService()..usePerQueryStreams = true;
      final repo = _TestAdminPortalRepository(
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'counselor-1',
        firestoreService: fs,
      );

      final emissions = <List<AppointmentModel>>[];
      final sub = repo.watchMyAssignedAppointments().listen(emissions.add);

      // 1. Start with ['cite'] and emit a matching synthetic appointment.
      fs.userProfileStream.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': ['cite'],
      });
      await Future<void>.delayed(Duration.zero);
      expect(fs.calls, hasLength(1));
      expect(fs.queryControllers, hasLength(1));
      expect(fs.queryControllers[0].hasListener, isTrue);

      fs.queryControllers[0].add([
        {
          'id': 'appt-cite',
          'userId': 'student-cite',
          'fullName': 'Cite Student',
          'collegeId': 'cite',
          'studentVerificationStatus': 'verified',
          'scheduledAt': DateTime.utc(2026, 11, 20, 9),
          'scheduledTime': '9:00 AM',
          'location': 'PACC',
          'status': 'confirmed',
          'concern': 'Stress',
          'contactNumber': '',
          'email': '',
          'preferredContactMethod': 'email',
          'createdAt': DateTime.utc(2026, 11, 18, 9),
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last.map((a) => a.id).toList(), ['appt-cite']);

      // 2. Switch to ['cas'] while new query has not emitted -> old 'cite' case cleared immediately.
      fs.userProfileStream.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': ['cas'],
      });
      await Future<void>.delayed(Duration.zero);
      expect(fs.calls, hasLength(2));
      expect(fs.calls.last.whereEquals, {'studentVerificationStatus': 'verified'});
      expect(fs.calls.last.whereIn, {'collegeId': ['cas']});
      expect(fs.queryControllers[0].hasListener, isFalse);
      expect(fs.queryControllers[1].hasListener, isTrue);
      expect(emissions.last, isEmpty);

      // Emit a 'cas' appointment, then revoke all assignments ([]).
      fs.queryControllers[1].add([
        {
          'id': 'appt-cas',
          'userId': 'student-cas',
          'fullName': 'Cas Student',
          'collegeId': 'cas',
          'studentVerificationStatus': 'verified',
          'scheduledAt': DateTime.utc(2026, 11, 21, 10),
          'scheduledTime': '10:00 AM',
          'location': 'PACC',
          'status': 'confirmed',
          'concern': 'Stress',
          'contactNumber': '',
          'email': '',
          'preferredContactMethod': 'email',
          'createdAt': DateTime.utc(2026, 11, 19, 9),
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last.map((a) => a.id).toList(), ['appt-cas']);

      // 3. Revoke to [] -> emits [] immediately with no global query.
      final callsBeforeEmpty = fs.calls.length;
      fs.userProfileStream.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': <String>[],
      });
      await Future<void>.delayed(Duration.zero);
      expect(fs.calls.length, callsBeforeEmpty);
      expect(fs.queryControllers[1].hasListener, isFalse);
      expect(emissions.last, isEmpty);

      // 4. Re-assign ['cite'], emit, then suspend -> clears result and cancels listener.
      fs.userProfileStream.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': ['cite'],
      });
      await Future<void>.delayed(Duration.zero);
      fs.queryControllers[2].add([
        {
          'id': 'appt-cite-2',
          'userId': 'student-cite',
          'fullName': 'Cite Student',
          'collegeId': 'cite',
          'studentVerificationStatus': 'verified',
          'scheduledAt': DateTime.utc(2026, 11, 22, 9),
          'scheduledTime': '9:00 AM',
          'location': 'PACC',
          'status': 'confirmed',
          'concern': 'Stress',
          'contactNumber': '',
          'email': '',
          'preferredContactMethod': 'email',
          'createdAt': DateTime.utc(2026, 11, 20, 9),
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last.map((a) => a.id).toList(), ['appt-cite-2']);

      final callsBeforeSuspend = fs.calls.length;
      fs.userProfileStream.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'disabled',
        'accountStatus': 'suspended',
        'assignedCollegeIds': ['cite'],
      });
      await Future<void>.delayed(Duration.zero);
      expect(fs.calls.length, callsBeforeSuspend);
      expect(fs.queryControllers[2].hasListener, isFalse);
      expect(emissions.last, isEmpty);

      await sub.cancel();
      await fs.dispose();
    },
  );

  test(
    'watchMyAssignedAppointments surfaces query failures instead of emitting empty',
    () async {
      final fs = _FakeFirestoreService()..usePerQueryStreams = true;
      final repo = _TestAdminPortalRepository(
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'counselor-1',
        firestoreService: fs,
      );

      final emissions = <List<AppointmentModel>>[];
      final errors = <Object>[];
      final sub = repo.watchMyAssignedAppointments().listen(
        emissions.add,
        onError: errors.add,
      );

      fs.userProfileStream.add({
        'accessRole': 'counselor',
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
        'assignedCollegeIds': ['cite'],
      });
      await Future<void>.delayed(Duration.zero);

      fs.queryControllers[0].addError(StateError('permission-denied'));
      await Future<void>.delayed(Duration.zero);

      expect(emissions, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single, isStateError);

      await sub.cancel();
      await fs.dispose();
    },
  );
}
