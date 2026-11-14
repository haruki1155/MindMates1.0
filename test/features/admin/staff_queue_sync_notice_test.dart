import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/staff_appointments_page.dart';
import 'package:mind_mates/features/admin/screens/staff_operations_dashboard.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _EmptyQueueRepo extends AdminPortalRepository {
  @override
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() =>
      Stream.value(const <AppointmentQueueItem>[]);

  @override
  Stream<PaccAvailabilityModel?> watchPaccAvailability() => Stream.value(null);

  @override
  Stream<List<College>> watchColleges() => Stream.value(const <College>[]);
}

void main() {
  testWidgets(
    'dashboard reports an unavailable schedule sync service instead of an '
    'empty schedule',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _EmptyQueueRepo();
      repo.portalQueueSyncError.value = 'not-found';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffOperationsDashboardPage(
              repository: repo,
              onNavigate: (AdminPortalPage _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('schedule sync service is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('(not-found)'), findsOneWidget);
      expect(
        find.textContaining('No staff-safe schedule records'),
        findsNothing,
      );
    },
  );

  testWidgets('dashboard shows the plain empty notice when sync succeeded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffOperationsDashboardPage(
            repository: _EmptyQueueRepo(),
            onNavigate: (AdminPortalPage _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No staff-safe schedule records'),
      findsOneWidget,
    );
    expect(
      find.textContaining('schedule sync service is unavailable'),
      findsNothing,
    );
  });

  testWidgets(
    'appointments table reports an unavailable schedule sync service',
    (tester) async {
      tester.view.physicalSize = const Size(1550, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _EmptyQueueRepo();
      repo.portalQueueSyncError.value = 'permission-denied';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StaffAppointmentsPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('schedule sync service is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('(permission-denied)'), findsOneWidget);
    },
  );
}
