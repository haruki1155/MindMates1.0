import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _Repo extends AdminPortalRepository {
  _Repo(this.role, this.userId);
  final AccessRole role;
  final String userId;
  @override
  AccessRole get currentAccessRole => role;
  @override
  Stream<List<AppointmentModel>> watchAppointments() => Stream.value([
    AppointmentModel(
      id: 'a1',
      userId: userId,
      fullName: 'Ana Student',
      scheduledAt: DateTime.now(),
      scheduledTime: '10:00 AM',
      location: 'PACC',
      status: 'requested',
      concern: '',
      contactNumber: '',
      email: '',
      preferredContactMethod: '',
      createdAt: DateTime.now(),
    ),
  ]);
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  await tester.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AdminAppointmentsPage(repository: repo, onOpenAssessments: null),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const label = 'View Student Information';

  testWidgets('shown to counselors on an appointment with a student', (
    tester,
  ) async {
    await _pump(tester, _Repo(AccessRole.counselor, 'uid-1'));
    expect(find.text(label), findsOneWidget);
  });

  testWidgets(
    'student name remains visible but Firebase UID is hidden',
    (tester) async {
      const uid = 'student-private-uid-123';
      await _pump(tester, _Repo(AccessRole.counselor, uid));
      expect(find.text('Ana Student'), findsOneWidget);
      expect(find.text(uid), findsNothing);
      expect(find.text('View Student Information'), findsOneWidget);
    },
  );

  testWidgets('hidden for portal staff', (tester) async {
    await _pump(tester, _Repo(AccessRole.portalStaff, 'uid-1'));
    expect(find.text(label), findsNothing);
  });

  testWidgets('hidden for walk-in imports without a userId', (tester) async {
    await _pump(tester, _Repo(AccessRole.counselor, ''));
    expect(find.text(label), findsNothing);
  });
}
