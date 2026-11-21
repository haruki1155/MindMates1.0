import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeInquiriesRepo extends AdminPortalRepository {
  _FakeInquiriesRepo(this.inquiries);

  final List<AdminInquiryModel> inquiries;
  final List<String> acknowledgedIds = [];

  @override
  AccessRole get currentAccessRole => AccessRole.admin;

  @override
  bool get isSuperAdmin => true;

  @override
  String? get currentUserId => 'admin-1';

  @override
  Stream<List<UserModel>> watchUsers() => Stream.value(const []);

  @override
  Stream<InquirySla> watchInquirySla() =>
      Stream.value(const InquirySla(hours: null));

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() => Stream.value(inquiries);

  @override
  Stream<AdminInquiryModel?> watchInquiry(String inquiryId) => Stream.value(
    inquiries.where((i) => i.id == inquiryId).firstOrNull,
  );

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
}

AdminInquiryModel _inquiry(
  String id, {
  required String subject,
  required InquiryStatus status,
  required DateTime createdAt,
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
}
