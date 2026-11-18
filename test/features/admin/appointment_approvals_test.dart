import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/appointment_approvals.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/widgets/appointment_approvals_panel.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

final _at = DateTime.utc(2026, 11, 20, 1);

AppointmentModel _appointment(
  String id,
  String name, {
  bool hasScheduleRevision = false,
  int scheduleRevision = 0,
}) => AppointmentModel(
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
  hasScheduleRevision: hasScheduleRevision,
  scheduleRevision: scheduleRevision,
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
    this.records = const [],
    this.error,
    this.onCallable,
    this.byIdFetcher,
  }) : super(
         callableInvoker: (name, data) async {
           if (onCallable != null) {
             return onCallable(name, data);
           }
           if (error != null) throw error;
           return {
             'ok': true,
             'items': items,
             'nextCursor': null,
             'hasMore': false,
             'done': true,
             'truncated': false,
             'scanned': items.length,
           };
         },
       );

  final AccessRole role;
  final bool superAdmin;
  final List<Map<String, dynamic>> items;
  final List<AppointmentModel> records;
  final Object? error;
  final Future<Map<String, dynamic>> Function(
    String name,
    Map<String, Object?> data,
  )?
  onCallable;
  final Future<AppointmentModel?> Function(String appointmentId)? byIdFetcher;

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  Stream<List<AppointmentModel>> watchAppointments() => Stream.value(records);

  @override
  Future<AppointmentModel?> fetchAppointmentById(String appointmentId) {
    if (byIdFetcher != null) return byIdFetcher!(appointmentId);
    return super.fetchAppointmentById(appointmentId);
  }
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

  test(
    'AppointmentApprovalsPage parses cursor pagination metadata and forwards cursor/limit',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repository = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return {
            'ok': true,
            'items': [_item('a1')],
            'nextCursor': 'cursor-1',
            'hasMore': true,
            'done': false,
            'truncated': true,
            'scanned': 250,
          };
        },
      );

      final page = await repository.listAppointmentApprovalsPage(
        cursor: 'c0',
        limit: 25,
      );

      expect(calls.single.$1, 'listAppointmentApprovals');
      expect(calls.single.$2, {'cursor': 'c0', 'limit': 25});
      expect(page.items.single.appointmentId, 'a1');
      expect(page.nextCursor, 'cursor-1');
      expect(page.hasMore, isTrue);
      expect(page.done, isFalse);
      expect(page.truncated, isTrue);
      expect(page.scanned, 250);
    },
  );

  testWidgets(
    'panel loads more pages deterministically without duplicates and retries load-more failures cleanly',
    (tester) async {
      var pageCalls = 0;
      var failSecondPage = true;
      final repo = _Repo(
        role: AccessRole.counselor,
        onCallable: (name, data) async {
          expect(name, 'listAppointmentApprovals');
          pageCalls += 1;
          final cursor = data['cursor'];
          if (cursor == null) {
            return {
              'ok': true,
              'items': [_item('a1')],
              'nextCursor': 'cur-1',
              'hasMore': true,
              'done': false,
              'truncated': false,
              'scanned': 200,
            };
          }
          expect(cursor, 'cur-1');
          if (failSecondPage) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'temporary blip',
            );
          }
          return {
            'ok': true,
            'items': [_item('a1'), _item('a2')],
            'nextCursor': null,
            'hasMore': false,
            'done': true,
            'truncated': false,
            'scanned': 120,
          };
        },
      );

      await _pump(
        tester,
        AppointmentApprovalsPanel(
          repository: repo,
          appointments: [
            _appointment('a1', 'Ana Reyes'),
            _appointment('a2', 'Ben Cruz'),
          ],
          onOpen: (_) {},
        ),
      );

      expect(find.textContaining('(1+)'), findsOneWidget);
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Load more approvals'), findsOneWidget);

      await tester.tap(find.text('Load more approvals'));
      await tester.pumpAndSettle();

      // Page 1 remains intact while load-more error is shown with retry.
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(
        find.textContaining('Additional approvals could not be loaded'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      failSecondPage = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(pageCalls, 3);
      expect(find.textContaining('(2)'), findsOneWidget);
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsOneWidget);
      expect(find.text('Load more approvals'), findsNothing);
    },
  );

  testWidgets(
    'panel treats empty first batch with hasMore=true as incomplete rather than empty queue',
    (tester) async {
      final repo = _Repo(
        role: AccessRole.counselor,
        onCallable: (name, data) async {
          if (data['cursor'] == null) {
            return {
              'ok': true,
              'items': const <Map<String, dynamic>>[],
              'nextCursor': 'cur-200',
              'hasMore': true,
              'done': false,
              'truncated': true,
              'scanned': 200,
            };
          }
          return {
            'ok': true,
            'items': [_item('a2')],
            'nextCursor': null,
            'hasMore': false,
            'done': true,
            'truncated': false,
            'scanned': 50,
          };
        },
      );

      await _pump(
        tester,
        AppointmentApprovalsPanel(
          repository: repo,
          appointments: [_appointment('a2', 'Ben Cruz')],
          onOpen: (_) {},
        ),
      );

      expect(find.textContaining('No appointments are waiting'), findsNothing);
      expect(
        find.textContaining('additional appointments remain'),
        findsOneWidget,
      );
      expect(find.text('Load more approvals'), findsOneWidget);

      await tester.tap(find.text('Load more approvals'));
      await tester.pumpAndSettle();

      expect(find.text('Ben Cruz'), findsOneWidget);
      expect(find.text('Load more approvals'), findsNothing);
    },
  );

  testWidgets(
    'panel refreshes on authUidChanges and clears state for non-eligible role',
    (tester) async {
      final authController = StreamController<String?>.broadcast();
      addTearDown(authController.close);
      var currentRole = AccessRole.counselor;
      var currentUid = 'uid-counselor-a';

      final repoA = _Repo(
        role: AccessRole.counselor,
        items: [_item('a1')],
      );
      final repoStaff = _Repo(
        role: AccessRole.portalStaff,
        items: [_item('a9')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppointmentApprovalsPanel(
              repository: repoA,
              appointments: [_appointment('a1', 'Ana Reyes')],
              onOpen: (_) {},
              authUidChanges: authController.stream,
              currentUserIdProvider: () => currentUid,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ana Reyes'), findsOneWidget);

      // Auth UID switch clears and reloads.
      currentUid = 'uid-counselor-b';
      authController.add(currentUid);
      await tester.pumpAndSettle();
      expect(find.text('Ana Reyes'), findsOneWidget);

      // Role switch to portalStaff hides panel and clears stale state.
      currentRole = AccessRole.portalStaff;
      expect(currentRole, AccessRole.portalStaff);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppointmentApprovalsPanel(
              repository: repoStaff,
              appointments: [_appointment('a1', 'Ana Reyes')],
              onOpen: (_) {},
              authUidChanges: authController.stream,
              currentUserIdProvider: () => currentUid,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ana Reyes'), findsNothing);
      expect(find.textContaining("My College's Approvals"), findsNothing);
    },
  );

  testWidgets(
    'panel fetches missing local appointment via fetchAppointmentById and warns if unavailable',
    (tester) async {
      AppointmentModel? opened;
      var returnDocument = true;
      final fetchedIds = <String>[];
      final repo = _Repo(
        role: AccessRole.counselor,
        items: [_item('a-remote')],
        byIdFetcher: (id) async {
          fetchedIds.add(id);
          return returnDocument ? _appointment(id, 'Remote Student') : null;
        },
      );

      await _pump(
        tester,
        AppointmentApprovalsPanel(
          repository: repo,
          appointments: const [],
          onOpen: (a) => opened = a,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
      await tester.pumpAndSettle();
      expect(fetchedIds, ['a-remote']);
      expect(opened?.id, 'a-remote');

      returnDocument = false;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
      await tester.pumpAndSettle();
      expect(fetchedIds, ['a-remote', 'a-remote']);
      expect(
        find.textContaining('This appointment is no longer available'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'super-admin review dialog sends exceptionReason, handles backend validation without double submit, and hides field for counselors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. Counselor does not see the administrator exception reason field.
      final counselorCalls = <(String, Map<String, Object?>)>[];
      final counselorRecord = _appointment(
        'appt-counselor',
        'Student Counselor Case',
        hasScheduleRevision: true,
        scheduleRevision: 1,
      );
      final counselorRepo = _Repo(
        role: AccessRole.counselor,
        superAdmin: false,
        items: const [],
        records: [counselorRecord],
        onCallable: (name, data) async {
          counselorCalls.add((name, data));
          if (name == 'listAppointmentApprovals') {
            return {'ok': true, 'items': const [], 'hasMore': false};
          }
          return {'ok': true};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminAppointmentsPage(
              repository: counselorRepo,
              onOpenAssessments: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review').first);
      await tester.pumpAndSettle();

      expect(find.text('Review appointment'), findsOneWidget);
      expect(find.text('Administrator exception reason'), findsNothing);

      await tester.tap(find.text('Send decision'));
      await tester.pumpAndSettle();
      expect(find.text('Review appointment'), findsNothing);
      final counselorReview = counselorCalls.firstWhere(
        (c) => c.$1 == 'reviewAppointment',
      );
      expect(counselorReview.$2.containsKey('exceptionReason'), isFalse);

      // 2. Super-admin sees Administrator exception reason, sees validation error on empty submit,
      // does not duplicate submission while in flight, and forwards trimmed reason on success.
      final adminCalls = <(String, Map<String, Object?>)>[];
      Completer<Map<String, dynamic>>? pendingReview;
      var failFirstReview = true;
      final exceptionRecord = _appointment(
        'appt-exc',
        'Student Exception Case',
        hasScheduleRevision: true,
        scheduleRevision: 1,
      );
      final superAdminRepo = _Repo(
        role: AccessRole.admin,
        superAdmin: true,
        records: [exceptionRecord],
        onCallable: (name, data) async {
          adminCalls.add((name, data));
          if (name == 'listAppointmentApprovals') {
            return {
              'ok': true,
              'items': [
                _item(
                  'appt-exc',
                  scope: 'exception',
                  reason: 'unverified_profile',
                  college: '',
                ),
              ],
              'hasMore': false,
              'done': true,
            };
          }
          if (name == 'reviewAppointment') {
            if (failFirstReview) {
              failFirstReview = false;
              throw FirebaseFunctionsException(
                code: 'failed-precondition',
                message:
                    'Enter an administrator exception reason (at least 5 characters).',
              );
            }
            pendingReview = Completer<Map<String, dynamic>>();
            return pendingReview!.future;
          }
          return {'ok': true};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminAppointmentsPage(
              repository: superAdminRepo,
              onOpenAssessments: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review').first);
      await tester.pumpAndSettle();

      expect(find.text('Review appointment'), findsOneWidget);
      expect(find.text('Administrator exception reason'), findsOneWidget);

      // Submitting without exception reason shows server validation error and keeps dialog open.
      await tester.tap(find.text('Send decision'));
      await tester.pumpAndSettle();
      expect(find.text('Review appointment'), findsOneWidget);
      expect(
        find.textContaining('Enter an administrator exception reason'),
        findsOneWidget,
      );

      // Enter valid reason and tap Submit; double-tap while in-flight must not issue two calls.
      await tester.enterText(
        find.widgetWithText(TextField, 'Administrator exception reason'),
        'Counselor on approved leave',
      );
      await tester.tap(find.text('Send decision'));
      await tester.pump();
      expect(find.text('Sending decision…'), findsOneWidget);
      await tester.tap(find.text('Sending decision…'), warnIfMissed: false);
      await tester.pump();

      pendingReview!.complete({'ok': true});
      await tester.pumpAndSettle();

      expect(find.text('Review appointment'), findsNothing);
      final adminReviews = adminCalls
          .where((c) => c.$1 == 'reviewAppointment')
          .toList();
      expect(adminReviews.length, 2);
      expect(adminReviews[0].$2.containsKey('exceptionReason'), isFalse);
      expect(
        adminReviews[1].$2['exceptionReason'],
        'Counselor on approved leave',
      );
    },
  );

  test(
    'repository.fetchAppointmentById uses getAppointmentForApproval callable and blocks unauthorized client roles',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      var available = true;
      final counselorRepo = _Repo(
        role: AccessRole.counselor,
        onCallable: (name, data) async {
          calls.add((name, data));
          if (!available) {
            return {
              'ok': true,
              'available': false,
              'reason': 'not_pending_approval',
              'appointment': null,
            };
          }
          return {
            'ok': true,
            'available': true,
            'appointment': {
              'id': 'appt-remote-1',
              'userId': 'student-1',
              'fullName': 'Authorized Student',
              'email': 'student@example.invalid',
              'contactNumber': '09170000001',
              'preferredContactMethod': 'email',
              'concern': 'Pending detail',
              'scheduledAt': _at.toIso8601String(),
              'scheduledTime': '9:00 AM',
              'location': 'PACC',
              'status': 'requested',
              'scheduleRevision': 2,
              'proposalRevision': 0,
              'createdAt': _at.toIso8601String(),
            },
          };
        },
      );

      final loaded = await counselorRepo.fetchAppointmentById('appt-remote-1');
      expect(calls.single.$1, 'getAppointmentForApproval');
      expect(calls.single.$2, {'appointmentId': 'appt-remote-1'});
      expect(loaded, isNotNull);
      expect(loaded!.id, 'appt-remote-1');
      expect(loaded.scheduledAt, _at);
      expect(loaded.hasScheduleRevision, isTrue);
      expect(loaded.scheduleRevision, 2);

      available = false;
      expect(await counselorRepo.fetchAppointmentById('appt-remote-1'), isNull);

      for (final blockedRepo in [
        _Repo(
          role: AccessRole.portalStaff,
          onCallable: (name, data) async {
            calls.add((name, data));
            return const {};
          },
        ),
        _Repo(
          role: AccessRole.admin,
          superAdmin: false,
          onCallable: (name, data) async {
            calls.add((name, data));
            return const {};
          },
        ),
      ]) {
        expect(await blockedRepo.fetchAppointmentById('appt-remote-1'), isNull);
      }
      expect(calls.length, 2);
    },
  );

  testWidgets(
    'panel opens missing appointment via secured callable and denies/clears UI on permission-denied without invoking onOpen',
    (tester) async {
      AppointmentModel? opened;
      var allowDetail = true;
      var listCalls = 0;
      final repo = _Repo(
        role: AccessRole.counselor,
        onCallable: (name, data) async {
          if (name == 'listAppointmentApprovals') {
            listCalls += 1;
            return {
              'ok': true,
              'items': listCalls == 1 ? [_item('a-sec')] : const [],
              'nextCursor': null,
              'hasMore': false,
              'done': true,
              'truncated': false,
            };
          }
          expect(name, 'getAppointmentForApproval');
          if (!allowDetail) {
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'Only counselors assigned to this college.',
            );
          }
          return {
            'ok': true,
            'available': true,
            'appointment': {
              'id': 'a-sec',
              'userId': 'student-sec',
              'fullName': 'Secured Fallback Student',
              'email': 'sec@example.invalid',
              'contactNumber': '09170000002',
              'preferredContactMethod': 'email',
              'concern': 'Authorized fallback concern',
              'scheduledAt': _at.toIso8601String(),
              'scheduledTime': '9:00 AM',
              'location': 'PACC',
              'status': 'requested',
              'scheduleRevision': 0,
              'proposalRevision': 0,
              'createdAt': _at.toIso8601String(),
            },
          };
        },
      );

      await _pump(
        tester,
        AppointmentApprovalsPanel(
          repository: repo,
          appointments: const [],
          onOpen: (a) => opened = a,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
      await tester.pumpAndSettle();
      expect(opened?.id, 'a-sec');
      expect(opened?.fullName, 'Secured Fallback Student');

      opened = null;
      allowDetail = false;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
      await tester.pumpAndSettle();
      expect(opened, isNull);
      expect(find.textContaining('not authorized to open'), findsOneWidget);
      expect(listCalls, 2);
      expect(find.text('No appointments are waiting for a decision.'), findsOneWidget);
    },
  );
}
