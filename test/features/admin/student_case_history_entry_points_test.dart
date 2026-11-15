import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/counselor_workflow_page.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/student_case_history_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

AppointmentModel _appointment(String userId) => AppointmentModel(
  id: 'a-$userId',
  userId: userId,
  fullName: 'Ana Cruz',
  scheduledAt: DateTime(2026, 1, 1, 10),
  scheduledTime: '10:00 AM',
  location: 'PACC',
  status: 'confirmed',
  concern: '',
  contactNumber: '',
  email: '',
  preferredContactMethod: '',
  createdAt: DateTime(2026, 1, 1),
);

class _Repo extends AdminPortalRepository {
  _Repo(this.role, {this.superAdmin = false});
  final AccessRole role;
  final bool superAdmin;
  final requested = <String>[];

  @override
  AccessRole get currentAccessRole => role;
  @override
  bool get isSuperAdmin => superAdmin;
  @override
  Stream<List<AppointmentModel>> watchAppointments() =>
      Stream.value([_appointment('student-uid-1')]);
  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() =>
      Stream.value([_appointment('student-uid-1')]);
  @override
  Future<StudentCaseHistoryResult> fetchStudentCaseHistory({
    required String studentId,
    String? cursor,
    int pageSize = 20,
  }) async {
    requested.add(studentId);
    return const StudentCaseHistoryResult(
      studentId: 'student-uid-1',
      displayName: 'Ana Cruz',
      collegeId: 'cite',
      items: [],
      nextCursor: null,
      truncated: false,
    );
  }
}

Future<void> _pumpMyCases(WidgetTester tester, _Repo repo) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CounselorWorkflowPage(
          repository: repo,
          mode: CounselorWorkflowMode.cases,
          onOpenAppointments: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAppointments(WidgetTester tester, _Repo repo) async {
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
  const label = 'Case history';

  testWidgets('My Cases opens the history for the card\'s student account', (
    tester,
  ) async {
    final repo = _Repo(AccessRole.counselor);
    await _pumpMyCases(tester, repo);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(repo.requested, ['student-uid-1']);
    expect(find.text('No cases recorded'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('My Cases'), findsOneWidget);
  });

  testWidgets('My Cases cards stay usable on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CounselorWorkflowPage(
            repository: _Repo(AccessRole.counselor),
            mode: CounselorWorkflowMode.cases,
            onOpenAppointments: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(label), findsOneWidget);
  });

  testWidgets('appointment cards open the history for counselors', (
    tester,
  ) async {
    final repo = _Repo(AccessRole.counselor);
    await _pumpAppointments(tester, repo);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(repo.requested, ['student-uid-1']);
  });

  testWidgets('the configured super-administrator sees the action', (
    tester,
  ) async {
    await _pumpAppointments(tester, _Repo(AccessRole.admin, superAdmin: true));
    expect(find.text(label), findsOneWidget);
  });

  testWidgets('portal staff and other administrators never see the action', (
    tester,
  ) async {
    await _pumpAppointments(tester, _Repo(AccessRole.admin));
    expect(find.text(label), findsNothing);
    await _pumpMyCases(tester, _Repo(AccessRole.portalStaff));
    expect(find.text(label), findsNothing);
  });
}
