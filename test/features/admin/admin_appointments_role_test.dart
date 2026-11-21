import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _RoleAppointmentsRepo extends AdminPortalRepository {
  _RoleAppointmentsRepo(
    this.items, {
    required this.role,
    this.superAdmin = false,
  });

  final List<AppointmentModel> items;
  final AccessRole role;
  final bool superAdmin;

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  Stream<List<AppointmentModel>> watchAppointments() => Stream.value(items);
}

AppointmentModel _appt(String id, String status, String name) =>
    AppointmentModel(
      id: id,
      userId: 'u-$id',
      fullName: name,
      scheduledAt: DateTime.now().add(const Duration(days: 2)),
      scheduledTime: '10:00 AM',
      location: 'PACC Office',
      status: status,
      concern: 'Check-in',
      contactNumber: '09171234567',
      email: '$id@example.com',
      preferredContactMethod: 'email',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

void main() {
  testWidgets(
    'Admin sees Review only and read-only dialog with no Send decision',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _RoleAppointmentsRepo(
        [_appt('a1', 'requested', 'Pending Student')],
        role: AccessRole.admin,
        superAdmin: true,
      );

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

      expect(find.text('Review'), findsOneWidget);
      expect(find.byTooltip('Move to history'), findsNothing);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('PACC decision'), findsNothing);
      expect(find.text('Send decision'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    },
  );

  testWidgets(
    'Counselor retains appointment decision controls and Send decision',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _RoleAppointmentsRepo([
        _appt('a1', 'requested', 'Pending Student'),
      ], role: AccessRole.counselor);

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

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('PACC decision'), findsOneWidget);
      expect(find.text('Send decision'), findsOneWidget);
    },
  );

  testWidgets('PAACC Staff remains read-only with no Send decision', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _RoleAppointmentsRepo([
      _appt('a1', 'requested', 'Pending Student'),
    ], role: AccessRole.portalStaff);

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

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.text('PACC decision'), findsNothing);
    expect(find.text('Send decision'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('Admin does not see bulk archive controls for finalized rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _RoleAppointmentsRepo([
      _appt('a1', 'completed', 'Done Student'),
    ], role: AccessRole.admin);

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

    await tester.tap(find.textContaining('All active'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Select finished'), findsNothing);
    expect(find.textContaining('Move'), findsNothing);
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets(
    'Appointments page renders cleanly at 390, 768, and 1280 px with status badges and role-scoped actions',
    (tester) async {
      addTearDown(tester.view.reset);

      final items = [
        _appt('a1', 'requested', 'Pending Student'),
        _appt('a2', 'completed', 'Finished Student'),
      ];

      for (final width in const [390.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;

        // Admin role: status badge visible, Review visible, read-only dialog,
        // and archive/bulk-select controls hidden even when finalized rows are shown.
        final adminRepo = _RoleAppointmentsRepo(
          items,
          role: AccessRole.admin,
          superAdmin: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: AdminAppointmentsPage(
                key: ValueKey('admin-$width'),
                repository: adminRepo,
                onOpenAssessments: null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'admin appointments overflow at $width',
        );
        expect(find.byType(AdminStatusBadge), findsWidgets);
        expect(find.text('Review'), findsWidgets);

        await tester.ensureVisible(find.text('Review').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review').first);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'admin review dialog overflow at $width',
        );
        expect(find.text('Send decision'), findsNothing);
        expect(find.text('Close'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.textContaining('All active'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('All active'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'admin all-active tab overflow at $width',
        );
        expect(find.text('Finished Student'), findsOneWidget);
        expect(find.byTooltip('Move to history'), findsNothing);
        expect(find.textContaining('Select finished'), findsNothing);

        // Counselor role: status badge visible, decision dialog enabled, and
        // archive/bulk-select controls visible when finalized rows are shown.
        final counselorRepo = _RoleAppointmentsRepo(
          items,
          role: AccessRole.counselor,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: AdminAppointmentsPage(
                key: ValueKey('counselor-$width'),
                repository: counselorRepo,
                onOpenAssessments: null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'counselor appointments overflow at $width',
        );
        expect(find.byType(AdminStatusBadge), findsWidgets);
        expect(find.text('Review'), findsWidgets);

        await tester.ensureVisible(find.text('Review').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review').first);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'counselor review dialog overflow at $width',
        );
        expect(find.text('Send decision'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.textContaining('All active'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('All active'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'counselor all-active tab overflow at $width',
        );
        expect(find.text('Finished Student'), findsOneWidget);
        expect(find.byTooltip('Move to history'), findsOneWidget);
        expect(find.textContaining('Select finished'), findsOneWidget);

        // PAACC Staff role: View action only (no Review, no archive controls).
        final staffRepo = _RoleAppointmentsRepo(
          items,
          role: AccessRole.portalStaff,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: AdminAppointmentsPage(
                key: ValueKey('staff-$width'),
                repository: staffRepo,
                onOpenAssessments: null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'staff appointments overflow at $width',
        );
        expect(find.byType(AdminStatusBadge), findsWidgets);
        expect(find.text('View'), findsWidgets);
        expect(find.text('Review'), findsNothing);
        expect(find.byTooltip('Move to history'), findsNothing);
      }
    },
  );
}
