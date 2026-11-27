import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/inquiry_routing_panel.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

AdminInquiryModel _inquiry({Map<String, dynamic> extra = const {}}) =>
    AdminInquiryModel.fromJson({
      'id': 'inq-1',
      'userId': 'student',
      'subject': 'Feedback',
      'message': 'Message',
      'category': 'Service Form',
      'email': 's@example.edu',
      'status': 'pending',
      'createdAt': '2026-11-14T08:00:00.000',
      'collegeId': 'cite',
      'routingStatus': 'routed',
      'routingMode': 'automatic',
      'routingRevision': 2,
      'assigneeIds': ['c1'],
      'assigneeLabels': {'c1': 'Counselor One'},
      'monitoringStaffIds': ['s1'],
      'monitoringStaffLabels': {'s1': 'Staff One'},
      ...extra,
    });

AdminInquiryModel _operationalInquiry({
  Map<String, dynamic> extra = const {},
}) => AdminInquiryModel.fromOperationalProjection({
  'inquiryId': 'inq-1',
  'category': 'Service Form',
  'formType': 'client_feedback',
  'operationalLabel': 'Client Feedback Form',
  'status': 'pending',
  'createdAt': '2026-11-14T08:00:00.000',
  'collegeId': 'cite',
  'routingStatus': 'routed',
  'routingMode': 'manual',
  'routingRevision': 2,
  'assigneeIds': ['c1'],
  'assigneeLabels': {'c1': 'Counselor One'},
  'monitoringStaffIds': ['s1'],
  'monitoringStaffLabels': {'s1': 'Staff One'},
  ...extra,
});

UserModel _staff(
  String id,
  String first, {
  AccessRole role = AccessRole.counselor,
  StaffAccountStatus status = StaffAccountStatus.approved,
}) => UserModel(
  id: id,
  email: '$id@example.com',
  firstName: first,
  lastName: 'Test',
  accessRole: role,
  staffAccountStatus: status,
);

class _Repo extends AdminPortalRepository {
  _Repo({
    this.superAdmin = false,
    this.role = AccessRole.counselor,
    this.uid = 'c1',
    this.error,
    this.inquiriesStream,
    this.statusStream,
    this.actionError,
  });
  final bool superAdmin;
  final AccessRole role;
  final String uid;
  final Object? error;
  final Stream<List<AdminInquiryModel>>? inquiriesStream;
  final Stream<List<AdminInquiryModel>>? statusStream;
  final Object? actionError;
  final escalations = <Map<String, Object?>>[];
  final reassignments = <Map<String, Object?>>[];
  final acknowledgedIds = <String>[];
  final statusUpdates = <Map<String, Object?>>[];
  int rawReads = 0;
  int statusReads = 0;
  int replyReads = 0;
  int backfills = 0;

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() {
    rawReads++;
    return inquiriesStream ?? Stream.value([_inquiry()]);
  }

  @override
  Stream<List<AdminInquiryModel>> watchInquiryStatuses() {
    statusReads++;
    return statusStream ?? Stream.value([_operationalInquiry()]);
  }

  @override
  Stream<List<InquiryReply>> watchInquiryReplies(String inquiryId) {
    replyReads++;
    return Stream.value(const []);
  }

  @override
  Future<void> acknowledgeInquiry(String id, {int? expectedRevision}) async {
    if (actionError != null) throw actionError!;
    acknowledgedIds.add(id);
  }

  @override
  Future<void> updateInquiryStatus(
    String id,
    InquiryStatus status, {
    int? expectedRevision,
  }) async {
    if (actionError != null) throw actionError!;
    statusUpdates.add({'id': id, 'status': status.name});
  }

  @override
  bool get isSuperAdmin => superAdmin;
  @override
  AccessRole get currentAccessRole => role;
  @override
  String? get currentUserId => uid;
  @override
  Stream<List<UserModel>> watchUsers() => Stream.value([
    _staff('c1', 'Counselor'),
    _staff('c2', 'Other', role: AccessRole.counselor),
    _staff('s1', 'Staff', role: AccessRole.portalStaff),
    _staff('sus', 'Suspended', status: StaffAccountStatus.disabled),
    _staff('pending', 'Pending', status: StaffAccountStatus.pending),
    UserModel(
      id: 'admin',
      email: 'a@x',
      firstName: 'Admin',
      lastName: 'X',
      accessRole: AccessRole.admin,
    ),
  ]);
  @override
  Future<void> escalateInquiry(
    String id, {
    InquiryEscalationType? escalationType,
    String? reason,
    int? expectedRevision,
  }) async {
    escalations.add({
      'id': id,
      'escalationType': escalationType,
      'reason': reason,
      'expectedRevision': expectedRevision,
    });
    if (error != null) throw error!;
  }

  @override
  Future<int> reassignInquiry(
    String id, {
    required List<String> assigneeIds,
    List<String>? monitoringStaffIds,
    required int expectedRevision,
    required String reason,
  }) async {
    if (error != null) throw error!;
    reassignments.add({
      'id': id,
      'assigneeIds': assigneeIds,
      'monitoringStaffIds': ?monitoringStaffIds,
      'expectedRevision': expectedRevision,
      'reason': reason,
    });
    return expectedRevision + 1;
  }

  final backfillCursors = <String?>[];
  @override
  Future<InquiryRoutingBackfillResult> routeExistingInquiries({
    int limit = 100,
    String? cursor,
  }) async {
    backfills++;
    backfillCursors.add(cursor);
    return backfills == 1
        ? const InquiryRoutingBackfillResult(
            routed: 3,
            needsTriage: 1,
            done: false,
            nextCursor: 'inq-500',
          )
        : const InquiryRoutingBackfillResult(
            routed: 2,
            needsTriage: 0,
            done: true,
            nextCursor: null,
          );
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('badge distinguishes routed, triage, and unrouted states without Forwarded to Admin', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        children: [
          InquiryRoutingBadge(inquiry: _inquiry()),
          InquiryRoutingBadge(
            inquiry: _inquiry(
              extra: {
                'routingStatus': 'needs_triage',
                'routingReason': 'missing_college',
                'assigneeIds': <String>[],
              },
            ),
          ),
          InquiryRoutingBadge(
            inquiry: AdminInquiryModel.fromJson({
              'id': 'legacy',
              'status': 'pending',
              'createdAt': '2026-11-14T08:00:00.000',
            }),
          ),
          InquiryRoutingBadge(
            inquiry: _inquiry(
              extra: {
                'escalation': {'status': 'requested', 'reason': 'x'},
              },
            ),
          ),
        ],
      ),
    );
    expect(find.text('Routed'), findsNWidgets(2));
    expect(find.text('Needs triage'), findsOneWidget);
    expect(find.text('Not yet routed'), findsOneWidget);
    expect(find.text('Forwarded to Admin'), findsNothing);
  });

  testWidgets(
    'panel shows college and assignees without manual forwarding action or hint',
    (tester) async {
      final repo = _Repo();
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: _inquiry(extra: {'status': 'resolved'}),
          repository: repo,
        ),
      );
      expect(find.textContaining('College assigned'), findsOneWidget);
      expect(find.textContaining('cite'), findsNothing);
      expect(find.textContaining('Counselor One'), findsOneWidget);
      expect(find.textContaining('Staff One'), findsOneWidget);
      expect(find.text('Reassign'), findsNothing);
      expect(find.text('Forward to Administrator'), findsNothing);
      expect(
        find.text(
          'Mark this inquiry as resolved to forward it to the Administrator.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'manual forwarding controls remain hidden across counselor and portalStaff states',
    (tester) async {
      for (final inquiry in [
        _inquiry(
          extra: {
            'status': 'resolved',
            'escalation': {'status': 'requested', 'reason': 'x'},
          },
        ),
        _inquiry(),
      ]) {
        await _pump(
          tester,
          InquiryRoutingPanel(inquiry: inquiry, repository: _Repo()),
        );
        expect(find.text('Forward to Administrator'), findsNothing);
        expect(find.textContaining('Forwarded to Admin'), findsNothing);
      }
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: _operationalInquiry(),
          repository: _Repo(role: AccessRole.portalStaff, uid: 's1'),
        ),
      );
      expect(find.text('Forward to Administrator'), findsNothing);
    },
  );

  testWidgets(
    'the super-administrator reassigns to eligible staff only, with the stored revision',
    (tester) async {
      final repo = _Repo(
        superAdmin: true,
        role: AccessRole.admin,
        uid: 'admin',
      );
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: _inquiry(
            extra: {
              'routingStatus': 'needs_triage',
              'routingReason': 'no_eligible_staff',
              'assigneeIds': <String>[],
            },
          ),
          repository: repo,
        ),
      );
      expect(find.textContaining('No eligible staff'), findsOneWidget);
      expect(find.text('Forward to Administrator'), findsNothing);
      await tester.tap(find.text('Reassign'));
      await tester.pumpAndSettle();
      expect(find.text('Other Test'), findsOneWidget);
      expect(find.text('Staff Test'), findsOneWidget);
      expect(find.text('Suspended Test'), findsNothing);
      expect(find.text('Pending Test'), findsNothing);
      expect(find.text('Admin X'), findsNothing);
      await tester.tap(find.text('Other Test'));
      await tester.enterText(find.byType(TextField), 'Coverage change');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save assignment'));
      await tester.pumpAndSettle();
      expect(repo.reassignments, [
        {
          'id': 'inq-1',
          'assigneeIds': ['c2'],
          'monitoringStaffIds': ['s1'],
          'expectedRevision': 2,
          'reason': 'Coverage change',
        },
      ]);
    },
  );

  testWidgets('a refused reassignment is shown and the dialog stays open', (
    tester,
  ) async {
    final repo = _Repo(
      superAdmin: true,
      role: AccessRole.admin,
      uid: 'admin',
      error: FirebaseFunctionsException(
        code: 'failed-precondition',
        message:
            'This inquiry was updated by someone else. Reload and try again.',
      ),
    );
    await _pump(
      tester,
      InquiryRoutingPanel(inquiry: _inquiry(), repository: repo),
    );
    await tester.tap(find.text('Reassign'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Test'));
    await tester.enterText(find.byType(TextField), 'Coverage change');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save assignment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('updated by someone else'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
    'reassigning with only monitoring staff and no counselor is disabled in UI',
    (tester) async {
      final repo = _Repo(
        superAdmin: true,
        role: AccessRole.admin,
        uid: 'admin',
      );
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: _inquiry(
            extra: {
              'routingStatus': 'needs_triage',
              'routingReason': 'no_eligible_staff',
              'assigneeIds': <String>[],
              'monitoringStaffIds': <String>[],
            },
          ),
          repository: repo,
        ),
      );

      await tester.tap(find.text('Reassign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staff Test'));
      await tester.enterText(find.byType(TextField), 'Monitoring coverage');
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Select at least one eligible counselor to mark this inquiry routed.',
        ),
        findsOneWidget,
      );
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save assignment'),
      );
      expect(saveButton.onPressed, isNull);
      expect(repo.reassignments, isEmpty);

      await tester.tap(find.text('Other Test'));
      await tester.pumpAndSettle();
      final enabledSave = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save assignment'),
      );
      expect(enabledSave.onPressed, isNotNull);
    },
  );

  testWidgets('only the super-administrator sees the backfill action', (
    tester,
  ) async {
    final repo = _Repo(superAdmin: true, role: AccessRole.admin, uid: 'admin');
    await _pump(tester, InquiryBackfillButton(repository: repo));
    await tester.tap(find.text('Route existing inquiries'));
    await tester.pumpAndSettle();
    expect(repo.backfills, 1);
    expect(find.textContaining('3 routed'), findsOneWidget);
    expect(find.textContaining('More inquiries remain'), findsOneWidget);
    await tester.tap(find.text('Continue routing'));
    await tester.pumpAndSettle();
    expect(repo.backfillCursors, [null, 'inq-500']);
    expect(
      find.textContaining('All existing inquiries have been checked'),
      findsOneWidget,
    );
    expect(find.text('Route existing inquiries'), findsOneWidget);
    await _pump(tester, InquiryBackfillButton(repository: _Repo()));
    expect(find.text('Route existing inquiries'), findsNothing);
  });

  testWidgets('portal staff now see Inquiries in navigation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 1400,
            child: PortalWorkspaceNavigation(
              page: AdminPortalPage.dashboard,
              onChanged: (_) {},
              accessRole: AccessRole.portalStaff,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inquiries'), findsOneWidget);
  });

  testWidgets(
    'InquiryDetailScreen hides details and actions when inquiry is reassigned away',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = StreamController<List<AdminInquiryModel>>();
      addTearDown(controller.close);
      final initial = _inquiry(extra: {'message': 'Student inquiry body'});
      final repo = _Repo(uid: 'c1', inquiriesStream: controller.stream);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: initial, repository: repo),
        ),
      );
      controller.add([initial]);
      await tester.pumpAndSettle();

      expect(find.text('Feedback'), findsOneWidget);
      expect(find.text('Student inquiry body'), findsOneWidget);
      expect(find.text('Confirm Receipt'), findsOneWidget);
      expect(find.byTooltip('Change inquiry status'), findsNothing);
      expect(find.text('Routing'), findsOneWidget);
      expect(
        find.text('Mark this inquiry as resolved to forward it to the Administrator.'),
        findsNothing,
      );

      controller.add(const []);
      await tester.pumpAndSettle();

      expect(find.text('Inquiry no longer assigned to you'), findsOneWidget);
      expect(find.text('Back to inquiries'), findsOneWidget);
      expect(find.text('Feedback'), findsNothing);
      expect(find.text('Student inquiry body'), findsNothing);
      expect(find.text('Confirm Receipt'), findsNothing);
      expect(find.byTooltip('Change inquiry status'), findsNothing);
      expect(find.text('Routing'), findsNothing);
      expect(find.text('Forward to Administrator'), findsNothing);
    },
  );

  testWidgets(
    'InquiryDetailScreen hides details when stream emits permission error',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = StreamController<List<AdminInquiryModel>>();
      addTearDown(controller.close);
      final initial = _inquiry();
      final repo = _Repo(uid: 'c1', inquiriesStream: controller.stream);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: initial, repository: repo),
        ),
      );
      controller.addError(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Missing inquiry permission.',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unable to access this inquiry'), findsOneWidget);
      expect(find.text('Back to inquiries'), findsOneWidget);
      expect(find.text('Feedback'), findsNothing);
      expect(find.text('Message'), findsNothing);
      expect(find.text('Confirm Receipt'), findsNothing);
    },
  );

  testWidgets(
    'InquiryDetailScreen blocks pre-stream details for unassigned non-admin',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = StreamController<List<AdminInquiryModel>>();
      addTearDown(controller.close);
      final repo = _Repo(
        superAdmin: false,
        uid: 'other-counselor',
        inquiriesStream: controller.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: _inquiry(), repository: repo),
        ),
      );
      await tester.pump();

      expect(find.text('Inquiry access restricted'), findsOneWidget);
      expect(find.text('Back to inquiries'), findsOneWidget);
      expect(find.text('Feedback'), findsNothing);
      expect(find.text('Confirm Receipt'), findsNothing);
    },
  );

  testWidgets(
    'InquiryDetailScreen disables acknowledgement for resolved inquiries and surfaces callable errors',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final resolved = _inquiry(extra: {'status': 'resolved'});
      final repo = _Repo(
        superAdmin: true,
        inquiriesStream: Stream.value([resolved]),
        actionError: FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Resolved inquiries cannot be acknowledged.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: resolved, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      final resolvedButton = find.ancestor(
        of: find.text('Resolved'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(resolvedButton, findsOneWidget);
      expect(tester.widget<OutlinedButton>(resolvedButton).onPressed, isNull);
      expect(find.text('Confirm Receipt'), findsNothing);
      expect(find.byTooltip('Change inquiry status'), findsNothing);
      expect(repo.statusUpdates, isEmpty);
    },
  );

  testWidgets(
    'InquiryDetailScreen keeps super-admin full view and receipt acknowledgement',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pending = _inquiry();
      final repo = _Repo(
        superAdmin: true,
        uid: 'admin',
        role: AccessRole.admin,
        inquiriesStream: Stream.value([pending]),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: pending, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Feedback'), findsOneWidget);
      await tester.tap(find.text('Confirm Receipt'));
      await tester.pumpAndSettle();

      expect(repo.acknowledgedIds, ['inq-1']);
    },
  );

  testWidgets(
    'portalStaff sees sanitized operational status without raw PII/message/PDF and retains acknowledge/escalate',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final projected = _operationalInquiry(
        extra: {
          'escalationStatus': 'requested',
          'escalation': {'status': 'requested', 'reason': 'Secret note'},
        },
      );
      final repo = _Repo(
        superAdmin: false,
        role: AccessRole.portalStaff,
        uid: 's1',
        statusStream: Stream.value([projected]),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: projected, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        repo.rawReads,
        0,
        reason: 'portalStaff must never read raw inquiries',
      );
      expect(repo.statusReads, 1);
      expect(
        repo.replyReads,
        0,
        reason: 'portalStaff must never watch inquiry replies',
      );
      expect(find.text('Client Feedback Form'), findsOneWidget);
      expect(find.text('Feedback'), findsNothing);
      expect(find.text('Message'), findsNothing);
      expect(find.text('Form responses'), findsNothing);
      expect(find.text('Replies'), findsNothing);
      expect(find.text('Send reply'), findsNothing);
      expect(find.text('Take over'), findsNothing);
      expect(find.text('PDF preview'), findsNothing);
      expect(find.text('Download PDF'), findsNothing);
      expect(find.byTooltip('Change inquiry status'), findsNothing);
      expect(find.textContaining('Secret note'), findsNothing);
      expect(find.textContaining('s@example.edu'), findsNothing);
      expect(find.textContaining('Sanitized operational view'), findsOneWidget);

      await tester.tap(find.text('Confirm Receipt'));
      await tester.pumpAndSettle();
      expect(repo.acknowledgedIds, ['inq-1']);
    },
  );

  testWidgets(
    'InquiryRoutingPanel hides takeover details in operational projection',
    (tester) async {
      final projectedTaken = _operationalInquiry(
        extra: {
          'isTakenOver': true,
          'takeover': {
            'by': 'admin',
            'byName': 'Secret Admin Name',
            'reason': 'Confidential takeover justification',
          },
        },
      );
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: projectedTaken,
          repository: _Repo(role: AccessRole.portalStaff, uid: 's1'),
        ),
      );
      expect(find.textContaining('Administrator handling'), findsOneWidget);
      expect(find.textContaining('Secret Admin Name'), findsNothing);
      expect(
        find.textContaining('Confidential takeover justification'),
        findsNothing,
      );
      expect(find.text('Forward to Administrator'), findsNothing);
      expect(find.text('Take over'), findsNothing);
    },
  );

  testWidgets(
    'portalStaff InquiryDetailScreen handles unavailable projection with Retry and never falls back to raw inquiries',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var attempts = 0;
      final projected = _operationalInquiry();
      final repo = _RetryRepo(
        projected: projected,
        onStatusWatch: () {
          attempts++;
          return attempts == 1
              ? Stream.error(
                  FirebaseFunctionsException(
                    code: 'unavailable',
                    message: 'Service temporarily unavailable.',
                  ),
                )
              : Stream.value([projected]);
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: projected, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.rawReads, 0);
      expect(find.text('Inquiry status unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repo.rawReads, 0);
      expect(attempts, 2);
      expect(find.text('Client Feedback Form'), findsOneWidget);
    },
  );

  testWidgets(
    'InquiryRoutingPanel does not display raw INTERNAL or internal error text on callable internal failure',
    (tester) async {
      final repo = _Repo(
        superAdmin: true,
        role: AccessRole.admin,
        uid: 'admin',
        error: FirebaseFunctionsException(
          code: 'internal',
          message: 'Internal error',
        ),
      );
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: _inquiry(),
          repository: repo,
        ),
      );
      await tester.tap(find.text('Take over'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Needs admin check');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Take over'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Internal'), findsNothing);
      expect(find.textContaining('INTERNAL'), findsNothing);
      expect(find.text('The request failed.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'InquiryRoutingPanel suppresses "Internal error" on unavailable and failed-precondition passthrough codes',
    (tester) async {
      for (final code in const ['unavailable', 'failed-precondition']) {
        final repo = _Repo(
          superAdmin: true,
          role: AccessRole.admin,
          uid: 'admin',
          error: FirebaseFunctionsException(
            code: code,
            message: 'Internal error',
          ),
        );
        await _pump(
          tester,
          InquiryRoutingPanel(
            inquiry: _inquiry(),
            repository: repo,
          ),
        );
        await tester.tap(find.text('Take over'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Needs admin check');
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Take over'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Internal'),
          findsNothing,
          reason: 'Leaked Internal for code=$code',
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'super-administrator Take over and Reassign dialogs continue requiring a 3+ char reason',
    (tester) async {
      final repo = _Repo(
        superAdmin: true,
        role: AccessRole.admin,
        uid: 'admin',
      );
      await _pump(
        tester,
        InquiryRoutingPanel(inquiry: _inquiry(), repository: repo),
      );

      await tester.tap(find.text('Take over'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Take over'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Take over'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reassign'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save assignment'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save assignment'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );
}

class _RetryRepo extends _Repo {
  _RetryRepo({required this.projected, required this.onStatusWatch})
    : super(role: AccessRole.portalStaff, uid: 's1');

  final AdminInquiryModel projected;
  final Stream<List<AdminInquiryModel>> Function() onStatusWatch;

  @override
  Stream<List<AdminInquiryModel>> watchInquiryStatuses() {
    statusReads++;
    return onStatusWatch();
  }
}
