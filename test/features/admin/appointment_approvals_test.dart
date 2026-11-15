import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/appointment_approvals.dart';
import 'package:mind_mates/features/admin/widgets/appointment_approvals_panel.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

final _at = DateTime.utc(2026, 11, 20, 1);

AppointmentModel _appointment(String id, String name) => AppointmentModel(
  id: id,
  userId: 'student-$id',
  fullName: name,
  scheduledAt: _at,
  scheduledTime: '9:00 AM',
  location: 'PACC',
  status: 'requested',
  concern: 'Private concern text',
  contactNumber: '',
  email: '',
  preferredContactMethod: 'email',
  createdAt: _at,
);

Map<String, dynamic> _item(
  String id, {
  String scope = 'college',
  String? reason,
  String college = 'cite',
}) => {
  'appointmentId': id,
  'status': 'requested',
  'scheduledAt': _at.millisecondsSinceEpoch,
  'pendingStudentProposal': false,
  'collegeId': college,
  'scope': scope,
  'reason': reason,
};

class _Repo extends AdminPortalRepository {
  _Repo({
    required this.role,
    this.superAdmin = false,
    this.items = const [],
    this.error,
  }) : super(
         callableInvoker: (name, data) async {
           if (error != null) throw error;
           return {'ok': true, 'items': items, 'truncated': false};
         },
       );
  final AccessRole role;
  final bool superAdmin;
  final List<Map<String, dynamic>> items;
  final Object? error;
  @override
  AccessRole get currentAccessRole => role;
  @override
  bool get isSuperAdmin => superAdmin;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1400);
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
  test('approval items parse scope and explain exception reasons', () {
    final item = AppointmentApprovalItem.fromJson(
      _item('a1', scope: 'exception', reason: 'no_eligible_counselor'),
    );
    expect(item.appointmentId, 'a1');
    expect(item.isException, isTrue);
    expect(item.scheduledAt, _at);
    expect(
      item.reasonLabel,
      'No eligible counselor is assigned to this college',
    );
    expect(
      AppointmentApprovalItem.fromJson(
        _item('a2', scope: 'exception', reason: 'missing_college'),
      ).reasonLabel,
      'Student has no verified college',
    );
    expect(AppointmentApprovalItem.fromJson(_item('a3')).isException, isFalse);
  });

  test(
    'the repository lists approvals and passes the administrator exception reason only when given',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repository = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return {
            'ok': true,
            'items': [_item('a1')],
          };
        },
      );
      final items = await repository.listAppointmentApprovals();
      expect(items.single.appointmentId, 'a1');
      await repository.reviewAppointment(
        appointmentId: 'a1',
        action: 'confirmed',
        reply: 'Confirmed.',
        expectedScheduledAt: 1,
        expectedScheduleRevision: 0,
        expectedStatus: 'requested',
        exceptionReason: 'Counselor on approved leave',
      );
      await repository.reviewAppointment(
        appointmentId: 'a1',
        action: 'confirmed',
        reply: 'Confirmed.',
        expectedScheduledAt: 1,
        expectedScheduleRevision: 0,
        expectedStatus: 'requested',
      );
      await repository.changeAppointmentAgreement(
        _appointment('a1', 'Student'),
        'accept',
        'req-00000001',
        exceptionReason: 'Covering today',
      );
      await repository.initializeAppointmentScheduleRevision(
        appointmentId: 'a1',
        scheduledAt: _at,
        status: 'requested',
        exceptionReason: 'Covering today',
      );
      expect(calls.map((c) => c.$1), [
        'listAppointmentApprovals',
        'reviewAppointment',
        'reviewAppointment',
        'changeAppointmentAgreement',
        'initializeAppointmentScheduleRevision',
      ]);
      expect(calls[1].$2['exceptionReason'], 'Counselor on approved leave');
      expect(calls[2].$2.containsKey('exceptionReason'), isFalse);
      expect(calls[3].$2['exceptionReason'], 'Covering today');
      expect(calls[4].$2['exceptionReason'], 'Covering today');
    },
  );

  testWidgets(
    "a counselor sees My College's Approvals and opens the appointment",
    (tester) async {
      AppointmentModel? opened;
      await _pump(
        tester,
        AppointmentApprovalsPanel(
          repository: _Repo(role: AccessRole.counselor, items: [_item('a1')]),
          appointments: [
            _appointment('a1', 'Ana Reyes'),
            _appointment('a2', 'Ben Cruz'),
          ],
          onOpen: (a) => opened = a,
        ),
      );
      expect(find.textContaining("My College's Approvals"), findsOneWidget);
      expect(find.textContaining('(1)'), findsOneWidget);
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsNothing);
      expect(find.textContaining('Private concern'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
      expect(opened?.id, 'a1');
    },
  );

  testWidgets('the super-admin sees approval exceptions with their reasons', (
    tester,
  ) async {
    await _pump(
      tester,
      AppointmentApprovalsPanel(
        repository: _Repo(
          role: AccessRole.admin,
          superAdmin: true,
          items: [
            _item(
              'a2',
              scope: 'exception',
              reason: 'unverified_profile',
              college: '',
            ),
          ],
        ),
        appointments: [_appointment('a2', 'Ben Cruz')],
        onOpen: (_) {},
      ),
    );
    expect(find.textContaining('Approval exceptions'), findsOneWidget);
    expect(find.text('Ben Cruz'), findsOneWidget);
    expect(find.textContaining('profile is not verified'), findsOneWidget);
  });

  testWidgets('operational staff and other admins see no approvals panel', (
    tester,
  ) async {
    for (final repo in [
      _Repo(role: AccessRole.portalStaff),
      _Repo(role: AccessRole.admin),
    ]) {
      await _pump(
        tester,
        AppointmentApprovalsPanel(
          repository: repo,
          appointments: const [],
          onOpen: (_) {},
        ),
      );
      expect(find.textContaining('Approvals'), findsNothing);
      expect(find.textContaining('exceptions'), findsNothing);
    }
  });

  testWidgets('a failed load is reported, not shown as an empty list', (
    tester,
  ) async {
    await _pump(
      tester,
      AppointmentApprovalsPanel(
        repository: _Repo(
          role: AccessRole.counselor,
          error: FirebaseFunctionsException(
            code: 'unavailable',
            message: 'offline',
          ),
        ),
        appointments: const [],
        onOpen: (_) {},
      ),
    );
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(find.textContaining('No appointments are waiting'), findsNothing);
  });
}
