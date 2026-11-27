import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/portal_badge_seen_controller.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_unread_badges.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/testing_service_schedule.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _PortalBadgeFakeRepository extends AdminPortalRepository {
  _PortalBadgeFakeRepository({
    required this.role,
    required this.superAdmin,
    required this.uid,
  });

  final AccessRole role;
  final bool superAdmin;
  final String uid;

  final _appointmentsListeners =
      <MultiStreamController<List<AppointmentModel>>>[];
  List<AppointmentModel>? _latestAppointments;

  void emitAppointments(List<AppointmentModel> items) {
    _latestAppointments = items;
    for (final listener in List.of(_appointmentsListeners)) {
      if (!listener.isClosed) {
        listener.add(items);
      }
    }
  }

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  String? get currentUserId => uid;

  @override
  User? get currentAuthUser => null;

  @override
  Stream<List<UserModel>> watchUsers() =>
      Stream<List<UserModel>>.value(const <UserModel>[]).asBroadcastStream();

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream<List<AdminAssessmentRecord>>.value(
        const <AdminAssessmentRecord>[],
      ).asBroadcastStream();

  @override
  Stream<List<AppointmentModel>> watchAppointments() =>
      Stream<List<AppointmentModel>>.multi((controller) {
        _appointmentsListeners.add(controller);
        final snapshot = _latestAppointments;
        if (snapshot != null) {
          controller.add(snapshot);
        }
        controller.onCancel = () => _appointmentsListeners.remove(controller);
      }, isBroadcast: true);

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() =>
      watchAppointments();

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() =>
      Stream<List<AdminInquiryModel>>.value(
        const <AdminInquiryModel>[],
      ).asBroadcastStream();
}

AppointmentModel _sampleAppointment({
  required String id,
  required String status,
  required DateTime scheduledAt,
  DateTime? updatedAt,
  int scheduleRevision = 0,
  int proposalRevision = 0,
}) => AppointmentModel(
  id: id,
  userId: 'student-1',
  fullName: 'Juan Dela Cruz',
  scheduledAt: scheduledAt,
  scheduledTime: '9:00 AM',
  location: 'PACC Office',
  status: status,
  concern: 'Counseling check-in',
  contactNumber: '09171234567',
  email: 'student@ucu.edu.ph',
  preferredContactMethod: 'email',
  createdAt: DateTime(2026, 11, 20, 8),
  updatedAt: updatedAt,
  scheduleRevision: scheduleRevision,
  proposalRevision: proposalRevision,
);

void main() {
  group('PortalBadgeSeenController unit tests', () {
    test('clears unseen appointments after viewing, persists across reloads, and re-surfaces on updates', () {
      final memoryStore = <String, String>{};
      final now = DateTime.utc(2026, 11, 27, 4);
      final appt = _sampleAppointment(
        id: 'appt-1',
        status: 'requested',
        scheduledAt: now.add(const Duration(days: 2)),
        updatedAt: DateTime.utc(2026, 11, 27, 1),
      );

      final first = PortalBadgeSeenController(
        userId: 'admin-1',
        readStorage: (k) => memoryStore[k],
        writeStorage: (k, v) => memoryStore[k] = v,
      );
      expect(first.countUnseenAppointments([appt], now), 1);

      expect(first.markAppointmentsSeen([appt]), isTrue);
      expect(first.countUnseenAppointments([appt], now), 0);

      // Persists across page reloads via storage
      final reloaded = PortalBadgeSeenController(
        userId: 'admin-1',
        readStorage: (k) => memoryStore[k],
        writeStorage: (k, v) => memoryStore[k] = v,
      );
      expect(reloaded.countUnseenAppointments([appt], now), 0);

      // Updating proposalRevision / updatedAt resurfaces badge cleanly
      final updatedAppt = _sampleAppointment(
        id: 'appt-1',
        status: 'requested',
        scheduledAt: now.add(const Duration(days: 3)),
        updatedAt: DateTime.utc(2026, 11, 27, 3),
        proposalRevision: 1,
      );
      expect(reloaded.countUnseenAppointments([updatedAppt], now), 1);
    });

    test('tracks Testing Service schedule revision changes separately per version key', () {
      final controller = PortalBadgeSeenController(
        userId: 'admin-1',
        readStorage: (_) => null,
        writeStorage: (_, _) {},
      );
      final awaiting = AdminInquiryModel.fromJson({
        'id': 'inq-ts-1',
        'userId': 'u-1',
        'subject': 'Testing Service Schedule Request',
        'message': 'Requesting schedule',
        'category': 'Service Form',
        'formType': testingServiceFormType,
        'status': 'pending',
        'routingRevision': 1,
        'createdAt': '2026-11-27T08:00:00.000Z',
        'testingSchedule': {'status': 'awaiting_schedule', 'revision': 0},
      });
      expect(
        controller.countUnseenInquiries([awaiting], testingOnly: true),
        1,
      );

      controller.markInquiriesSeen([awaiting]);
      expect(
        controller.countUnseenInquiries([awaiting], testingOnly: true),
        0,
      );

      // Student requests reschedule -> revision & status change -> resurfaces!
      final rescheduleRequested = AdminInquiryModel.fromJson({
        'id': 'inq-ts-1',
        'userId': 'u-1',
        'subject': 'Testing Service Schedule Request',
        'message': 'Requesting schedule',
        'category': 'Service Form',
        'formType': testingServiceFormType,
        'status': 'in_progress',
        'routingRevision': 3,
        'createdAt': '2026-11-27T08:00:00.000Z',
        'testingSchedule': {
          'status': 'reschedule_requested',
          'revision': 2,
        },
      });
      expect(
        controller.countUnseenInquiries(
          [rescheduleRequested],
          testingOnly: true,
        ),
        1,
      );
    });
  });

  group('AdminPortalHome appointment badge widget tests', () {
    testWidgets(
      'Admin appointment badge clears after viewing Appointments and reappears on new/updated appointment',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final repo = _PortalBadgeFakeRepository(
          role: AccessRole.admin,
          superAdmin: true,
          uid: 'admin-badge-test',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: AdminPortalHome(
              repository: repo,
              registerUnload: (_) => null,
              removeUnload: (_) {},
            ),
          ),
        );
        await tester.pump();

        final future = DateTime.now().add(const Duration(days: 2));
        final firstAppt = _sampleAppointment(
          id: 'appt-new-1',
          status: 'requested',
          scheduledAt: future,
          updatedAt: DateTime(2026, 11, 27, 10),
        );
        repo.emitAppointments([firstAppt]);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('nav-badge-appointments')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('nav-badge-appointments')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );

        // Admin navigates to Appointments to view the latest appointment.
        await tester.tap(find.text('Appointments'));
        await tester.pumpAndSettle();

        // Badge is cleared immediately (count == 0, hidden) and stays cleared on Dashboard.
        final clearedBadge = tester.widget<UnreadCountBadge>(
          find.byKey(const ValueKey('nav-badge-appointments')),
        );
        expect(clearedBadge.count, 0);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('nav-badge-appointments')),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<UnreadCountBadge>(
                find.byKey(const ValueKey('nav-badge-appointments')),
              )
              .count,
          0,
        );

        // When a newer update or new appointment arrives, the badge reappears.
        final secondAppt = _sampleAppointment(
          id: 'appt-new-2',
          status: 'requested',
          scheduledAt: future.add(const Duration(days: 1)),
          updatedAt: DateTime(2026, 11, 27, 12),
        );
        repo.emitAppointments([firstAppt, secondAppt]);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('nav-badge-appointments')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Counselor appointment badge remains visible until appointment is actually acted upon',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final repo = _PortalBadgeFakeRepository(
          role: AccessRole.counselor,
          superAdmin: false,
          uid: 'counselor-1',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: AdminPortalHome(
              repository: repo,
              registerUnload: (_) => null,
              removeUnload: (_) {},
            ),
          ),
        );
        await tester.pump();

        final appt = _sampleAppointment(
          id: 'appt-coun-1',
          status: 'requested',
          scheduledAt: DateTime.now().add(const Duration(days: 2)),
        );
        repo.emitAppointments([appt]);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('nav-badge-appointments')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Appointments'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('nav-badge-appointments')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
