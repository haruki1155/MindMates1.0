import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/staff_appointments_page.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

AppointmentQueueItem _record(String id, String student, String college) =>
    AppointmentQueueItem(
      id: id,
      studentDisplayName: student,
      scheduledAt: DateTime(2026, 11, 18, 9),
      scheduledTime: '9:00 AM',
      status: 'confirmed',
      isArchived: false,
      assignedCounselor: 'Counselor Test',
      collegeId: college,
    );

class _StaffRepo extends AdminPortalRepository {
  int queueCalls = 0;

  @override
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() {
    queueCalls++;
    return Stream.value([
      _record('a', 'Student Alpha', 'college-a'),
      _record('b', 'Student Beta', 'college-b'),
      _record('c', 'Student Unassigned', ''),
    ]);
  }

  @override
  Stream<List<College>> watchColleges() => Stream.value(const [
    College(id: 'college-a', name: 'College A', code: 'A', active: true),
    College(id: 'college-b', name: 'College B', code: 'B', active: true),
  ]);
}

void main() {
  testWidgets('staff appointment table filters verified college IDs, not free-text guesses', (tester) async {
    tester.view.physicalSize = const Size(1550, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _StaffRepo();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: StaffAppointmentsPage(repository: repo),
    )));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('3 appointments shown'), findsOneWidget);
    expect(find.text('Student Alpha'), findsOneWidget);
    expect(find.text('Student Beta'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);

    await tester.tap(find.text('All colleges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('College A').last);
    await tester.pumpAndSettle();

    expect(find.text('1 appointment shown'), findsOneWidget);
    expect(find.text('Student Alpha'), findsOneWidget);
    expect(find.text('Student Beta'), findsNothing);
    expect(repo.queueCalls, 1);
  });

  testWidgets('staff table keeps operational schedule fields with no clinical concern column', (tester) async {
    tester.view.physicalSize = const Size(1550, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: StaffAppointmentTable(
        items: [_record('a', 'Student Alpha', 'college-a')],
        collegeNames: const {'college-a': 'College A'},
      ),
    )));
    expect(find.text('College'), findsOneWidget);
    expect(find.text('Service'), findsOneWidget);
    expect(find.text('Date & time'), findsOneWidget);
    expect(find.text('Assigned counselor'), findsOneWidget);
    expect(find.text('Counseling'), findsOneWidget);
    expect(find.text('College A'), findsOneWidget);
    expect(find.text('Concern'), findsNothing);
    expect(find.text('Clinical notes'), findsNothing);
  });
}
