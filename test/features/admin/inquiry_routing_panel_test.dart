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
      'assigneeIds': ['c1', 's1'],
      'assigneeLabels': {'c1': 'Counselor One', 's1': 'Staff One'},
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
  });
  final bool superAdmin;
  final AccessRole role;
  final String uid;
  final Object? error;
  final escalations = <String>[];
  final reassignments = <Map<String, Object?>>[];
  int backfills = 0;

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
  Future<void> escalateInquiry(String id, {required String reason}) async {
    if (error != null) throw error!;
    escalations.add('$id:$reason');
  }

  @override
  Future<int> reassignInquiry(
    String id, {
    required List<String> assigneeIds,
    required int expectedRevision,
    required String reason,
  }) async {
    if (error != null) throw error!;
    reassignments.add({
      'id': id,
      'assigneeIds': assigneeIds,
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
  testWidgets('badge distinguishes routed, triage, unrouted and escalated', (
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
    expect(find.text('Routed'), findsOneWidget);
    expect(find.text('Needs triage'), findsOneWidget);
    expect(find.text('Not yet routed'), findsOneWidget);
    expect(find.text('Escalated'), findsOneWidget);
  });

  testWidgets(
    'panel shows college, assignees and triage reason; assignees may escalate',
    (tester) async {
      final repo = _Repo();
      await _pump(
        tester,
        InquiryRoutingPanel(inquiry: _inquiry(), repository: repo),
      );
      expect(find.textContaining('cite'), findsOneWidget);
      expect(find.textContaining('Counselor One'), findsOneWidget);
      expect(find.textContaining('Staff One'), findsOneWidget);
      expect(find.text('Reassign'), findsNothing);
      await tester.tap(find.text('Escalate to administrator'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Needs supervisor review');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Escalate'));
      await tester.pumpAndSettle();
      expect(repo.escalations, ['inq-1:Needs supervisor review']);
    },
  );

  testWidgets(
    'escalation is hidden when already escalated, resolved, or for non-assignees',
    (tester) async {
      for (final inquiry in [
        _inquiry(
          extra: {
            'escalation': {'status': 'requested', 'reason': 'x'},
          },
        ),
        _inquiry(extra: {'status': 'resolved'}),
      ]) {
        await _pump(
          tester,
          InquiryRoutingPanel(inquiry: inquiry, repository: _Repo()),
        );
        expect(find.text('Escalate to administrator'), findsNothing);
      }
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: _inquiry(),
          repository: _Repo(uid: 'c2'),
        ),
      );
      expect(find.text('Escalate to administrator'), findsNothing);
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
      expect(find.text('Escalate to administrator'), findsNothing);
      await tester.tap(find.text('Reassign'));
      await tester.pumpAndSettle();
      expect(find.text('Other Test'), findsOneWidget);
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
}
