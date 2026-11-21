import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
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
    'Inquiries page removes Status/Category filters and sorts Pending -> In progress -> Resolved newest first',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _FakeInquiriesRepo([
        _inquiry(
          'i_res',
          subject: 'Resolved Old',
          status: InquiryStatus.resolved,
          createdAt: DateTime.utc(2026, 11, 20, 10),
        ),
        _inquiry(
          'i_prog',
          subject: 'In Progress Mid',
          status: InquiryStatus.inProgress,
          createdAt: DateTime.utc(2026, 11, 21, 9),
        ),
        _inquiry(
          'i_pend_old',
          subject: 'Pending Older',
          status: InquiryStatus.pending,
          createdAt: DateTime.utc(2026, 11, 19, 8),
        ),
        _inquiry(
          'i_pend_new',
          subject: 'Pending Newer',
          status: InquiryStatus.pending,
          createdAt: DateTime.utc(2026, 11, 21, 10),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(body: AdminInquiriesPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      // No Status or Category dropdowns.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('All Status'), findsNothing);
      expect(find.text('All Categories'), findsNothing);

      // Compact summary strip remains visible.
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('In progress'), findsWidgets);
      expect(find.text('Resolved'), findsWidgets);

      // Deterministic vertical ordering: Pending Newer < Pending Older < In Progress Mid < Resolved Old.
      final yPendNew = tester.getTopLeft(find.text('Pending Newer')).dy;
      final yPendOld = tester.getTopLeft(find.text('Pending Older')).dy;
      final yProg = tester.getTopLeft(find.text('In Progress Mid')).dy;
      final yRes = tester.getTopLeft(find.text('Resolved Old')).dy;
      expect(yPendNew, lessThan(yPendOld));
      expect(yPendOld, lessThan(yProg));
      expect(yProg, lessThan(yRes));
    },
  );

  testWidgets(
    'Inquiry detail hides Change status menu while preserving Acknowledge receipt and read-only badge',
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
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Acknowledge receipt'), findsOneWidget);

      await tester.ensureVisible(find.text('Acknowledge receipt'));
      await tester.tap(find.text('Acknowledge receipt'));
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
        expect(find.text('Pending'), findsWidgets);
        expect(find.text('In progress'), findsWidgets);
        expect(find.text('Resolved'), findsWidgets);
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
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('Acknowledge receipt'), findsOneWidget);
        expect(find.text('Change status'), findsNothing);

        // PAACC Staff operational projection: sanitized list + detail, no overflow.
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
        expect(find.text('Pending'), findsWidgets);
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
      expect(find.text('Acknowledge receipt'), findsOneWidget);
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
      expect(find.text(InquiryStatus.inProgress.label), findsOneWidget);
      expect(find.text('Mark as Resolved'), findsOneWidget);
      expect(find.text('Unable to mark inquiry as resolved.'), findsOneWidget);

      // PAACC Staff (portalStaff) operational view does not show Mark as Resolved.
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
}
