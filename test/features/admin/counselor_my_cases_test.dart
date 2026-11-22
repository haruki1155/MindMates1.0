import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/counselor_workflow_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
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
  String? followUpMessage,
  String? followUpAppointmentId,
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
  followUpMessage: followUpMessage,
  followUpAppointmentId: followUpAppointmentId,
);

Future<void> _pumpWorkflow(
  WidgetTester tester,
  _FakeCaseloadRepository repo,
  CounselorWorkflowMode mode, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
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
      expect(find.text('Awaiting Client Response'), findsOneWidget);
      expect(
        find.text(
          'Pending follow-up offer — client has not booked a session yet.',
        ),
        findsOneWidget,
      );
      expect(find.text('Follow-up offered - waiting for client'), findsNothing);
      expect(find.text('Approved'), findsNothing);
      expect(find.text('Follow-up booked'), findsNothing);
      expect(find.text('Ben Santos'), findsNothing);
    },
  );

  testWidgets(
    'Pending follow-up offer uses amber indicator, offer note, and semantics without green styling',
    (tester) async {
      final repo = _FakeCaseloadRepository([
        _syntheticAppointment(
          id: 'appt-offer',
          userId: 'student-1',
          fullName: 'Ana Cruz',
          scheduledAt: DateTime(2026, 11, 20, 9),
          scheduledTime: '9:00 AM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'offered',
          followUpMessage: 'Please book within the week.',
        ),
      ]);

      await _pumpWorkflow(tester, repo, CounselorWorkflowMode.followUps);

      expect(find.text('Follow-up records'), findsOneWidget);
      expect(find.text('Awaiting client response'), findsOneWidget);
      expect(find.text('Privacy scope'), findsOneWidget);
      expect(find.text('Assigned only'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('Awaiting Client Response'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Awaiting Client Response')),
        findsOneWidget,
      );
      final badgeSemantics = tester.widgetList<Semantics>(
        find.descendant(
          of: find.byType(AdminStatusBadge),
          matching: find.byType(Semantics),
        ),
      );
      expect(
        badgeSemantics.any(
          (s) => s.properties.label == 'Awaiting Client Response',
        ),
        isTrue,
      );
      expect(find.byIcon(Icons.hourglass_top_outlined), findsOneWidget);
      expect(
        find.text('Offer note: Please book within the week.'),
        findsOneWidget,
      );

      final badge = tester.widget<AdminStatusBadge>(
        find.byType(AdminStatusBadge),
      );
      expect(badge.presentation.backgroundColor, AdminColors.amberBg);
      expect(badge.presentation.foregroundColor, AdminColors.amberFg);
      expect(badge.presentation.borderColor, AdminColors.amberBorder);
      expect(badge.presentation.backgroundColor, isNot(AdminColors.greenBg));
      expect(badge.presentation.foregroundColor, isNot(AdminColors.greenFg));

      // Verify amber-highlighted card border/surface and absence of green/success containers.
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasAmberCard = containers.any((container) {
        final decoration = container.decoration;
        if (decoration is! BoxDecoration) return false;
        final border = decoration.border;
        return decoration.color ==
                AdminColors.amberBg.withValues(alpha: 0.28) &&
            border is Border &&
            border.top.color == AdminColors.amberBorder;
      });
      final hasAnyGreenContainer = containers.any((container) {
        final decoration = container.decoration;
        if (decoration is! BoxDecoration) return false;
        return decoration.color == AdminColors.greenBg ||
            decoration.color == AdminColors.success;
      });
      expect(hasAmberCard, isTrue);
      expect(hasAnyGreenContainer, isFalse);

      expect(repo.watchUsersCalls, 0);
      expect(repo.watchAppointmentsCalls, 0);
    },
  );

  testWidgets(
    'Follow-ups distinguishes offered, booked, completed, declined, cancelled, and expired states and sorts pending first',
    (tester) async {
      final repo = _FakeCaseloadRepository([
        _syntheticAppointment(
          id: 'appt-expired',
          userId: 'student-expired',
          fullName: 'Evan Lim',
          scheduledAt: DateTime(2026, 11, 10, 9),
          scheduledTime: '9:00 AM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'expired',
        ),
        _syntheticAppointment(
          id: 'appt-cancelled',
          userId: 'student-cancelled',
          fullName: 'Cara Reyes',
          scheduledAt: DateTime(2026, 11, 11, 9),
          scheduledTime: '9:00 AM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'cancelled',
        ),
        _syntheticAppointment(
          id: 'appt-declined',
          userId: 'student-declined',
          fullName: 'Dan Tan',
          scheduledAt: DateTime(2026, 11, 12, 9),
          scheduledTime: '9:00 AM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'declined',
        ),
        _syntheticAppointment(
          id: 'appt-booked-completed-parent',
          userId: 'student-completed',
          fullName: 'Ben Santos',
          scheduledAt: DateTime(2026, 11, 13, 9),
          scheduledTime: '9:00 AM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'booked',
          followUpAppointmentId: 'appt-booked-completed-child',
        ),
        _syntheticAppointment(
          id: 'appt-booked-completed-child',
          userId: 'student-completed',
          fullName: 'Ben Santos',
          scheduledAt: DateTime(2026, 11, 16, 10),
          scheduledTime: '10:00 AM',
          status: 'completed',
          followUpRecommended: false,
          followUpStatus: 'none',
        ),
        _syntheticAppointment(
          id: 'appt-booked',
          userId: 'student-booked',
          fullName: 'Faye Cruz',
          scheduledAt: DateTime(2026, 11, 14, 11),
          scheduledTime: '11:00 AM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'booked',
        ),
        _syntheticAppointment(
          id: 'appt-offered',
          userId: 'student-offered',
          fullName: 'Ana Cruz',
          scheduledAt: DateTime(2026, 11, 20, 14),
          scheduledTime: '2:00 PM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'offered',
        ),
        _syntheticAppointment(
          id: 'appt-none',
          userId: 'student-none',
          fullName: 'Gino Diaz',
          scheduledAt: DateTime(2026, 11, 21, 15),
          scheduledTime: '3:00 PM',
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'none',
        ),
      ]);

      await _pumpWorkflow(tester, repo, CounselorWorkflowMode.followUps);

      expect(find.text('6'), findsOneWidget); // Follow-up records
      expect(find.text('1'), findsOneWidget); // Awaiting client response
      expect(find.text('Gino Diaz'), findsNothing);

      final badges = tester
          .widgetList<AdminStatusBadge>(find.byType(AdminStatusBadge))
          .toList();
      expect(badges.map((b) => b.presentation.label).toList(), [
        'Awaiting Client Response',
        'Booked',
        'Expired',
        'Cancelled',
        'Declined',
        'Completed',
      ]);
      expect(badges[0].presentation.backgroundColor, AdminColors.amberBg);
      expect(badges[1].presentation.backgroundColor, AdminColors.blueBg);
      expect(badges[2].presentation.backgroundColor, AdminColors.neutralBg);
      expect(badges[3].presentation.backgroundColor, AdminColors.neutralBg);
      expect(badges[4].presentation.backgroundColor, AdminColors.neutralBg);
      expect(badges[5].presentation.backgroundColor, AdminColors.greenBg);

      expect(find.text('Client booked a follow-up session.'), findsOneWidget);
      expect(find.text('Follow-up session completed.'), findsOneWidget);
      expect(find.text('Follow-up session was declined.'), findsOneWidget);
      expect(find.text('Follow-up session was cancelled.'), findsOneWidget);
      expect(find.text('Follow-up offer or booking expired.'), findsOneWidget);
    },
  );

  for (final viewport in [
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1280, 900),
  ]) {
    testWidgets(
      'Follow-ups layout renders cleanly without overflow at ${viewport.width.toInt()}x${viewport.height.toInt()}',
      (tester) async {
        final repo = _FakeCaseloadRepository([
          _syntheticAppointment(
            id: 'appt-offered',
            userId: 'student-1',
            fullName: 'Ana Maria Dela Cruz',
            scheduledAt: DateTime(2026, 11, 20, 9),
            scheduledTime: '9:00 AM',
            status: 'completed',
            followUpRecommended: true,
            followUpStatus: 'offered',
            followUpMessage: 'Schedule next check-in before finals.',
          ),
          _syntheticAppointment(
            id: 'appt-booked',
            userId: 'student-2',
            fullName: 'Ben Santos',
            scheduledAt: DateTime(2026, 11, 18, 10),
            scheduledTime: '10:00 AM',
            status: 'completed',
            followUpRecommended: true,
            followUpStatus: 'booked',
          ),
        ]);

        await _pumpWorkflow(
          tester,
          repo,
          CounselorWorkflowMode.followUps,
          size: viewport,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Awaiting Client Response'), findsOneWidget);
        expect(find.text('Booked'), findsOneWidget);
        expect(repo.watchUsersCalls, 0);
        expect(repo.watchAppointmentsCalls, 0);
      },
    );
  }

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
        find.text('No counseling cases were found for your assigned colleges.'),
        findsOneWidget,
      );
    },
  );
}
