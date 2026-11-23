import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FollowUpRepo extends AdminPortalRepository {
  _FollowUpRepo(this.items);
  final List<AppointmentModel> items;

  @override
  AccessRole get currentAccessRole => AccessRole.counselor;

  @override
  Stream<List<AppointmentModel>> watchAppointments() => Stream.value(items);
}

AppointmentModel _appt(
  String id, {
  required String name,
  required String status,
  String? parentAppointmentId,
}) => AppointmentModel(
  id: id,
  userId: 'u-$id',
  fullName: name,
  scheduledAt: DateTime.now().add(const Duration(days: 3)),
  scheduledTime: '10:00 AM',
  location: 'PACC Office',
  status: status,
  concern: 'General session',
  contactNumber: '09171234567',
  email: '$id@example.com',
  preferredContactMethod: 'email',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  parentAppointmentId: parentAppointmentId,
);

void main() {
  testWidgets(
    'Appointment type filter filters canonical follow-up vs initial and shows Follow-up badge beside status',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _FollowUpRepo([
        _appt('a1', name: 'Initial Student', status: 'requested'),
        _appt(
          'a2',
          name: 'Followup Student',
          status: 'requested',
          parentAppointmentId: 'parent-1',
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AdminAppointmentsPage(
              repository: repo,
              onOpenAssessments: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both appear in 'All appointments'.
      expect(find.text('Initial Student'), findsOneWidget);
      expect(find.text('Followup Student'), findsOneWidget);
      // Only canonical follow-up receives the Follow-up badge, coexisting with status.
      expect(find.text('Follow-up'), findsOneWidget);
      expect(find.byType(AdminStatusBadge), findsNWidgets(3));

      // Filter to Follow-up only.
      await tester.tap(find.text('All appointments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow-up').last);
      await tester.pumpAndSettle();

      expect(find.text('Followup Student'), findsOneWidget);
      expect(find.text('Initial Student'), findsNothing);

      // Filter to Initial only.
      await tester.tap(find.text('Follow-up').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Initial').last);
      await tester.pumpAndSettle();

      expect(find.text('Initial Student'), findsOneWidget);
      expect(find.text('Followup Student'), findsNothing);
    },
  );
}
