import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/counselor_workflow_page.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeCaseloadRepository extends AdminPortalRepository {
  _FakeCaseloadRepository(this.appointments);

  final List<AppointmentModel> appointments;
  int watchUsersCalls = 0;
  int watchAppointmentsCalls = 0;

  @override
  AccessRole get currentAccessRole => AccessRole.counselor;

  @override
  bool get isSuperAdmin => false;

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() =>
      Stream.value(appointments);

  @override
  Stream<List<AppointmentModel>> watchAppointments() {
    watchAppointmentsCalls += 1;
    return const Stream.empty();
  }

  @override
  Stream<List<UserModel>> watchUsers() {
    watchUsersCalls += 1;
    return const Stream.empty();
  }
}

AppointmentModel _syntheticAppointment({
  required String id,
  required String userId,
  required String fullName,
  required DateTime scheduledAt,
  required String scheduledTime,
  String status = 'completed',
  bool followUpRecommended = false,
  String followUpStatus = 'none',
}) => AppointmentModel(
  id: id,
  userId: userId,
  fullName: fullName,
  scheduledAt: scheduledAt,
  scheduledTime: scheduledTime,
  location: 'PACC',
  status: status,
  concern: 'Academic stress',
  contactNumber: '',
  email: '',
  preferredContactMethod: 'email',
  createdAt: scheduledAt.subtract(const Duration(days: 1)),
  followUpRecommended: followUpRecommended,
  followUpStatus: followUpStatus,
);

Future<void> _pumpWorkflow(
  WidgetTester tester,
  _FakeCaseloadRepository repo,
  CounselorWorkflowMode mode,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CounselorWorkflowPage(
          repository: repo,
          mode: mode,
          onOpenAppointments: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'My Cases shows one newest case card per student when appointments arrive out of order',
    (tester) async {
      final repo = _FakeCaseloadRepository([
        // Older appointment for student-1 arrives first.
        _syntheticAppointment(
          id: 'appt-s1-old',
          userId: 'student-1',
          fullName: 'Ana Cruz',
          scheduledAt: DateTime(2026, 10, 5, 9),
          scheduledTime: '9:00 AM',
          status: 'completed',
        ),
        // Newer appointment for student-1 arrives second.
        _syntheticAppointment(
          id: 'appt-s1-new',
          userId: 'student-1',
          fullName: 'Ana Cruz',
          scheduledAt: DateTime(2026, 11, 20, 14),
          scheduledTime: '2:00 PM',
          status: 'confirmed',
        ),
        _syntheticAppointment(
          id: 'appt-s2',
          userId: 'student-2',
          fullName: 'Ben Santos',
          scheduledAt: DateTime(2026, 11, 18, 10),
          scheduledTime: '10:00 AM',
          status: 'completed',
        ),
      ]);

      await _pumpWorkflow(tester, repo, CounselorWorkflowMode.cases);

      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Ben Santos'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('2026-11-20'), findsOneWidget);
      expect(find.textContaining('2026-10-05'), findsNothing);
      expect(repo.watchUsersCalls, 0);
      expect(repo.watchAppointmentsCalls, 0);
    },
  );

  testWidgets(
    'Follow-ups shows recommended offered follow-ups and excludes non-follow-up appointments',
    (tester) async {
      final repo = _FakeCaseloadRepository([
        _syntheticAppointment(
          id: 'appt-followup',
          userId: 'student-1',
          fullName: 'Ana Cruz',
          scheduledAt: DateTime(2026, 11, 20, 9),
          scheduledTime: '9:00 AM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'offered',
        ),
        _syntheticAppointment(
          id: 'appt-regular',
          userId: 'student-2',
          fullName: 'Ben Santos',
          scheduledAt: DateTime(2026, 11, 19, 10),
          scheduledTime: '10:00 AM',
          status: 'confirmed',
          followUpRecommended: false,
          followUpStatus: 'none',
        ),
      ]);

      await _pumpWorkflow(tester, repo, CounselorWorkflowMode.followUps);

      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Follow-up offered - waiting for client'), findsOneWidget);
      expect(find.text('Ben Santos'), findsNothing);
    },
  );

  testWidgets(
    'Empty My Cases uses truthful college-scoped wording without calling records active',
    (tester) async {
      final repo = _FakeCaseloadRepository(const []);

      await _pumpWorkflow(tester, repo, CounselorWorkflowMode.cases);

      expect(find.text('No active cases'), findsNothing);
      expect(
        find.text('No counseling cases are currently assigned to you.'),
        findsNothing,
      );
      expect(find.text('No cases in your assigned colleges'), findsOneWidget);
      expect(
        find.text(
          'No counseling cases were found for your assigned colleges.',
        ),
        findsOneWidget,
      );
    },
  );
}
