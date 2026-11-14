import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/staff_operations_dashboard.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _StaffDashboardRepository extends AdminPortalRepository {
  _StaffDashboardRepository(this.source);

  final Stream<List<AppointmentQueueItem>> source;

  @override
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() => source;

  @override
  Stream<PaccAvailabilityModel?> watchPaccAvailability() =>
      Stream.value(null);
}

void main() {
  testWidgets('dashboard calendar remains visible when queue stream fails',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _StaffDashboardRepository(
      Stream<List<AppointmentQueueItem>>.error(
        StateError('Simulated unavailable schedule'),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffOperationsDashboardPage(
          repository: repo,
          onNavigate: (AdminPortalPage _) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Appointment calendar'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);
    expect(find.textContaining('Live appointments could not be loaded'),
        findsOneWidget);
    expect(find.textContaining('Testing schedules not yet connected'),
        findsOneWidget);
  });

  testWidgets('dashboard calendar renders with no appointments',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _StaffDashboardRepository(
      Stream.value(const <AppointmentQueueItem>[]),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffOperationsDashboardPage(
          repository: repo,
          onNavigate: (AdminPortalPage _) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Appointment calendar'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);
    expect(find.textContaining('Live appointments could not be loaded'),
        findsNothing);
  });
}
