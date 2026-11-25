import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/screens/admin_assessment_results_page.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _PortalAssessmentsRepo extends AdminPortalRepository {
  _PortalAssessmentsRepo({
    required this.role,
    required this.superAdmin,
    required this.assessments,
  });

  final AccessRole role;
  final bool superAdmin;
  final List<AdminAssessmentRecord> assessments;
  int watchUsersCalls = 0;

  final _notifications =
      StreamController<List<AppNotificationModel>>.broadcast();

  @override
  AccessRole get currentAccessRole => role;

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  String? get currentUserId => 'portal-user-1';

  @override
  User? get currentAuthUser => null;

  @override
  Stream<List<AppNotificationModel>> watchPortalNotifications() =>
      _notifications.stream;

  @override
  Stream<List<AppointmentModel>> watchAppointments() =>
      Stream<List<AppointmentModel>>.value(const []);

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() =>
      Stream<List<AppointmentModel>>.value(const []);

  @override
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() =>
      Stream<List<AppointmentQueueItem>>.value(const []);

  @override
  Stream<PaccAvailabilityModel?> watchPaccAvailability() => Stream.value(null);

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream<List<AdminAssessmentRecord>>.value(assessments);

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() =>
      Stream<List<AdminInquiryModel>>.value(const []);

  @override
  Stream<List<UserModel>> watchUsers() {
    watchUsersCalls += 1;
    if (role != AccessRole.admin) {
      throw StateError('Non-admin role must not call watchUsers()');
    }
    return Stream<List<UserModel>>.value(const []);
  }

  @override
  Stream<Map<String, dynamic>?> watchOwnProfile(String userId) =>
      Stream<Map<String, dynamic>?>.value({
        'accessRole': role.name,
        'staffAccountStatus': 'approved',
        'accountStatus': 'active',
      });

  Future<void> dispose() => _notifications.close();
}

List<AdminAssessmentRecord> _sampleAssessments() => [
  // Quick assessments (with contradictory scores to verify no client recalculation)
  AdminAssessmentRecord.fromJson({
    'id': 'q-low',
    'userId': 's1',
    'type': 'quick',
    'createdAt': '2026-11-20T00:00:00.000Z',
    'score': 99,
    'overallLevel': 'low',
    'role': 'student',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'q-mild',
    'userId': 's2',
    'type': 'quick',
    'createdAt': '2026-11-19T00:00:00.000Z',
    'overallLevel': 'mild',
    'role': 'student',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'q-moderate',
    'userId': 's3',
    'type': 'quick',
    'createdAt': '2026-11-18T00:00:00.000Z',
    'overallLevel': 'moderate',
    'role': 'teaching',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'q-very-high',
    'userId': 's4',
    'type': 'quick',
    'createdAt': '2026-11-17T00:00:00.000Z',
    'score': 1,
    'overallLevel': 'veryHigh',
    'role': 'nonTeaching',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'q-missing',
    'userId': 's5',
    'type': 'quick',
    'createdAt': '2026-11-16T00:00:00.000Z',
    'role': 'student',
  }),
  // V4 sentence + profileStatus (with high score to verify no client recalculation)
  AdminAssessmentRecord.fromJson({
    'id': 'f-v4-supported',
    'userId': 's1',
    'assessmentKind': 'full',
    'createdAt': '2026-11-20T00:00:00.000Z',
    'score': 96,
    'status': 'Well-being appears generally supported.',
    'result': {'profileStatus': 'generallySupported'},
    'populationRole': 'student',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'f-v4-mostly',
    'userId': 's2',
    'assessmentKind': 'full',
    'createdAt': '2026-11-19T00:00:00.000Z',
    'status': 'Mostly supported, with an area to explore.',
    'populationRole': 'student',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'f-v4-attention',
    'userId': 's3',
    'assessmentKind': 'full',
    'createdAt': '2026-11-18T00:00:00.000Z',
    'status': 'Some areas may benefit from attention.',
    'populationRole': 'teaching',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'f-v4-help',
    'userId': 's4',
    'assessmentKind': 'full',
    'createdAt': '2026-11-17T00:00:00.000Z',
    'score': 2,
    'status': 'Support may be helpful right now.',
    'populationRole': 'nonTeaching',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'f-v3-thriving',
    'userId': 's5',
    'type': 'full',
    'createdAt': '2026-11-16T00:00:00.000Z',
    'status': 'Thriving',
    'role': 'student',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'f-unknown',
    'userId': 's6',
    'type': 'full',
    'createdAt': '2026-11-15T00:00:00.000Z',
    'status': 'custom_unmapped_band',
    'role': 'student',
  }),
  AdminAssessmentRecord.fromJson({
    'id': 'f-missing',
    'userId': 's7',
    'type': 'full',
    'createdAt': '2026-11-14T00:00:00.000Z',
    'role': 'student',
  }),
];

Future<void> _pumpPortal(
  WidgetTester tester,
  _PortalAssessmentsRepo repo,
) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: AdminPortalHome(
        key: ValueKey(repo),
        repository: repo,
        registerUnload: (_) => null,
        removeUnload: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<
  ({AdminSemanticTone tone, Color bg, Color fg, IconData icon, String label})
>
_captureBadgeSignatures(WidgetTester tester) {
  final resultsFinder = find.byType(AdminAssessmentResultsPage);
  final badges = tester.widgetList<AdminStatusBadge>(
    find.descendant(of: resultsFinder, matching: find.byType(AdminStatusBadge)),
  );
  return badges
      .map(
        (b) => (
          tone: b.presentation.tone,
          bg: b.presentation.backgroundColor,
          fg: b.presentation.foregroundColor,
          icon: b.presentation.icon,
          label: b.presentation.label,
        ),
      )
      .toList();
}

void main() {
  testWidgets(
    'PortalWorkspaceNavigation shows Assessment for admin & counselor and hides for portalStaff',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final (role, superAdmin, expectedVisible) in const [
        (AccessRole.admin, true, true),
        (AccessRole.admin, false, true),
        (AccessRole.counselor, false, true),
        (AccessRole.portalStaff, false, false),
      ]) {
        AdminPortalPage? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.data,
            home: Scaffold(
              body: SizedBox(
                width: 280,
                height: 2400,
                child: PortalWorkspaceNavigation(
                  page: AdminPortalPage.dashboard,
                  onChanged: (p) => selected = p,
                  accessRole: role,
                  isSuperAdmin: superAdmin,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final assessmentFinder = find.text('Assessment');
        if (expectedVisible) {
          expect(
            assessmentFinder,
            findsOneWidget,
            reason: '$role (superAdmin=$superAdmin) should see Assessment',
          );
          await tester.tap(assessmentFinder);
          expect(selected, AdminPortalPage.assessments);
        } else {
          expect(
            assessmentFinder,
            findsNothing,
            reason: '$role must not see Assessment',
          );
        }
      }
    },
  );

  testWidgets(
    'Admin and Counselor see identical Quick and Full Assessment semantic badge colors, icons, and labels',
    (tester) async {
      final adminRepo = _PortalAssessmentsRepo(
        role: AccessRole.admin,
        superAdmin: true,
        assessments: _sampleAssessments(),
      );
      addTearDown(adminRepo.dispose);

      await _pumpPortal(tester, adminRepo);
      await tester.tap(
        find.descendant(
          of: find.byType(PortalWorkspaceNavigation),
          matching: find.text('Assessment'),
        ),
      );
      await tester.pumpAndSettle();

      // Quick Assessment tab is active by default.
      final adminQuickBadges = _captureBadgeSignatures(tester);
      expect(adminQuickBadges, hasLength(5));
      expect(adminQuickBadges[0].tone, AdminSemanticTone.green);
      expect(adminQuickBadges[0].bg, AdminColors.greenBg);
      expect(adminQuickBadges[0].icon, Icons.check_circle_outline);
      expect(adminQuickBadges[0].label, 'Low');

      expect(adminQuickBadges[1].tone, AdminSemanticTone.blue);
      expect(adminQuickBadges[1].bg, AdminColors.blueBg);
      expect(adminQuickBadges[1].icon, Icons.info_outline);
      expect(adminQuickBadges[1].label, 'Mild');

      expect(adminQuickBadges[2].tone, AdminSemanticTone.amber);
      expect(adminQuickBadges[2].bg, AdminColors.amberBg);
      expect(adminQuickBadges[2].icon, Icons.warning_amber_outlined);
      expect(adminQuickBadges[2].label, 'Moderate');

      expect(adminQuickBadges[3].tone, AdminSemanticTone.red);
      expect(adminQuickBadges[3].bg, AdminColors.redBg);
      expect(adminQuickBadges[3].icon, Icons.priority_high_rounded);
      expect(adminQuickBadges[3].label, 'Very high');

      expect(adminQuickBadges[4].tone, AdminSemanticTone.neutral);
      expect(adminQuickBadges[4].bg, AdminColors.neutralBg);
      expect(adminQuickBadges[4].icon, Icons.help_outline);
      expect(adminQuickBadges[4].label, 'Result unavailable');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();

      final adminFullBadges = _captureBadgeSignatures(tester);
      expect(adminFullBadges, hasLength(7));
      expect(adminFullBadges[0].tone, AdminSemanticTone.green);
      expect(adminFullBadges[0].bg, AdminColors.greenBg);
      expect(adminFullBadges[0].icon, Icons.check_circle_outline);
      expect(adminFullBadges[0].label, 'Supported');

      expect(adminFullBadges[1].tone, AdminSemanticTone.blue);
      expect(adminFullBadges[1].bg, AdminColors.blueBg);
      expect(adminFullBadges[1].icon, Icons.info_outline);
      expect(adminFullBadges[1].label, 'Mostly supported');

      expect(adminFullBadges[2].tone, AdminSemanticTone.amber);
      expect(adminFullBadges[2].bg, AdminColors.amberBg);
      expect(adminFullBadges[2].icon, Icons.warning_amber_outlined);
      expect(adminFullBadges[2].label, 'Some areas need attention');

      expect(adminFullBadges[3].tone, AdminSemanticTone.red);
      expect(adminFullBadges[3].bg, AdminColors.redBg);
      expect(adminFullBadges[3].icon, Icons.priority_high_rounded);
      expect(adminFullBadges[3].label, 'Support may help');

      expect(adminFullBadges[4].tone, AdminSemanticTone.green);
      expect(adminFullBadges[4].label, 'Supported');

      expect(adminFullBadges[5].tone, AdminSemanticTone.neutral);
      expect(adminFullBadges[5].bg, AdminColors.neutralBg);
      expect(adminFullBadges[5].icon, Icons.help_outline);
      expect(adminFullBadges[5].label, 'custom unmapped band');

      expect(adminFullBadges[6].tone, AdminSemanticTone.neutral);
      expect(adminFullBadges[6].bg, AdminColors.neutralBg);
      expect(adminFullBadges[6].icon, Icons.help_outline);
      expect(adminFullBadges[6].label, 'Result unavailable');

      // Now verify Counselor sees identical Quick and Full Assessment badges and never calls watchUsers().
      final counselorRepo = _PortalAssessmentsRepo(
        role: AccessRole.counselor,
        superAdmin: false,
        assessments: _sampleAssessments(),
      );
      addTearDown(counselorRepo.dispose);

      await _pumpPortal(tester, counselorRepo);
      expect(counselorRepo.watchUsersCalls, 0);

      await tester.tap(
        find.descendant(
          of: find.byType(PortalWorkspaceNavigation),
          matching: find.text('Assessment'),
        ),
      );
      await tester.pumpAndSettle();

      expect(counselorRepo.watchUsersCalls, 0);
      final counselorQuickBadges = _captureBadgeSignatures(tester);
      expect(counselorQuickBadges, equals(adminQuickBadges));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Full Assessment'));
      await tester.pumpAndSettle();

      expect(counselorRepo.watchUsersCalls, 0);
      final counselorFullBadges = _captureBadgeSignatures(tester);
      expect(counselorFullBadges, equals(adminFullBadges));
    },
  );

  testWidgets('AdminPortalHome hides Assessment from portalStaff', (
    tester,
  ) async {
    final staffRepo = _PortalAssessmentsRepo(
      role: AccessRole.portalStaff,
      superAdmin: false,
      assessments: _sampleAssessments(),
    );
    addTearDown(staffRepo.dispose);

    await _pumpPortal(tester, staffRepo);
    expect(find.text('Assessment'), findsNothing);
    expect(staffRepo.watchUsersCalls, 0);
  });
}
