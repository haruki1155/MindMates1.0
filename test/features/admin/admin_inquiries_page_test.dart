import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/features/admin/widgets/counselor_inquiry_workspace.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeInquiriesRepo extends AdminPortalRepository {
  _FakeInquiriesRepo(
    this.inquiries, {
    this.role = AccessRole.admin,
    this.superAdmin = true,
    this.uid = 'admin-1',
    this.resolveCompleter,
    this.resolveError,
  });

  List<AdminInquiryModel> inquiries;
  final AccessRole role;
  final bool superAdmin;
  final String uid;
  final Completer<void>? resolveCompleter;
  final Object? resolveError;
  final List<String> acknowledgedIds = [];
  final List<(String, int?)> resolvedCalls = [];
  final StreamController<List<AdminInquiryModel>> _controller =
      StreamController<List<AdminInquiryModel>>.broadcast();

  void emitInquiries(List<AdminInquiryModel> next) {
    inquiries = next;
    _controller.add(next);
  }

  void dispose() {
    _controller.close();
  }

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  String? get currentUserId => uid;

  @override
  Stream<List<UserModel>> watchUsers() => Stream.value(const []);

  @override
  Stream<InquirySla> watchInquirySla() =>
      Stream.value(const InquirySla(hours: null));

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() async* {
    yield inquiries;
    yield* _controller.stream;
  }

  @override
  Stream<List<AdminInquiryModel>> watchInquiryStatuses() async* {
    yield inquiries;
    yield* _controller.stream;
  }

  @override
  Stream<List<InquiryReply>> watchInquiryReplies(String inquiryId) =>
      Stream.value(const []);

  @override
  Future<void> acknowledgeInquiry(
    String inquiryId, {
    int? expectedRevision,
  }) async {
    acknowledgedIds.add(inquiryId);
  }

  @override
  Future<void> resolveInquiry(String inquiryId, {int? expectedRevision}) async {
    resolvedCalls.add((inquiryId, expectedRevision));
    if (resolveCompleter != null) {
      await resolveCompleter!.future;
    }
    if (resolveError != null) {
      throw resolveError!;
    }
  }
}

AdminInquiryModel _inquiry(
  String id, {
  required String subject,
  required InquiryStatus status,
  required DateTime createdAt,
  DateTime? acknowledgedAt,
  List<String> assigneeIds = const [],
  int routingRevision = 1,
  String? formType,
  Map<String, dynamic> formData = const {},
}) => AdminInquiryModel(
  id: id,
  userId: 'u1',
  name: 'Student $id',
  email: '$id@example.com',
  category: 'General',
  subject: subject,
  message: 'Inquiry body $id',
  status: status,
  createdAt: createdAt,
  acknowledgedAt: acknowledgedAt,
  assigneeIds: assigneeIds,
  routingRevision: routingRevision,
  formType: formType,
  formData: formData,
);

void main() {
  testWidgets(
    'Inquiries page removes Status/Category filters and sorts New -> Pending -> Resolved newest first',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _FakeInquiriesRepo(
        [
          _inquiry(
            'i_res',
            subject: 'Resolved Old',
            status: InquiryStatus.resolved,
            createdAt: DateTime.utc(2026, 11, 20, 10),
          ),
          _inquiry(
            'i_prog',
            subject: 'Legacy In Progress',
            status: InquiryStatus.inProgress,
            createdAt: DateTime.utc(2026, 11, 21, 9),
          ),
          _inquiry(
            'i_pend_ack',
            subject: 'Confirmed Pending Older',
            status: InquiryStatus.pending,
            acknowledgedAt: DateTime.utc(2026, 11, 19, 9),
            createdAt: DateTime.utc(2026, 11, 19, 8),
          ),
          _inquiry(
            'i_new',
            subject: 'New Unconfirmed',
            status: InquiryStatus.pending,
            createdAt: DateTime.utc(2026, 11, 21, 10),
          ),
        ],
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'c1',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: AdminInquiriesPage(
              repository: repo,
              initialSection: CounselorInquirySection.otherServices,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No Status or Category dropdowns.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('All Status'), findsNothing);
      expect(find.text('All Categories'), findsNothing);

      // Compact summary strip remains visible with counselor lifecycle buckets.
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('New'), findsWidgets);
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Resolved'), findsWidgets);

      // Deterministic vertical ordering: New < Confirmed/Legacy Pending < Resolved.
      final yNew = tester.getTopLeft(find.text('New Unconfirmed')).dy;
      final yProg = tester.getTopLeft(find.text('Legacy In Progress')).dy;
      final yAck = tester.getTopLeft(find.text('Confirmed Pending Older')).dy;
      final yRes = tester.getTopLeft(find.text('Resolved Old')).dy;
      expect(yNew, lessThan(yProg));
      expect(yProg, lessThan(yAck));
      expect(yAck, lessThan(yRes));
    },
  );

  testWidgets(
    'Inquiry detail hides Change status menu while preserving Confirm Receipt and read-only badge',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final item = _inquiry(
        'i1',
        subject: 'Need counseling guidance',
        status: InquiryStatus.pending,
        createdAt: DateTime.utc(2026, 11, 21, 10),
      );
      final repo = _FakeInquiriesRepo([item]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: item, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Change status'), findsNothing);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Confirm Receipt'), findsOneWidget);

      await tester.ensureVisible(find.text('Confirm Receipt'));
      await tester.tap(find.text('Confirm Receipt'));
      await tester.pumpAndSettle();
      expect(repo.acknowledgedIds, ['i1']);
    },
  );

  testWidgets(
    'Inquiries page and detail render cleanly at 390, 768, and 1280 px without overflow',
    (tester) async {
      addTearDown(tester.view.reset);

      final items = [
        _inquiry(
          'i1',
          subject: 'Pending inquiry subject for responsive check',
          status: InquiryStatus.pending,
          createdAt: DateTime.utc(2026, 11, 21, 10),
        ),
        _inquiry(
          'i2',
          subject: 'In progress inquiry subject',
          status: InquiryStatus.inProgress,
          createdAt: DateTime.utc(2026, 11, 20, 10),
        ),
        _inquiry(
          'i3',
          subject: 'Resolved inquiry subject',
          status: InquiryStatus.resolved,
          createdAt: DateTime.utc(2026, 11, 19, 10),
        ),
      ];
      final repo = _FakeInquiriesRepo(items);
      final operationalItem = AdminInquiryModel(
        id: 'op1',
        userId: '',
        name: '',
        email: '',
        category: 'General',
        subject: '',
        message: '',
        status: InquiryStatus.pending,
        createdAt: DateTime.utc(2026, 11, 21, 10),
        isOperationalProjection: true,
        operationalLabel: 'General inquiry #op1',
        monitoringStaffIds: const ['staff-1'],
      );
      final staffRepo = _FakeInquiriesRepo(
        [operationalItem],
        role: AccessRole.portalStaff,
        superAdmin: false,
        uid: 'staff-1',
      );

      for (final width in const [390.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: AdminInquiriesPage(
                key: ValueKey('admin-list-$width'),
                repository: repo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'list overflow at $width',
        );
        expect(find.text('Resolved'), findsWidgets);
        expect(find.text('Forwarded to Admin'), findsNothing);
        expect(find.text('Pending inquiry subject for responsive check'), findsNothing);
        expect(find.text('In progress inquiry subject'), findsNothing);
        expect(find.text('Resolved inquiry subject'), findsOneWidget);
        expect(find.text('All Status'), findsNothing);
        expect(find.text('All Categories'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: InquiryDetailScreen(
              key: ValueKey('admin-detail-$width'),
              inquiry: items.first,
              repository: repo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'detail overflow at $width',
        );
        expect(find.byType(AdminStatusBadge), findsOneWidget);
        expect(find.text('New'), findsOneWidget);
        expect(find.text('Confirm Receipt'), findsOneWidget);
        expect(find.text('Change status'), findsNothing);

        // PACC Staff operational projection: sanitized list + detail, no overflow.
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: AdminInquiriesPage(
                key: ValueKey('staff-list-$width'),
                repository: staffRepo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'staff inquiries list overflow at $width',
        );
        expect(find.text('General inquiry #op1'), findsOneWidget);
        expect(find.text('New'), findsWidgets);
        expect(find.text('Inquiry body i1'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: InquiryDetailScreen(
              key: ValueKey('staff-detail-$width'),
              inquiry: operationalItem,
              repository: staffRepo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'staff inquiry detail overflow at $width',
        );
        expect(find.text('Operational inquiry status'), findsOneWidget);
        expect(find.byType(AdminStatusBadge), findsOneWidget);
        expect(find.text('Change status'), findsNothing);
      }
    },
  );

  testWidgets(
    'Mark as Resolved is hidden for pending and resolved inquiries, and shown for in-progress inquiries with confirmation, loading, and status update',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1. Pending inquiry: no Mark as Resolved button (must acknowledge first).
      final pending = _inquiry(
        'i_pend',
        subject: 'Pending inquiry',
        status: InquiryStatus.pending,
        createdAt: DateTime.utc(2026, 11, 21, 10),
        assigneeIds: const ['c1'],
        routingRevision: 1,
      );
      final pendingRepo = _FakeInquiriesRepo(
        [pending],
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'c1',
      );
      addTearDown(pendingRepo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: pending, repository: pendingRepo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirm Receipt'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsNothing);
      expect(find.text('Change status'), findsNothing);

      // 2. In-progress inquiry for assigned counselor: shows Mark as Resolved,
      // confirmation dialog, loading indicator, duplicate-submit guard, and live status update.
      final completer = Completer<void>();
      final inProgress = _inquiry(
        'i_prog',
        subject: 'In progress form inquiry',
        status: InquiryStatus.inProgress,
        createdAt: DateTime.utc(2026, 11, 21, 11),
        acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
        assigneeIds: const ['c1'],
        routingRevision: 2,
        formType: 'client_feedback',
        formData: const {'Rating': 'Helpful'},
      );
      final resolveRepo = _FakeInquiriesRepo(
        [inProgress],
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'c1',
        resolveCompleter: completer,
      );
      addTearDown(resolveRepo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(
            inquiry: inProgress,
            repository: resolveRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // PDF buttons remain present for form submissions.
      expect(find.text('PDF preview'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsOneWidget);
      expect(find.text('Change status'), findsNothing);

      // Cancel in confirmation dialog leaves status unchanged and makes no call.
      await tester.ensureVisible(find.text('Mark as Resolved'));
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      expect(find.text('Mark inquiry as resolved?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(resolveRepo.resolvedCalls, isEmpty);

      // Confirm in dialog triggers loading indicator and prevents duplicate submit.
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
        ),
      );
      await tester.pump();
      expect(find.text('Marking as resolved…'), findsOneWidget);
      expect(resolveRepo.resolvedCalls, [('i_prog', 2)]);

      // Attempting another tap while loading does not submit twice.
      await tester.tap(find.text('Marking as resolved…'), warnIfMissed: false);
      await tester.pump();
      expect(resolveRepo.resolvedCalls.length, 1);

      // Complete resolution and emit updated resolved document from stream.
      completer.complete();
      resolveRepo.emitInquiries([
        _inquiry(
          'i_prog',
          subject: 'In progress form inquiry',
          status: InquiryStatus.resolved,
          createdAt: DateTime.utc(2026, 11, 21, 11),
          acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
          assigneeIds: const ['c1'],
          routingRevision: 3,
          formType: 'client_feedback',
          formData: const {'Rating': 'Helpful'},
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Inquiry marked as resolved.'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsNothing);
    },
  );

  testWidgets(
    'Failed inquiry resolution preserves in-progress state and shows error feedback; unauthorized staff do not see Mark as Resolved',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final inProgress = _inquiry(
        'i_fail',
        subject: 'Failing resolve inquiry',
        status: InquiryStatus.inProgress,
        createdAt: DateTime.utc(2026, 11, 21, 11),
        acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
        assigneeIds: const ['c1'],
        routingRevision: 2,
      );
      final failingRepo = _FakeInquiriesRepo(
        [inProgress],
        role: AccessRole.admin,
        superAdmin: true,
        uid: 'admin-1',
        resolveError: StateError('Server error'),
      );
      addTearDown(failingRepo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(
            inquiry: inProgress,
            repository: failingRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Mark as Resolved'));
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
        ),
      );
      await tester.pumpAndSettle();

      expect(failingRepo.resolvedCalls, [('i_fail', 2)]);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsOneWidget);
      expect(find.text('Unable to mark inquiry as resolved.'), findsOneWidget);

      // PACC Staff (portalStaff) operational view does not show Mark as Resolved.
      final operationalInProgress = AdminInquiryModel(
        id: 'op_prog',
        userId: '',
        name: '',
        email: '',
        category: 'General',
        subject: '',
        message: '',
        status: InquiryStatus.inProgress,
        createdAt: DateTime.utc(2026, 11, 21, 11),
        acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
        isOperationalProjection: true,
        operationalLabel: 'General inquiry #op_prog',
        monitoringStaffIds: const ['staff-1'],
        routingRevision: 2,
      );
      final staffRepo = _FakeInquiriesRepo(
        [operationalInProgress],
        role: AccessRole.portalStaff,
        superAdmin: false,
        uid: 'staff-1',
      );
      addTearDown(staffRepo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(
            inquiry: operationalInProgress,
            repository: staffRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mark as Resolved'), findsNothing);
    },
  );

  testWidgets(
    'Resolving an in-progress inquiry updates detail UI to Resolved immediately before stream emits and blocks duplicate taps',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final inProgress = _inquiry(
        'i_immediate',
        subject: 'Immediate resolve inquiry',
        status: InquiryStatus.inProgress,
        createdAt: DateTime.utc(2026, 11, 21, 11),
        acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
        assigneeIds: const ['c1'],
        routingRevision: 2,
      );
      final repo = _FakeInquiriesRepo(
        [inProgress],
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'c1',
      );
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: inProgress, repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Mark as Resolved'));
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
        ),
      );
      // Do NOT emit an updated resolved inquiry from the stream yet.
      await tester.pumpAndSettle();

      expect(repo.resolvedCalls, [('i_immediate', 2)]);
      expect(find.text('Inquiry marked as resolved.'), findsOneWidget);
      expect(find.text('Resolved'), findsWidgets);
      expect(find.text('Mark as Resolved'), findsNothing);
    },
  );

  testWidgets(
    'resolveInquiry internal/path errors show safe fallback, failed-precondition shows actionable message, and legacy missing routingRevision defaults to 0',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1. Internal error with raw message and path/token never leaks into SnackBar.
      final legacyInquiry = AdminInquiryModel.fromJson({
        'id': 'i_legacy',
        'userId': 'u1',
        'name': 'Student Legacy',
        'email': 'legacy@example.com',
        'category': 'General',
        'subject': 'Legacy Inquiry',
        'message': 'Legacy message',
        'status': 'in_progress',
        'createdAt': '2026-11-21T11:00:00.000Z',
        'acknowledgedAt': '2026-11-21T11:05:00.000Z',
        'assigneeIds': ['c1'],
      });
      expect(legacyInquiry.routingRevision, 0);

      final internalRepo = _FakeInquiriesRepo(
        [legacyInquiry],
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'c1',
        resolveError: FirebaseFunctionsException(
          code: 'internal',
          message:
              'Internal error at projects/mindmate-staging/databases/(default)/documents/inquiries/i_legacy token=secret',
        ),
      );
      addTearDown(internalRepo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: InquiryDetailScreen(
            inquiry: legacyInquiry,
            repository: internalRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Mark as Resolved'));
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
        ),
      );
      await tester.pumpAndSettle();

      expect(internalRepo.resolvedCalls, [('i_legacy', 0)]);
      expect(find.text('Unable to mark inquiry as resolved.'), findsOneWidget);
      expect(find.textContaining('Internal'), findsNothing);
      expect(find.textContaining('projects/'), findsNothing);
      expect(find.textContaining('token='), findsNothing);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsOneWidget);

      // 2. Actionable failed-precondition message is shown directly.
      final preconditionRepo = _FakeInquiriesRepo(
        [legacyInquiry],
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'c1',
        resolveError: FirebaseFunctionsException(
          code: 'failed-precondition',
          message:
              'Confirm receipt before marking this inquiry as resolved.',
        ),
      );
      addTearDown(preconditionRepo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('precondition-test'),
          theme: AdminTheme.data,
          home: InquiryDetailScreen(
            inquiry: legacyInquiry,
            repository: preconditionRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Mark as Resolved'));
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Confirm receipt before marking this inquiry as resolved.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pending'), findsOneWidget);
    },
  );

  testWidgets(
    'Inquiry detail suppresses "Internal error" on passthrough codes and restores In Progress if reopened at a higher revision',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 1. unavailable / failed-precondition carrying "Internal error" must NOT leak into SnackBar.
      for (final code in const ['unavailable', 'failed-precondition']) {
        final item = _inquiry(
          'i_leak_$code',
          subject: 'Leak guard $code',
          status: InquiryStatus.inProgress,
          createdAt: DateTime.utc(2026, 11, 21, 11),
          acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
          assigneeIds: const ['c1'],
          routingRevision: 2,
        );
        final repo = _FakeInquiriesRepo(
          [item],
          role: AccessRole.counselor,
          superAdmin: false,
          uid: 'c1',
          resolveError: FirebaseFunctionsException(
            code: code,
            message: 'Internal error',
          ),
        );
        addTearDown(repo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('leak-$code'),
            theme: AdminTheme.data,
            home: InquiryDetailScreen(inquiry: item, repository: repo),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Mark as Resolved'));
        await tester.tap(find.text('Mark as Resolved'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Internal'),
          findsNothing,
          reason: 'Leaked Internal for code=$code',
        );
      }

      // 2. Optimistically resolved inquiry reopened by server to in_progress at higher routingRevision.
      final initial = _inquiry(
        'i_reopen',
        subject: 'Reopened inquiry',
        status: InquiryStatus.inProgress,
        createdAt: DateTime.utc(2026, 11, 21, 11),
        acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
        assigneeIds: const ['c1'],
        routingRevision: 2,
      );
      final reopenRepo = _FakeInquiriesRepo(
        [initial],
        role: AccessRole.counselor,
        superAdmin: false,
        uid: 'c1',
      );
      addTearDown(reopenRepo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('reopen-test'),
          theme: AdminTheme.data,
          home: InquiryDetailScreen(inquiry: initial, repository: reopenRepo),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Mark as Resolved'));
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resolved'), findsWidgets);
      expect(find.text('Mark as Resolved'), findsNothing);

      // Stream catches up to resolved at revision 3, then reopens to in_progress at revision 4.
      reopenRepo.emitInquiries([
        _inquiry(
          'i_reopen',
          subject: 'Reopened inquiry',
          status: InquiryStatus.resolved,
          createdAt: DateTime.utc(2026, 11, 21, 11),
          acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
          assigneeIds: const ['c1'],
          routingRevision: 3,
        ),
      ]);
      await tester.pumpAndSettle();

      reopenRepo.emitInquiries([
        _inquiry(
          'i_reopen',
          subject: 'Reopened inquiry',
          status: InquiryStatus.inProgress,
          createdAt: DateTime.utc(2026, 11, 21, 11),
          acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
          assigneeIds: const ['c1'],
          routingRevision: 4,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsOneWidget);

      // Direct jump: optimistic resolve at rev 4, then stream emits in_progress at rev 5 without intermediate resolved.
      await tester.ensureVisible(find.text('Mark as Resolved'));
      await tester.tap(find.text('Mark as Resolved'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark as Resolved'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resolved'), findsWidgets);

      reopenRepo.emitInquiries([
        _inquiry(
          'i_reopen',
          subject: 'Reopened inquiry',
          status: InquiryStatus.inProgress,
          createdAt: DateTime.utc(2026, 11, 21, 11),
          acknowledgedAt: DateTime.utc(2026, 11, 21, 11, 5),
          assigneeIds: const ['c1'],
          routingRevision: 5,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsOneWidget);
    },
  );

  testWidgets(
    'Admin Inquiries page shows and counts only counselor-resolved or taken-over inquiries without Forwarded to Admin tile',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _FakeInquiriesRepo([
        _inquiry(
          'i_unprocessed_new',
          subject: 'Hidden Unprocessed New',
          status: InquiryStatus.pending,
          createdAt: DateTime.utc(2026, 11, 22, 10),
        ),
        _inquiry(
          'i_unprocessed_pending',
          subject: 'Hidden Unprocessed Pending',
          status: InquiryStatus.pending,
          acknowledgedAt: DateTime.utc(2026, 11, 22, 11),
          createdAt: DateTime.utc(2026, 11, 22, 9),
        ),
        _inquiry(
          'i_resolved',
          subject: 'Visible Resolved Inquiry',
          status: InquiryStatus.resolved,
          createdAt: DateTime.utc(2026, 11, 20, 10),
        ),
        _inquiry(
          'i_resolved_second',
          subject: 'Second Resolved Inquiry',
          status: InquiryStatus.resolved,
          createdAt: DateTime.utc(2026, 11, 21, 10),
        ),
      ]);
      addTearDown(repo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: AdminInquiriesPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hidden Unprocessed New'), findsNothing);
      expect(find.text('Hidden Unprocessed Pending'), findsNothing);
      expect(find.text('Visible Resolved Inquiry'), findsOneWidget);
      expect(find.text('Second Resolved Inquiry'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Resolved'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      expect(find.text('Forwarded to Admin'), findsNothing);
    },
  );
}
