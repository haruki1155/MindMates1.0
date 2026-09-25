import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/widgets/appointment_list_view.dart';
import 'package:mind_mates/models/appointment_model.dart';

void main() {
  testWidgets(
    'client appointment cards expose only staff-proposal acceptance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appointment = _appointment(
        status: 'reschedule_proposed',
        proposedScheduledAt: DateTime(2026, 10, 2, 10),
        proposedScheduledTime: '10:00 AM',
        rescheduleReason: 'Counselor schedule conflict',
      );

      await tester.pumpWidget(_app([appointment]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review New Schedule'));
      await tester.pumpAndSettle();

      expect(find.text('Accept New Schedule'), findsOneWidget);
      expect(find.text('Reason for reschedule'), findsOneWidget);
      expect(find.text('Counselor schedule conflict'), findsOneWidget);
      expect(find.text('Cancel Appointment'), findsNothing);
      expect(find.text('Cancel Request'), findsNothing);
      expect(find.text('Request Reschedule'), findsNothing);
      expect(find.text('Request Another Time'), findsNothing);
    },
  );

  testWidgets('follow-up displays only client-safe message and links booking', (
    tester,
  ) async {
    final appointment = _appointment(
      status: 'completed',
      followUpRecommended: true,
      followUpMessage: 'You may book a follow-up when ready.',
    );
    AppointmentModel? bookedFrom;

    await tester.pumpWidget(
      _app([appointment], onBook: (value) => bookedFrom = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(find.text('Book Follow-up'), findsOneWidget);
    expect(find.text('You may book a follow-up when ready.'), findsNothing);
    await tester.tap(find.text('Book Follow-up'));
    expect(bookedFrom?.id, appointment.id);
  });
}

Widget _app(
  List<AppointmentModel> appointments, {
  ValueChanged<AppointmentModel?>? onBook,
}) => MaterialApp(
  home: Scaffold(
    body: AppointmentListView(
      appointments: appointments,
      onBook: onBook ?? (_) {},
      onView: (_) {},
      onCalendar: (_) {},
      onAccept: (_) {},
    ),
  ),
);

AppointmentModel _appointment({
  required String status,
  DateTime? proposedScheduledAt,
  String? proposedScheduledTime,
  String? rescheduleReason,
  bool followUpRecommended = false,
  String? followUpMessage,
}) => AppointmentModel(
  id: 'appointment-1',
  userId: 'student-1',
  fullName: 'Student',
  scheduledAt: DateTime(2026, 10, 1, 9),
  scheduledTime: '9:00 AM',
  location: 'PACC',
  status: status,
  concern: 'Support',
  contactNumber: '09123456789',
  email: 'student@example.com',
  preferredContactMethod: 'Email',
  createdAt: DateTime(2026, 9, 1),
  proposedScheduledAt: proposedScheduledAt,
  proposedScheduledTime: proposedScheduledTime,
  rescheduleReason: rescheduleReason,
  followUpRecommended: followUpRecommended,
  followUpMessage: followUpMessage,
);
