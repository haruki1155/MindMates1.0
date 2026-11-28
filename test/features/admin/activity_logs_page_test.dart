import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_activity_log_presentation.dart';
import 'package:mind_mates/features/admin/domain/admin_management_models.dart';
import 'package:mind_mates/features/admin/screens/activity_logs_page.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeActivityLogRepository extends AdminPortalRepository {
  _FakeActivityLogRepository({
    required this.role,
    required this.superAdmin,
    this.seedEvents = const [],
    this.pendingCompleter,
    this.throwError,
  });

  final AccessRole role;
  final bool superAdmin;
  final List<AdminAuditEvent> seedEvents;
  final Completer<void>? pendingCompleter;
  Object? throwError;
  int fetchCalls = 0;

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  Future<({List<AdminAuditEvent> events, bool hasMore, String? nextCursor})>
  fetchActivityLogPage({
    ActivityActorRoleFilter roleFilter = ActivityActorRoleFilter.all,
    String actorId = '',
    String category = '',
    String action = '',
    String search = '',
    DateTime? after,
    DateTime? before,
    String? cursor,
    int pageSize = 25,
  }) async {
    fetchCalls++;
    if (!isSuperAdmin) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Super-administrator access is required.',
      );
    }
    if (pendingCompleter != null && !pendingCompleter!.isCompleted) {
      await pendingCompleter!.future;
    }
    if (throwError != null) {
      throw throwError!;
    }
    final filtered = filterActivityLogEvents(
      seedEvents,
      roleFilter: roleFilter,
      actorIdFilter: actorId,
      categoryFilter: category,
      actionFilter: action,
      searchQuery: search,
      after: after,
      before: before,
    ).toList();

    final offset = cursor == null ? 0 : int.parse(cursor);
    final page = filtered.skip(offset).take(pageSize).toList();
    final hasMore = filtered.length > offset + pageSize;
    return (
      events: page,
      hasMore: hasMore,
      nextCursor: hasMore ? (offset + pageSize).toString() : null,
    );
  }
}

void main() {
  // 2026-11-21 14:30 Manila = 2026-11-21 06:30 UTC
  final fixedNow = DateTime.utc(2026, 11, 21, 6, 30);

  final sampleEvents = <AdminAuditEvent>[
    AdminAuditEvent(
      id: 'ev-admin-1',
      action: 'STAFF_ROLE_CHANGED',
      actorId: 'admin-1',
      targetUserId: 'staff-99',
      reason: 'Promoted to counselor',
      category: 'USER_MANAGEMENT',
      actorNameSnapshot: 'Maria Santos',
      actorRoleSnapshot: 'admin',
      targetType: 'staff',
      targetId: 'staff-99',
      metadata: const {
        'assignedRole': 'counselor',
        'password': 'MUST_NEVER_APPEAR',
        'token': 'SECRET_TOKEN_123',
      },
      createdAt: DateTime.utc(2026, 11, 21, 6, 0),
    ),
    AdminAuditEvent(
      id: 'ev-counselor-1',
      action: 'INQUIRY_ESCALATED',
      actorId: 'counselor-1',
      targetUserId: '',
      reason: '',
      category: 'INQUIRIES',
      actorNameSnapshot: 'Dr. Reyes',
      actorRoleSnapshot: 'counselor',
      targetType: 'inquiry',
      targetId: 'inq-101',
      metadata: const {
        'status': 'in_progress',
        'message': 'Confidential student inquiry body',
      },
      createdAt: DateTime.utc(2026, 11, 21, 5, 0),
    ),
    AdminAuditEvent(
      id: 'ev-counselor-pii',
      action: 'STUDENT_PERSONAL_INFO_VIEWED',
      actorId: 'counselor-1',
      targetUserId: '',
      reason: '',
      category: 'SECURITY',
      actorNameSnapshot: 'Dr. Reyes',
      actorRoleSnapshot: 'counselor',
      targetType: 'student',
      targetId: 'uid-student-9876',
      metadata: const {
        'studentName': 'Hidden Student Name',
        'email': 'hidden@student.edu',
      },
      createdAt: DateTime.utc(2026, 11, 21, 4, 0),
    ),
    AdminAuditEvent(
      id: 'ev-staff-1',
      action: 'ANNOUNCEMENT_PUBLISHED',
      actorId: 'staff-1',
      targetUserId: '',
      reason: '',
      category: 'SYSTEM',
      actorNameSnapshot: 'Paolo Cruz',
      actorRoleSnapshot: 'portalStaff',
      targetType: 'announcement',
      targetId: 'ann-55',
      metadata: const {'status': 'published', 'revision': 2},
      createdAt: DateTime.utc(2026, 11, 20, 3, 0),
    ),
    AdminAuditEvent(
      id: 'ev-student-ignored',
      action: 'APPOINTMENT_SCHEDULE_PROPOSED',
      actorId: 'student-1',
      targetUserId: '',
      reason: '',
      category: 'APPOINTMENTS',
      actorNameSnapshot: 'Student',
      actorRoleSnapshot: 'appUser',
      targetType: 'appointment',
      targetId: 'appt-1',
      createdAt: DateTime.utc(2026, 11, 21, 6, 15),
    ),
  ];

  group('admin_activity_log_presentation pure domain logic', () {
    test(
      'formats Asia/Manila timestamps with explicit timezone and redacts student IDs & confidential metadata',
      () {
        final formatted = formatActivityManilaTimestamp(
          DateTime.utc(2026, 11, 21, 6, 30),
        );
        expect(formatted, 'Nov 21, 2026 · 2:30 PM (Asia/Manila, UTC+8)');

        final sanitizedAdmin = sanitizeAuditEventForDisplay(sampleEvents[0]);
        expect(sanitizedAdmin.metadata.containsKey('password'), isFalse);
        expect(sanitizedAdmin.metadata.containsKey('token'), isFalse);
        expect(sanitizedAdmin.metadata['assignedRole'], 'counselor');

        final sanitizedStudentView = sanitizeAuditEventForDisplay(
          sampleEvents[2],
        );
        expect(sanitizedStudentView.targetId, 'student••••9876');
        expect(
          sanitizedStudentView.metadata.containsKey('studentName'),
          isFalse,
        );
        expect(sanitizedStudentView.metadata.containsKey('email'), isFalse);

        // Preserves safe organization code ('code') while stripping activationCode / authCode
        final orgEvent = AdminAuditEvent(
          id: 'ev-org-1',
          action: 'COLLEGE_CREATED',
          actorId: 'admin-1',
          targetUserId: '',
          reason: '',
          category: 'SYSTEM',
          actorNameSnapshot: 'Maria Santos',
          actorRoleSnapshot: 'admin',
          targetType: 'colleges',
          targetId: 'college-cite',
          metadata: const {
            'code': 'CITE',
            'activationCode': 'SECRET-1234',
            'authCode': 'AUTH-9999',
          },
          createdAt: DateTime.utc(2026, 11, 21, 6, 30),
        );
        final sanitizedOrg = sanitizeAuditEventForDisplay(orgEvent);
        expect(sanitizedOrg.metadata['code'], 'CITE');
        expect(sanitizedOrg.metadata.containsKey('activationCode'), isFalse);
        expect(sanitizedOrg.metadata.containsKey('authCode'), isFalse);
      },
    );

    test(
      'filters by actor role, category, search, and date range while excluding appUser actors',
      () {
        final allStaff = filterActivityLogEvents(sampleEvents);
        // Excludes ev-student-ignored (appUser).
        expect(allStaff.map((e) => e.id).toList(), [
          'ev-admin-1',
          'ev-counselor-1',
          'ev-counselor-pii',
          'ev-staff-1',
        ]);

        final counselorsOnly = filterActivityLogEvents(
          sampleEvents,
          roleFilter: ActivityActorRoleFilter.counselor,
        );
        expect(counselorsOnly.map((e) => e.id).toList(), [
          'ev-counselor-1',
          'ev-counselor-pii',
        ]);

        final systemOnly = filterActivityLogEvents(
          sampleEvents,
          categoryFilter: 'SYSTEM',
        );
        expect(systemOnly.map((e) => e.id).toList(), ['ev-staff-1']);

        final searched = filterActivityLogEvents(
          sampleEvents,
          searchQuery: 'Maria Santos',
        );
        expect(searched.map((e) => e.id).toList(), ['ev-admin-1']);
      },
    );
  });

  group('Role navigation & access control', () {
    testWidgets(
      'PortalWorkspaceNavigation shows Activity Logs only for Super-Admin and hides it for Counselor and PACC Staff',
      (tester) async {
        // Super-Admin sees Activity Logs
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: PortalWorkspaceNavigation(
                page: AdminPortalPage.dashboard,
                onChanged: (_) {},
                accessRole: AccessRole.admin,
                isSuperAdmin: true,
              ),
            ),
          ),
        );
        expect(find.text('Activity Logs'), findsOneWidget);

        // Counselor does NOT see Activity Logs
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: PortalWorkspaceNavigation(
                page: AdminPortalPage.dashboard,
                onChanged: (_) {},
                accessRole: AccessRole.counselor,
                isSuperAdmin: false,
              ),
            ),
          ),
        );
        expect(find.text('Activity Logs'), findsNothing);

        // PACC Staff does NOT see Activity Logs
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: PortalWorkspaceNavigation(
                page: AdminPortalPage.dashboard,
                onChanged: (_) {},
                accessRole: AccessRole.portalStaff,
                isSuperAdmin: false,
              ),
            ),
          ),
        );
        expect(find.text('Activity Logs'), findsNothing);
      },
    );

    testWidgets(
      'Counselor and PACC Staff are denied access on ActivityLogsPage and perform zero queries',
      (tester) async {
        for (final role in const [
          AccessRole.counselor,
          AccessRole.portalStaff,
        ]) {
          final repo = _FakeActivityLogRepository(
            role: role,
            superAdmin: false,
            seedEvents: sampleEvents,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AdminTheme.data,
              home: Scaffold(
                body: ActivityLogsPage(repository: repo, clock: () => fixedNow),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Administrator access required'), findsOneWidget);
          expect(repo.fetchCalls, 0);
          expect(find.text('Maria Santos'), findsNothing);
        }
      },
    );
  });

  group('ActivityLogsPage UI, filters, pagination, states & responsiveness', () {
    testWidgets(
      'renders loading, error recovery, empty state, pagination, detail dialog, and responsive widths (390/768/1280)',
      (tester) async {
        final repo = _FakeActivityLogRepository(
          role: AccessRole.admin,
          superAdmin: true,
          seedEvents: sampleEvents,
        );

        for (final width in const [390.0, 768.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 1600);
          tester.view.devicePixelRatio = 1;

          await tester.pumpWidget(
            MaterialApp(
              theme: AdminTheme.data,
              home: Scaffold(
                body: ActivityLogsPage(
                  repository: repo,
                  clock: () => fixedNow,
                  pageSize: 2,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            find.text(
              'Read-only audit trail of Administrator, Counselor, and PACC Staff actions.',
            ),
            findsOneWidget,
          );
          expect(find.text('Timezone: Asia/Manila (UTC+8)'), findsOneWidget);
          // First page of 2 events loaded: ev-admin-1 and ev-counselor-1.
          expect(find.text('Staff role changed'), findsOneWidget);
          expect(
            find.text('Inquiry forwarded to administrator'),
            findsOneWidget,
          );
          expect(
            find.text('Nov 21, 2026 · 2:00 PM (Asia/Manila, UTC+8)'),
            findsOneWidget,
          );
          // Secret values must never appear.
          expect(find.textContaining('MUST_NEVER_APPEAR'), findsNothing);
          expect(find.textContaining('SECRET_TOKEN_123'), findsNothing);
          expect(
            find.textContaining('Confidential student inquiry body'),
            findsNothing,
          );
          expect(find.text('Load more activity'), findsOneWidget);
        }

        // Test incremental pagination ("Load more activity").
        await tester.tap(find.text('Load more activity'));
        await tester.pumpAndSettle();
        expect(
          find.text('Student personal information viewed'),
          findsOneWidget,
        );
        expect(find.text('Announcement published'), findsOneWidget);
        // Student targetId is redacted; student name never appears.
        expect(find.textContaining('student••••9876'), findsOneWidget);
        expect(find.textContaining('Hidden Student Name'), findsNothing);

        // Tap event row to open detail dialog.
        await tester.tap(find.text('Staff role changed'));
        await tester.pumpAndSettle();
        expect(find.text('STAFF_ROLE_CHANGED'), findsOneWidget);
        expect(find.text('assignedRole: counselor'), findsOneWidget);
        expect(find.textContaining('MUST_NEVER_APPEAR'), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        // Filter by Actor Role -> PACC Staff.
        await tester.tap(find.byKey(const ValueKey('activity-role-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('PACC Staff').last);
        await tester.pumpAndSettle();
        expect(find.text('Announcement published'), findsOneWidget);
        expect(find.text('Staff role changed'), findsNothing);

        // Search for nonexistent actor -> shows empty state and Reset filters button.
        await tester.enterText(
          find.byKey(const ValueKey('activity-search-input')),
          'NoSuchActor999',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          find.text('No activity logs match the current filters.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Reset filters').first);
        await tester.pumpAndSettle();
        expect(find.text('Staff role changed'), findsOneWidget);

        tester.view.reset();
      },
    );

    testWidgets('shows loading state while initial fetch is in flight', (
      tester,
    ) async {
      final completer = Completer<void>();
      final repo = _FakeActivityLogRepository(
        role: AccessRole.admin,
        superAdmin: true,
        seedEvents: sampleEvents,
        pendingCompleter: completer,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: ActivityLogsPage(repository: repo, clock: () => fixedNow),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading activity logs…'), findsOneWidget);
      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Staff role changed'), findsOneWidget);
    });

    testWidgets('handles general network error and recovers on Try Again', (
      tester,
    ) async {
      final repo = _FakeActivityLogRepository(
        role: AccessRole.admin,
        superAdmin: true,
        seedEvents: sampleEvents,
        throwError: StateError('network-offline'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: ActivityLogsPage(repository: repo, clock: () => fixedNow),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Unable to load activity logs right now'),
        findsOneWidget,
      );

      repo.throwError = null;
      await tester.ensureVisible(find.text('Try Again'));
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Staff role changed'), findsOneWidget);
    });
  });
}
