import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/session_evidence.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';

class _Repository extends AdminPortalRepository {
  _Repository(
    this.records, {
    this.role = AccessRole.appUser,
    this.superAdmin = false,
  });

  final List<AppointmentModel> records;
  final AccessRole role;
  final bool superAdmin;
  String? agreementAction;
  int? agreementRevision;
  bool uploadCalled = false;
  Map<String, Object?>? reviewedSubmission;

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  Future<void> changeAppointmentAgreement(AppointmentModel appointment, String action, String requestId, {String? exceptionReason}) async { agreementAction = action; agreementRevision = appointment.proposalRevision; }

  @override
  Future<List<SessionEvidenceAttachment>> uploadClinicalEvidenceFiles({
    required String appointmentId,
    required List<PendingSessionEvidenceFile> files,
  }) async {
    uploadCalled = true;
    return super.uploadClinicalEvidenceFiles(
      appointmentId: appointmentId,
      files: files,
    );
  }

  @override
  Future<void> reviewAppointment({
    required String appointmentId,
    required String action,
    required String reply,
    int? expectedScheduledAt,
    required int expectedScheduleRevision,
    int expectedProposalRevision = 0,
    required String expectedStatus,
    DateTime? proposedScheduledAt,
    String? proposedScheduledTime,
    String? rescheduleReason,
    String? sessionSummary,
    List<SessionEvidenceAttachment> attachments = const [],
    bool offerFollowUp = false,
    String? followUpMessage,
    String? exceptionReason,
  }) async {
    reviewedSubmission = {
      'appointmentId': appointmentId,
      'action': action,
      'sessionSummary': sessionSummary,
      'attachments': attachments,
      'exceptionReason': exceptionReason,
    };
  }

  @override
  Future<SessionEvidenceRecord?> getClinicalSessionEvidence(
    String appointmentId,
  ) async => const SessionEvidenceRecord(
    summary: 'Existing summary',
    attachments: [
      SessionEvidenceAttachment(
        path:
            'counseling_session_files/apt/counselor/0123456789abcdef0123456789abcdef.pdf',
        name: 'Existing worksheet.pdf',
        contentType: 'application/pdf',
        size: 1024,
      ),
    ],
  );

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
  testWidgets('completed-session decision preserves summary and file upload only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = _appointment(
      'confirmed', DateTime.now().subtract(const Duration(days: 1)), 'Student A',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AdminAppointmentsPage(
        repository: _Repository([record]), onOpenAssessments: null,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Needs action 1'), findsWidgets);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Session summary (internal)'), findsOneWidget);
    expect(find.text('Session attachments'), findsOneWidget);
    expect(find.text('Add images / documents'), findsOneWidget);
    expect(find.byKey(const Key('clinical-interview-questions')), findsNothing);
    expect(find.byKey(const Key('clinical-requirements-checked')), findsNothing);
    expect(find.byKey(const Key('clinical-materials-used')), findsNothing);
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

  testWidgets(
    'super-admin disables attachment upload while preserving summary, follow-up, and attachment viewing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final confirmed = _appointment(
        'confirmed',
        DateTime.now().subtract(const Duration(days: 1)),
        'Triage Student',
      ).copyWith(hasScheduleRevision: true);
      final completed = _appointment(
        'completed',
        DateTime.now().subtract(const Duration(days: 2)),
        'Completed Student',
      );
      final repo = _Repository(
        [confirmed, completed],
        role: AccessRole.admin,
        superAdmin: true,
      );

      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.text('Session summary (internal)'), findsOneWidget);
      expect(find.text('Offer a follow-up session'), findsOneWidget);
      expect(
        find.text(
          'Session attachments can only be uploaded by an assigned college counselor.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add images / documents'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Session summary (internal)'),
        'Super-admin triage summary',
      );
      await tester.tap(find.text('Send decision'));
      await tester.pumpAndSettle();

      expect(repo.uploadCalled, isFalse);
      expect(repo.reviewedSubmission?['action'], 'completed');
      expect(
        repo.reviewedSubmission?['sessionSummary'],
        'Super-admin triage summary',
      );
      expect(repo.reviewedSubmission?['attachments'], isEmpty);

      await tester.ensureVisible(find.text('Completed 1'));
      await tester.tap(find.text('Completed 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View session documentation'));
      await tester.pumpAndSettle();
      expect(find.text('Existing summary'), findsOneWidget);
      expect(find.text('Existing worksheet.pdf'), findsOneWidget);
      expect(find.byTooltip('Download Existing worksheet.pdf'), findsOneWidget);
    },
  );

  testWidgets(
    'counselor session completion keeps clinical attachment upload enabled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final record = _appointment(
        'confirmed',
        DateTime.now().subtract(const Duration(days: 1)),
        'Counselor Student',
      );
      final repo = _Repository(
        [record],
        role: AccessRole.counselor,
        superAdmin: false,
      );

      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.text('Session summary (internal)'), findsOneWidget);
      expect(find.text('Session attachments'), findsOneWidget);
      expect(find.text('Add images / documents'), findsOneWidget);
    },
  );

  test(
    'AdminPortalRepository rejects clinical attachment uploads from super-admin and admin accounts',
    () async {
      final adminRepo = AdminPortalRepository();
      final testRepo = _Repository(
        const [],
        role: AccessRole.admin,
        superAdmin: true,
      );
      final file = PendingSessionEvidenceFile(
        name: 'notes.pdf',
        contentType: 'application/pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(
        () => testRepo.uploadClinicalEvidenceFiles(
          appointmentId: 'apt-1',
          files: [file],
        ),
        throwsStateError,
      );
      expect(adminRepo.isSuperAdmin, isFalse);
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
