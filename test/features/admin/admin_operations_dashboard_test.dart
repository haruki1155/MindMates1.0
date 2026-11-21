import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_operations_dashboard.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeDashboardRepository extends AdminPortalRepository {
  _FakeDashboardRepository({
    required this.users,
    required this.inquiries,
    required this.assessments,
    required this.appointments,
  });

  final Stream<List<UserModel>> users;
  final Stream<List<AdminInquiryModel>> inquiries;
  final Stream<List<AdminAssessmentRecord>> assessments;
  final Stream<List<AppointmentModel>> appointments;

  @override
  AccessRole get currentAccessRole => AccessRole.admin;

  @override
  bool get isSuperAdmin => true;

  @override
  Stream<List<UserModel>> watchUsers() => users;

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() => inquiries;

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() => assessments;

  @override
  Stream<List<AppointmentModel>> watchAppointments() => appointments;
}

void main() {
  final fixedNow = DateTime.utc(2026, 11, 21, 6, 0);

  testWidgets('shows loading state without artificial zeros while streams wait', (
    tester,
  ) async {
    final usersCtrl = StreamController<List<UserModel>>();
    final inquiriesCtrl = StreamController<List<AdminInquiryModel>>();
    final assessmentsCtrl = StreamController<List<AdminAssessmentRecord>>();
    final appointmentsCtrl = StreamController<List<AppointmentModel>>();
    addTearDown(() async {
      await usersCtrl.close();
      await inquiriesCtrl.close();
      await assessmentsCtrl.close();
      await appointmentsCtrl.close();
    });

    final repo = _FakeDashboardRepository(
      users: usersCtrl.stream,
      inquiries: inquiriesCtrl.stream,
      assessments: assessmentsCtrl.stream,
      appointments: appointmentsCtrl.stream,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: AdminOperationsDashboardPage(
            repository: repo,
            onNavigate: (_) {},
            clock: () => fixedNow,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading live operations overview…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Active users (last 30 days)'), findsNothing);
  });

  testWidgets('shows access panel on stream error', (tester) async {
    final repo = _FakeDashboardRepository(
      users: Stream.error(StateError('denied')),
      inquiries: Stream.value(const []),
      assessments: Stream.value(const []),
      appointments: Stream.value(const []),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: AdminOperationsDashboardPage(
            repository: repo,
            onNavigate: (_) {},
            clock: () => fixedNow,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('requires an authenticated staff account'),
      findsOneWidget,
    );
  });

  testWidgets('renders honest analytics, interactive charts, and responsive widths', (
    tester,
  ) async {
    final navigated = <AdminPortalPage>[];
    final repo = _FakeDashboardRepository(
      users: Stream.value([
        UserModel(
          id: 'u1',
          email: 'u1@example.com',
          name: 'Student One',
          firstName: 'Student',
          lastName: 'One',
          role: 'student',
          accessRole: AccessRole.appUser,
          lastActiveAt: fixedNow.subtract(const Duration(hours: 2)),
        ),
      ]),
      inquiries: Stream.value([
        AdminInquiryModel(
          id: 'i1',
          userId: 'u1',
          name: 'Student One',
          email: 'u1@example.com',
          category: 'General',
          subject: 'Help',
          message: 'Need help',
          status: InquiryStatus.pending,
          createdAt: fixedNow.subtract(const Duration(hours: 30)),
        ),
      ]),
      assessments: Stream.value([
        AdminAssessmentRecord(
          id: 'as1',
          userId: 'u1',
          type: 'full',
          createdAt: fixedNow.subtract(const Duration(days: 1)),
          status: 'generally_supported',
        ),
      ]),
      appointments: Stream.value([
        AppointmentModel(
          id: 'a1',
          userId: 'u1',
          fullName: 'Student One',
          scheduledAt: fixedNow,
          scheduledTime: '2:00 PM',
          location: 'PACC Office',
          concern: 'Check-in',
          contactNumber: '09171234567',
          email: 'u1@example.com',
          preferredContactMethod: 'email',
          status: 'confirmed',
          createdAt: fixedNow.subtract(const Duration(hours: 4)),
          parentAppointmentId: 'a0',
        ),
        AppointmentModel(
          id: 'a2',
          userId: 'u1',
          fullName: 'Cancelled Student',
          scheduledAt: fixedNow,
          scheduledTime: '3:00 PM',
          location: 'PACC Office',
          concern: 'Cancelled',
          contactNumber: '09171234567',
          email: 'u1@example.com',
          preferredContactMethod: 'email',
          status: 'cancelled',
          createdAt: fixedNow.subtract(const Duration(hours: 5)),
        ),
      ]),
    );

    for (final width in const [390.0, 768.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AdminOperationsDashboardPage(
              repository: repo,
              onNavigate: navigated.add,
              clock: () => fixedNow,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Active users (last 30 days)'), findsOneWidget);
      expect(find.text('Open appointments'), findsOneWidget);
      expect(find.text('Full assessments (last 7 days)'), findsOneWidget);
      expect(find.text('Open inquiries'), findsOneWidget);
      expect(find.text('Users by most recent activity day'), findsOneWidget);
      expect(find.text('Appointment status breakdown'), findsOneWidget);
      expect(find.text('Cancelled / declined'), findsOneWidget);
      expect(find.text('Confirmed / upcoming'), findsOneWidget);
      // Cancelled session is excluded from Today's Counseling Schedule.
      expect(find.text('Cancelled Student'), findsNothing);
      expect(find.text('Student One'), findsOneWidget);
      expect(find.text('Follow-up'), findsOneWidget);
      // Grounded wording checks.
      expect(
        find.textContaining('recommended for counselor follow-up'),
        findsNothing,
      );
    }

    // Tap KPI card to verify click-through navigation.
    await tester.tap(find.text('Open appointments'));
    await tester.pump();
    expect(navigated, contains(AdminPortalPage.appointments));

    // Tap status breakdown item to verify interactive highlight detail.
    await tester.tap(find.text('Cancelled / declined'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Cancelled / declined: 1 of 2 (50%)'),
      findsOneWidget,
    );

    tester.view.reset();
  });
}
