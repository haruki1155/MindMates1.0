import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/counselor_operations_dashboard.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeCounselorDashboardRepository extends AdminPortalRepository {
  _FakeCounselorDashboardRepository({
    required this.appointments,
    required this.myAssignedAppointments,
  });

  final Stream<List<AppointmentModel>> appointments;
  final Stream<List<AppointmentModel>> myAssignedAppointments;

  @override
  Stream<List<AppointmentModel>> watchAppointments() => appointments;

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() =>
      myAssignedAppointments;
}

AppointmentModel _sampleAppointment({
  required String id,
  required DateTime scheduledAt,
  required String status,
  String userId = 'student-1001',
  String? parentAppointmentId,
  bool followUpRecommended = false,
  String followUpStatus = 'none',
}) => AppointmentModel(
  id: id,
  userId: userId,
  fullName: 'Student $id',
  scheduledAt: scheduledAt,
  scheduledTime: '9:00 AM',
  location: 'PACC Office',
  concern: 'Check-in',
  contactNumber: '09171234567',
  email: '$userId@example.com',
  preferredContactMethod: 'email',
  status: status,
  createdAt: scheduledAt.subtract(const Duration(days: 1)),
  parentAppointmentId: parentAppointmentId,
  followUpRecommended: followUpRecommended,
  followUpStatus: followUpStatus,
);

void main() {
  final fixedNow = DateTime.utc(2026, 11, 21, 6, 0);

  testWidgets('renders skeleton loading state while PACC appointments wait', (
    tester,
  ) async {
    final paccCtrl = StreamController<List<AppointmentModel>>.broadcast();
    final myCtrl = StreamController<List<AppointmentModel>>.broadcast();
    addTearDown(() async {
      await paccCtrl.close();
      await myCtrl.close();
    });

    final repo = _FakeCounselorDashboardRepository(
      appointments: paccCtrl.stream,
      myAssignedAppointments: myCtrl.stream,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: CounselorOperationsDashboardPage(
            repository: repo,
            onNavigate: (_) {},
            clock: () => fixedNow,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Counselor Dashboard'), findsNothing);
  });

  testWidgets(
    'renders interactive analytics, status breakdown toggle, and responsive widths (390/768/1280)',
    (tester) async {
      final navigated = <AdminPortalPage>[];
      final apptTodayAssigned = _sampleAppointment(
        id: 'appt-today-1',
        userId: 'student-4321',
        scheduledAt: DateTime.utc(2026, 11, 21, 1, 0),
        status: 'confirmed',
        parentAppointmentId: 'appt-parent-0',
      );
      final apptTomorrowPacc = _sampleAppointment(
        id: 'appt-tomorrow-2',
        userId: 'student-5555',
        scheduledAt: DateTime.utc(2026, 11, 22, 2, 0),
        status: 'requested',
      );
      final apptCompletedOffered = _sampleAppointment(
        id: 'appt-completed-3',
        userId: 'student-7777',
        scheduledAt: DateTime.utc(2026, 11, 19, 2, 0),
        status: 'completed',
        followUpRecommended: true,
        followUpStatus: 'offered',
      );
      final apptCancelledToday = _sampleAppointment(
        id: 'appt-cancelled-4',
        userId: 'student-9999',
        scheduledAt: DateTime.utc(2026, 11, 21, 3, 0),
        status: 'cancelled',
      );

      final repo = _FakeCounselorDashboardRepository(
        appointments: Stream.value([
          apptTodayAssigned,
          apptTomorrowPacc,
          apptCompletedOffered,
          apptCancelledToday,
        ]),
        myAssignedAppointments: Stream.value([
          apptTodayAssigned,
          apptCompletedOffered,
        ]),
      );

      for (final width in const [390.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              body: CounselorOperationsDashboardPage(
                repository: repo,
                onNavigate: navigated.add,
                clock: () => fixedNow,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Counselor Dashboard'), findsOneWidget);
        expect(find.text('PACC Today'), findsOneWidget);
        expect(find.text('My Assigned Active'), findsOneWidget);
        expect(find.text('My Caseload'), findsOneWidget);
        expect(find.text('Assigned 2'), findsOneWidget);
        expect(find.text('Follow-up offered 1'), findsOneWidget);
        expect(find.text('7-day appointment schedule'), findsOneWidget);
        expect(find.text('Appointment status breakdown'), findsOneWidget);
        expect(find.text('Student ••••4321'), findsOneWidget);
        expect(find.text('Assigned to you'), findsOneWidget);
        // Cancelled today appointment must not appear in Today's schedule.
        expect(find.text('Student ••••9999'), findsNothing);
      }

      // Tap 7-day chart day bar ("Nov 21") to inspect day breakdown.
      await tester.tap(find.text('Nov 21'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nov 21: 1 PACC session (1 assigned to you)'),
        findsOneWidget,
      );

      // Tap status breakdown item ("Cancelled / declined").
      await tester.tap(find.text('Cancelled / declined'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cancelled / declined: 1 of 4 (25%)'),
        findsOneWidget,
      );

      // Toggle to My Caseload scope in status breakdown.
      await tester.tap(find.text('My Caseload (2)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Assigned caseload records (2 total)'),
        findsOneWidget,
      );

      // Click-through navigation on KPI card.
      await tester.tap(find.text('My Assigned Active'));
      await tester.pump();
      expect(navigated, contains(AdminPortalPage.cases));

      tester.view.reset();
    },
  );
}
