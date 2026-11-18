import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/inquiry_sla.dart';
import 'package:mind_mates/features/admin/widgets/inquiry_oversight.dart';
import 'package:mind_mates/features/admin/widgets/inquiry_routing_panel.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

final _now = DateTime.utc(2026, 11, 16, 12);

AdminInquiryModel _inquiry(
  String id, {
  required Duration age,
  Map<String, dynamic> extra = const {},
}) => AdminInquiryModel.fromJson({
  'id': id,
  'userId': 'student',
  'subject': 'Subject $id',
  'message': 'Message',
  'category': 'Service Form',
  'email': 's@x',
  'status': 'pending',
  'createdAt': _now.subtract(age).toIso8601String(),
  'collegeId': 'cite',
  'routingStatus': 'routed',
  'routingRevision': 3,
  'assigneeIds': ['c1', 's1'],
  'assigneeLabels': {'c1': 'Counselor One', 's1': 'Staff One'},
  ...extra,
});

class _Repo extends AdminPortalRepository {
  _Repo({
    this.superAdmin = false,
    this.role = AccessRole.counselor,
    this.uid = 'c1',
    int? sla = 48,
    this.replyError,
  }) : _sla = StreamController<InquirySla>.broadcast() {
    _initial = InquirySla(hours: sla);
  }
  final bool superAdmin;
  final AccessRole role;
  final String uid;
  final Object? replyError;
  final StreamController<InquirySla> _sla;
  late InquirySla _initial;
  final slaWrites = <int>[];
  final replies = <Map<String, Object?>>[];
  final takeovers = <Map<String, Object?>>[];
  int replyReads = 0;

  @override
  bool get isSuperAdmin => superAdmin;
  @override
  AccessRole get currentAccessRole => role;
  @override
  String? get currentUserId => uid;
  @override
  Stream<InquirySla> watchInquirySla() async* {
    yield _initial;
    yield* _sla.stream;
  }

  @override
  Future<void> setInquirySla(int hours) async {
    slaWrites.add(hours);
    _sla.add(InquirySla(hours: hours));
  }

  @override
  Stream<List<InquiryReply>> watchInquiryReplies(String inquiryId) {
    replyReads++;
    return Stream.value([
      InquiryReply(
        id: 'r1',
        message: 'We received your form.',
        authorName: 'Counselor One',
        authorRole: 'counselor',
        createdAt: _now,
      ),
    ]);
  }

  @override
  Future<int> replyToInquiry(
    String id, {
    required String message,
    required int expectedRevision,
    required String requestId,
  }) async {
    replies.add({
      'id': id,
      'message': message,
      'expectedRevision': expectedRevision,
      'requestId': requestId,
    });
    if (replyError != null) throw replyError!;
    return expectedRevision + 1;
  }

  @override
  Future<int> takeOverInquiry(
    String id, {
    required int expectedRevision,
    required String reason,
  }) async {
    takeovers.add({
      'id': id,
      'expectedRevision': expectedRevision,
      'reason': reason,
    });
    return expectedRevision + 1;
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1800);
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
  testWidgets(
    'the overdue panel lists only overdue inquiries with college, assignees, age and last action',
    (tester) async {
      AdminInquiryModel? opened;
      final items = [
        _inquiry(
          'late',
          age: const Duration(hours: 60),
          extra: {'acknowledgedAt': '2026-11-14T00:00:00.000Z'},
        ),
        _inquiry('fresh', age: const Duration(hours: 2)),
        _inquiry(
          'answered',
          age: const Duration(hours: 90),
          extra: {'firstResponseAt': '2026-11-13T00:00:00.000Z'},
        ),
        _inquiry(
          'closed',
          age: const Duration(hours: 90),
          extra: {'status': 'resolved'},
        ),
      ];
      await _pump(
        tester,
        InquiryOverduePanel(
          repository: _Repo(
            superAdmin: true,
            role: AccessRole.admin,
            uid: 'admin',
          ),
          inquiries: items,
          onOpen: (i) => opened = i,
          now: () => _now,
        ),
      );
      expect(find.textContaining('1 overdue'), findsOneWidget);
      expect(find.text('Subject late'), findsOneWidget);
      expect(find.text('Subject fresh'), findsNothing);
      expect(find.text('Subject answered'), findsNothing);
      expect(find.text('Subject closed'), findsNothing);
      expect(find.textContaining('cite'), findsOneWidget);
      expect(find.textContaining('Counselor One, Staff One'), findsOneWidget);
      expect(find.textContaining('60 h'), findsOneWidget);
      expect(find.textContaining('Acknowledged, no reply'), findsOneWidget);
      await tester.tap(find.text('Subject late'));
      expect(opened?.id, 'late');
    },
  );

  testWidgets(
    'without a response target nothing is flagged and the super-admin can set one',
    (tester) async {
      final repo = _Repo(
        superAdmin: true,
        role: AccessRole.admin,
        uid: 'admin',
        sla: null,
      );
      await _pump(
        tester,
        InquiryOverduePanel(
          repository: repo,
          inquiries: [_inquiry('late', age: const Duration(hours: 500))],
          onOpen: (_) {},
          now: () => _now,
        ),
      );
      expect(find.textContaining('Set a response target'), findsOneWidget);
      expect(find.text('Subject late'), findsNothing);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('48 hours').last);
      await tester.pumpAndSettle();
      expect(repo.slaWrites, [48]);
      expect(find.text('Subject late'), findsOneWidget);
    },
  );

  testWidgets('the overdue panel is not shown to staff or counselors', (
    tester,
  ) async {
    await _pump(
      tester,
      InquiryOverduePanel(
        repository: _Repo(),
        inquiries: [_inquiry('late', age: const Duration(hours: 60))],
        onOpen: (_) {},
        now: () => _now,
      ),
    );
    expect(find.textContaining('overdue'), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNothing);
  });

  testWidgets(
    'an assignee reads the timeline and replies with the current revision and a stable request id',
    (tester) async {
      final repo = _Repo();
      await _pump(
        tester,
        InquiryReplyThread(
          inquiry: _inquiry('i1', age: const Duration(hours: 5)),
          repository: repo,
        ),
      );
      expect(find.text('We received your form.'), findsOneWidget);
      expect(find.textContaining('Counselor One'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'We will call you tomorrow.',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send reply'));
      await tester.pumpAndSettle();
      expect(repo.replies.single['message'], 'We will call you tomorrow.');
      expect(repo.replies.single['expectedRevision'], 3);
      expect(
        RegExp(
          r'^[A-Za-z0-9_-]{8,128}$',
        ).hasMatch(repo.replies.single['requestId']! as String),
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'a refused reply keeps the draft and retries with the same request id',
    (tester) async {
      final repo = _Repo(
        replyError: FirebaseFunctionsException(
          code: 'unavailable',
          message: 'Network error',
        ),
      );
      await _pump(
        tester,
        InquiryReplyThread(
          inquiry: _inquiry('i1', age: const Duration(hours: 5)),
          repository: repo,
        ),
      );
      await tester.enterText(find.byType(TextField), 'Draft answer');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send reply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Network error'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft answer',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send reply'));
      await tester.pumpAndSettle();
      expect(repo.replies.length, 2);
      expect(
        repo.replies[0]['requestId'],
        repo.replies[1]['requestId'],
        reason: 'a retry must not create a second reply',
      );
    },
  );

  testWidgets(
    'after a takeover assignees cannot reply; the super-admin can; nobody replies to resolved inquiries',
    (tester) async {
      final taken = _inquiry(
        'i1',
        age: const Duration(hours: 70),
        extra: {
          'takeover': {
            'by': 'admin',
            'byName': 'Super Admin',
            'reason': 'Overdue',
          },
        },
      );
      await _pump(
        tester,
        InquiryReplyThread(inquiry: taken, repository: _Repo()),
      );
      expect(find.text('Send reply'), findsNothing);
      expect(find.textContaining('Super Admin took over'), findsOneWidget);
      await _pump(
        tester,
        InquiryReplyThread(
          inquiry: taken,
          repository: _Repo(
            superAdmin: true,
            role: AccessRole.admin,
            uid: 'admin',
          ),
        ),
      );
      expect(find.text('Send reply'), findsOneWidget);
      await _pump(
        tester,
        InquiryReplyThread(
          inquiry: _inquiry(
            'i2',
            age: const Duration(hours: 1),
            extra: {'status': 'resolved'},
          ),
          repository: _Repo(),
        ),
      );
      expect(find.text('Send reply'), findsNothing);
      await _pump(
        tester,
        InquiryReplyThread(
          inquiry: _inquiry('i3', age: const Duration(hours: 1)),
          repository: _Repo(uid: 'c2'),
        ),
      );
      expect(
        find.text('Send reply'),
        findsNothing,
        reason: 'other colleges cannot reply',
      );
    },
  );

  testWidgets(
    'the super-admin takes over from the routing panel; assignees see who took over',
    (tester) async {
      final repo = _Repo(
        superAdmin: true,
        role: AccessRole.admin,
        uid: 'admin',
      );
      await _pump(
        tester,
        InquiryRoutingPanel(
          inquiry: _inquiry('i1', age: const Duration(hours: 70)),
          repository: repo,
        ),
      );
      await tester.tap(find.text('Take over'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Past the response target',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Take over'));
      await tester.pumpAndSettle();
      expect(repo.takeovers, [
        {
          'id': 'i1',
          'expectedRevision': 3,
          'reason': 'Past the response target',
        },
      ]);

      final taken = _inquiry(
        'i1',
        age: const Duration(hours: 70),
        extra: {
          'takeover': {
            'by': 'admin',
            'byName': 'Super Admin',
            'reason': 'Past the response target',
          },
        },
      );
      await _pump(
        tester,
        InquiryRoutingPanel(inquiry: taken, repository: _Repo()),
      );
      expect(find.textContaining('Super Admin'), findsOneWidget);
      expect(find.text('Escalate to administrator'), findsNothing);
      await _pump(
        tester,
        InquiryRoutingPanel(inquiry: taken, repository: repo),
      );
      expect(find.text('Take over'), findsNothing);
    },
  );

  testWidgets(
    'portalStaff cannot open or subscribe to reply timeline or composer, even if in assigneeIds',
    (tester) async {
      final repo = _Repo(role: AccessRole.portalStaff, uid: 's1');
      await _pump(
        tester,
        InquiryReplyThread(
          inquiry: _inquiry('i1', age: const Duration(hours: 5)),
          repository: repo,
        ),
      );
      expect(repo.replyReads, 0);
      expect(find.text('Replies'), findsNothing);
      expect(find.text('We received your form.'), findsNothing);
      expect(find.text('Send reply'), findsNothing);
    },
  );
}
