import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _Repository extends AdminPortalRepository {
  _Repository(this.records);

  final List<AppointmentModel> records;

  @override
  Stream<List<AppointmentModel>> watchAppointments() => Stream.value(records);
}

void main() {
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
    expect(find.text('Needs action 1'), findsOneWidget);
    expect(find.text('Today 0'), findsOneWidget);
    expect(find.text('Upcoming 2'), findsOneWidget);
    expect(find.text('Completed 91'), findsOneWidget);
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

    await tester.ensureVisible(find.text('Completed 91'));
    await tester.tap(find.text('Completed 91'));
    await tester.pumpAndSettle();
    expect(find.text('Archived 0'), findsWidgets);
    expect(find.text('Finished one'), findsWidgets);
    expect(find.byTooltip('Move to history'), findsWidgets);
    expect(find.textContaining('Select finished'), findsOneWidget);
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Move to history (2)'), findsOneWidget);

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
