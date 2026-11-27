import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/admin_testing_service_page.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/testing_service_schedule.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeTestingAdminRepo extends AdminPortalRepository {
  _FakeTestingAdminRepo(
    this.inquiries, {
    this.role = AccessRole.counselor,
    this.superAdmin = false,
    this.uid = 'coun-1',
  });

  final List<AdminInquiryModel> inquiries;
  final AccessRole role;
  final bool superAdmin;
  final String uid;
  bool watchedAppointments = false;

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  String? get currentUserId => uid;

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() => Stream.value(inquiries);

  @override
  Stream<List<AdminInquiryModel>> watchInquiryStatuses() =>
      Stream.value(inquiries);

  @override
  Stream<InquirySla> watchInquirySla() =>
      Stream.value(const InquirySla(hours: null));

  @override
  Stream<List<AppointmentModel>> watchAppointments() {
    watchedAppointments = true;
    return Stream.value(const []);
  }
}

AdminInquiryModel _testingInquiry(
  String id, {
  required String name,
  required String roleLabel,
  required TestingScheduleStatus scheduleStatus,
  required DateTime createdAt,
  String? mobile,
  String? email,
  String? studentNumber,
  String? proposedByName,
  String? cancelReason,
}) => AdminInquiryModel.fromJson({
  'id': id,
  'userId': 'u-$id',
  'name': name,
  'email': email ?? '$id@ucu.edu.ph',
  'studentNumber': ?studentNumber,
  'role': roleLabel,
  'subject': 'Testing Service Schedule Request',
  'message': 'Testing request $id',
  'category': 'Service Form',
  'formType': testingServiceFormType,
  'contactNumber': mobile ?? '+63 917 000 0001',
  'formData': {'Client type': roleLabel},
  'assigneeIds': ['coun-1'],
  'assigneeLabels': {'coun-1': 'Dr. Elena Cruz'},
  'status': scheduleStatus == TestingScheduleStatus.awaitingSchedule
      ? 'pending'
      : 'in_progress',
  'createdAt': createdAt.toIso8601String(),
  'testingDocuments': {
    'endorsementLetter': {
      'path':
          'testing_service_files/u-$id/endorsement_letter/0123456789abcdef0123456789abcdef.png',
      'name': 'endorsement.png',
      'contentType': 'image/png',
      'size': 1024,
      'kind': 'endorsement_letter',
    },
    'officialReceipt': {
      'path':
          'testing_service_files/u-$id/official_receipt/0123456789abcdef0123456789abcdef.png',
      'name': 'receipt.png',
      'contentType': 'image/png',
      'size': 2048,
      'kind': 'official_receipt',
    },
  },
  'testingSchedule': {
    'status': scheduleStatus.storedValue,
    'proposedByName': proposedByName,
    'cancelReason': cancelReason,
    'rescheduleCount':
        scheduleStatus == TestingScheduleStatus.rescheduleRequested ? 1 : 0,
    'maxReschedules': 1,
    'revision': 1,
  },
});

AdminInquiryModel _generalInquiry(String id) => AdminInquiryModel(
  id: id,
  userId: 'gen-$id',
  name: 'General Student',
  email: 'gen@ucu.edu.ph',
  subject: 'General Question',
  message: 'How to contact PACC?',
  category: 'General',
  createdAt: DateTime(2026, 11, 27, 8),
  status: InquiryStatus.pending,
);

void main() {
  testWidgets(
    'AdminTestingServicePage displays all KPI counts (including Cancelled), opens decision dialog, and never reads appointments',
    (tester) async {
      final repo = _FakeTestingAdminRepo([
        _testingInquiry(
          't1',
          name: 'Ana OJT',
          roleLabel: 'Student (OJT)',
          scheduleStatus: TestingScheduleStatus.awaitingSchedule,
          createdAt: DateTime(2026, 11, 27, 10),
        ),
        _testingInquiry(
          't2',
          name: 'Prof. Reyes',
          roleLabel: 'Teaching Employee',
          scheduleStatus: TestingScheduleStatus.proposed,
          createdAt: DateTime(2026, 11, 27, 11),
          proposedByName: 'Dr. Elena Cruz',
        ),
        _testingInquiry(
          't3',
          name: 'Staff Lim',
          roleLabel: 'Non-Teaching Employee',
          scheduleStatus: TestingScheduleStatus.rescheduleRequested,
          createdAt: DateTime(2026, 11, 27, 12),
        ),
        _testingInquiry(
          't4',
          name: 'Ben OJT',
          roleLabel: 'Student (OJT)',
          scheduleStatus: TestingScheduleStatus.confirmed,
          createdAt: DateTime(2026, 11, 27, 13),
        ),
        _testingInquiry(
          't5',
          name: 'Ella OJT',
          roleLabel: 'Student (OJT)',
          email: '20220367@students.mindmate.local',
          studentNumber: '20220367',
          scheduleStatus: TestingScheduleStatus.cancelled,
          cancelReason: 'Invalid or unreadable Official Receipt (PHP 250.00)',
          createdAt: DateTime(2026, 11, 27, 14),
        ),
        _testingInquiry(
          't6',
          name: 'Gino OJT',
          roleLabel: 'Student (OJT)',
          scheduleStatus: TestingScheduleStatus.completed,
          createdAt: DateTime(2026, 11, 27, 15),
        ),
        _generalInquiry('g1'),
      ]);

      AdminInquiryModel? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminTestingServicePage(
                repository: repo,
                onOpenInquiry: (item) => opened = item,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Strictly separate from Appointments
      expect(repo.watchedAppointments, isFalse);
      expect(find.text('General Student'), findsNothing);
      expect(find.text('Ana OJT'), findsOneWidget);
      expect(find.text('Ella OJT'), findsOneWidget);

      // Top status metric boxes are removed; compact status filter chips + aligned cards are shown
      expect(find.byKey(const ValueKey('testing-kpi-all')), findsNothing);
      expect(find.byKey(const ValueKey('testing-kpi-completed')), findsNothing);
      expect(find.byKey(const ValueKey('testing-kpi-cancelled')), findsNothing);
      expect(find.text('All (6)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsOneWidget);
      expect(find.text('Cancelled (1)'), findsOneWidget);
      expect(find.text('STUDENT ID'), findsNWidgets(6));
      expect(find.text('SMS CONTACT'), findsNWidgets(6));
      // Synthetic email is never shown; Student Number is shown instead
      expect(find.textContaining('students.mindmate.local'), findsNothing);
      expect(find.text('Student No. 20220367'), findsOneWidget);

      // Filter by Completed chip
      await tester.ensureVisible(
        find.byKey(const ValueKey('testing-filter-completed')),
      );
      await tester.tap(find.byKey(const ValueKey('testing-filter-completed')));
      await tester.pumpAndSettle();
      expect(find.text('Gino OJT'), findsOneWidget);
      expect(find.text('Ana OJT'), findsNothing);

      // Filter by Cancelled chip
      await tester.ensureVisible(
        find.byKey(const ValueKey('testing-filter-cancelled')),
      );
      await tester.tap(find.byKey(const ValueKey('testing-filter-cancelled')));
      await tester.pumpAndSettle();
      expect(find.text('Ella OJT'), findsOneWidget);
      expect(find.text('Ana OJT'), findsNothing);

      // Reset to All, test Schedule / Decide dialog and View Details callback
      await tester.ensureVisible(
        find.byKey(const ValueKey('testing-filter-all')),
      );
      await tester.tap(find.byKey(const ValueKey('testing-filter-all')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('testing-decide-btn-t1')),
      );
      await tester.tap(find.byKey(const ValueKey('testing-decide-btn-t1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('testing-decision-dialog-t1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-testing-action-dropdown')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('testing-review-btn-t1')),
      );
      await tester.tap(find.byKey(const ValueKey('testing-review-btn-t1')));
      await tester.pumpAndSettle();
      expect(opened?.id, 't1');
    },
  );

  testWidgets(
    'Testing Service is removed from Workspace sidebar and accessible inside AdminInquiriesPage',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortalWorkspaceNavigation(
              page: AdminPortalPage.appointments,
              accessRole: AccessRole.counselor,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appointments'), findsOneWidget);
      expect(find.text('Inquiries'), findsOneWidget);
      expect(find.text('Testing Service'), findsNothing);

      final adminRepo = _FakeTestingAdminRepo(
        [
          _testingInquiry(
            't10',
            name: 'Carla OJT',
            roleLabel: 'Student (OJT)',
            scheduleStatus: TestingScheduleStatus.awaitingSchedule,
            createdAt: DateTime(2026, 11, 27, 14),
          ),
          _generalInquiry('g10'),
        ],
        role: AccessRole.admin,
        superAdmin: true,
        uid: 'admin-1',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminInquiriesPage(repository: adminRepo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All Inquiries'), findsOneWidget);
      expect(find.text('Testing Service'), findsOneWidget);
      await tester.tap(find.text('Testing Service'));
      await tester.pumpAndSettle();

      expect(find.text('Carla OJT'), findsOneWidget);
      expect(find.text('General Student'), findsNothing);

      // Admin sees supervising/monitoring view-only banner & View Details, NEVER Schedule / Decide
      expect(
        find.byKey(const ValueKey('testing-admin-readonly-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('testing-review-btn-t10')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('testing-decide-btn-t10')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Workspace nav shows Appointments & Inquiries badges and removes notification bubble/bell',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortalWorkspaceNavigation(
              page: AdminPortalPage.appointments,
              accessRole: AccessRole.admin,
              isSuperAdmin: true,
              appointmentsBadgeStream: Stream.value(3),
              inquiriesBadgeStream: Stream.value(2),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
      expect(find.byKey(const ValueKey('nav-badge-appointments')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('nav-badge-appointments')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('nav-badge-inquiries')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('nav-badge-inquiries')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    },
  );
}
