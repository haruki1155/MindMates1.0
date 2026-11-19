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
    return appointmentsStream.stream;
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

  test('counselor watchMyAssignedAppointments includes verified + assignedCollegeIds filters', () async {
    final fs = _FakeFirestoreService();
    final repo = _TestAdminPortalRepository(
      role: AccessRole.counselor,
      superAdmin: false,
      uid: 'counselor-1',
      firestoreService: fs,
    );

    final sub = repo.watchMyAssignedAppointments().listen((_) {});
    fs.userProfileStream.add({
      'accessRole': 'counselor',
      'staffAccountStatus': 'approved',
      'accountStatus': 'active',
      'assignedCollegeIds': ['cite', 'cas'],
    });
    await Future<void>.delayed(Duration.zero);

    expect(fs.calls.length, 1);
    expect(fs.calls.last.whereEquals, {
      'assignedStaffId': 'counselor-1',
      'studentVerificationStatus': 'verified',
    });
    expect(fs.calls.last.whereIn, {
      'collegeId': ['cas', 'cite'],
    });

    await sub.cancel();
    await fs.userProfileStream.close();
    await fs.appointmentsStream.close();
  });

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
      await fs.userProfileStream.close();
      await fs.appointmentsStream.close();
    }
  });
}
