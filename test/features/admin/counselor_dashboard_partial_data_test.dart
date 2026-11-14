import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/counselor_operations_dashboard.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _CounselorRepository extends AdminPortalRepository {
  _CounselorRepository({required this.cases});

  final Stream<List<AppointmentModel>> cases;

  @override
  Stream<List<AppointmentModel>> watchAppointments() => Stream.value([
    AppointmentModel(
      id: 'appt-1',
      userId: 'student-1',
      fullName: 'Sample Student',
      scheduledAt: DateTime(2026, 11, 17, 9),
      scheduledTime: '9:00 AM',
      location: 'PACC',
      status: 'confirmed',
      concern: '',
      contactNumber: '',
      email: '',
      preferredContactMethod: '',
      createdAt: DateTime(2026, 11, 12),
    ),
  ]);

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() => cases;
}

void main() {
  testWidgets('counselor retains PACC overview if assigned case query fails',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1250);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _CounselorRepository(
      cases: Stream<List<AppointmentModel>>.error(StateError('offline')),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CounselorOperationsDashboardPage(
          repository: repository,
          onNavigate: (AdminPortalPage _) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Counselor Dashboard'), findsOneWidget);
    expect(find.text('Assigned caseload unavailable'), findsOneWidget);
    expect(find.text('PACC-wide clinical operations and your assigned caseload.'),
        findsOneWidget);
  });
}
