import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';

class _Repository extends AdminPortalRepository {
  _Repository(this.records);

  final List<AppointmentModel> records;
  String? agreementAction;
  int? agreementRevision;
  @override
  Future<void> changeAppointmentAgreement(AppointmentModel appointment, String action, String requestId) async { agreementAction = action; agreementRevision = appointment.proposalRevision; }

  @override
  Stream<List<AppointmentModel>> watchAppointments() => Stream.value(records);

  @override
  Future<List<AppointmentSlot>> getAvailableAppointmentSlots(
    DateTime date,
  ) async => [
    AppointmentSlot(
      start: DateTime(date.year, date.month, date.day, 13),
      label: '1:00 PM',
    ),
  ];
}

void main() {
  testWidgets('follow-up offer requires a suggested date and time', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = _appointment('confirmed', DateTime.now().subtract(const Duration(hours: 2)), 'Follow-up student');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAppointmentsPage(repository: _Repository([record]), onOpenAssessments: null))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All active 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Session summary (internal)'), 'Session summary');
    final offer = find.text('Offer a follow-up session');
    await tester.ensureVisible(offer);
    await tester.tap(offer);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Client message'), 'Please return for a follow-up.');
    expect(find.text('Suggested date'), findsOneWidget);
    expect(find.text('Suggested time'), findsOneWidget);
    await tester.tap(find.text('Send decision'));
    await tester.pump();
    expect(find.text('Choose a suggested follow-up date and time.'), findsOneWidget);
  });
  testWidgets('PACC reopens its requested-time proposal with a valid counter action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = _appointment('requested', DateTime.now().add(const Duration(days: 8)), 'Pending PACC proposal').copyWith(hasScheduleRevision: true, proposalRevision: 1, proposalStatus: 'pending', proposedBy: 'counselor', proposedScheduledAt: DateTime.now().add(const Duration(days: 9)), proposedScheduledTime: '1:00 PM');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAppointmentsPage(repository: _Repository([record]), onOpenAssessments: null))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Re-schedule appointment'), findsOneWidget);
    expect(find.text('Confirm appointment'), findsNothing);
  });

  testWidgets('PACC accepts a student proposal without moving the current time first', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = _appointment('confirmed', DateTime.now().add(const Duration(days: 8)), 'Agreement student').copyWith(hasScheduleRevision: true, scheduleRevision: 2, proposalRevision: 3, proposalStatus: 'pending', proposedBy: 'student', proposedScheduledAt: DateTime.now().add(const Duration(days: 9)), proposedScheduledTime: '1:00 PM');
    final repo = _Repository([record]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAppointmentsPage(repository: repo, onOpenAssessments: null))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Current reserved time'), findsOneWidget);
    expect(find.text('Accept student proposed time'), findsOneWidget);
    await tester.tap(find.text('Send decision'));
    await tester.pumpAndSettle();
    expect(repo.agreementAction, 'accept');
    expect(repo.agreementRevision, 3);
  });

  testWidgets('Admin Appointment categories retain finished archived records', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final future = DateTime.now().add(const Duration(days: 8));
    final records = [
      _appointment('requested', DateTime.now(), 'Request'),
      _appointment('confirmed', future, 'Future one'),
      _appointment('confirmed', future, 'Future two'),
      _appointment('completed', DateTime.now(), 'Finished one'),
      _appointment('no_show', DateTime.now(), 'Finished two'),
      for (var index = 0; index < 89; index++)
        _appointment(
          'completed',
          DateTime.now(),
          'Archived $index',
          archived: true,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminAppointmentsPage(
            repository: _Repository(records),
            onOpenAssessments: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appointment category'), findsOneWidget);
    expect(find.text('All active 5'), findsOneWidget);
    expect(find.text('Needs action 2'), findsOneWidget);
    expect(find.text('Today 0'), findsOneWidget);
    expect(find.text('Upcoming 2'), findsOneWidget);
    expect(find.text('Completed 90'), findsOneWidget);
    expect(find.text('Finished, including archived'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(
      find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.textContaining('Closed'),
      ),
      findsNothing,
    );
    expect(find.text('Archived 0'), findsNothing);

    await tester.ensureVisible(find.text('Completed 90'));
    await tester.tap(find.text('Completed 90'));
    await tester.pumpAndSettle();
    expect(find.text('Archived 0'), findsWidgets);
    expect(find.text('Finished one'), findsWidgets);
    expect(find.byTooltip('Move to history'), findsWidgets);
    expect(find.textContaining('Select finished'), findsOneWidget);
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Move to history (1)'), findsOneWidget);

    await tester.ensureVisible(find.text('History'));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Archived 0'), findsWidgets);
    expect(find.text('Finished one'), findsNothing);
    expect(find.text('Appointment category'), findsNothing);
    expect(find.byTooltip('Restore from history'), findsNothing);
    expect(find.textContaining('Restore selected'), findsNothing);
    expect(find.byIcon(Icons.unarchive_outlined), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('Select finished'), findsNothing);
    expect(find.text('View'), findsWidgets);
    expect(find.text('Review'), findsNothing);
    expect(find.byTooltip('Move to history'), findsNothing);
  });

  testWidgets(
    'reschedule proposals offer available slots instead of manual time entry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final record = _appointment(
        'requested',
        DateTime.now(),
        'Needs reschedule',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminAppointmentsPage(
              repository: _Repository([record]),
              onOpenAssessments: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm appointment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re-schedule appointment').last);
      await tester.pumpAndSettle();

      expect(find.text('Available times'), findsOneWidget);
      expect(find.text('e.g. 2:00 PM'), findsNothing);
    },
  );
}

AppointmentModel _appointment(
  String status,
  DateTime scheduledAt,
  String name, {
  bool archived = false,
}) => AppointmentModel(
  id: name,
  userId: name,
  fullName: name,
  scheduledAt: scheduledAt,
  scheduledTime: '10:00 AM',
  location: 'PACC',
  status: status,
  concern: '',
  contactNumber: '',
  email: '',
  preferredContactMethod: '',
  createdAt: scheduledAt,
  archivedAt: archived ? scheduledAt : null,
);
