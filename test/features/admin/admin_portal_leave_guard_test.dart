import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/student_roster_page.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _Repo extends AdminPortalRepository {
  int signOutCalls = 0;

  @override
  AccessRole get currentAccessRole => AccessRole.admin;

  @override
  bool get isSuperAdmin => true;

  @override
  User? get currentAuthUser => null;

  // The shell listens from several places, so this has to be broadcast.
  final _notifications =
      StreamController<List<AppNotificationModel>>.broadcast();

  @override
  Stream<List<AppNotificationModel>> watchPortalNotifications() =>
      _notifications.stream;

  // The dashboard the portal opens on would otherwise reach for Firebase.
  @override
  Stream<List<UserModel>> watchUsers() =>
      Stream<List<UserModel>>.value(const []);

  @override
  Stream<List<AppointmentModel>> watchAppointments() =>
      Stream<List<AppointmentModel>>.value(const []);

  @override
  Stream<List<AdminAssessmentRecord>> watchAssessments() =>
      Stream<List<AdminAssessmentRecord>>.value(const []);

  @override
  Stream<List<AdminInquiryModel>> watchInquiries() =>
      Stream<List<AdminInquiryModel>>.value(const []);

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }
}

Future<void> _pumpPortal(
  WidgetTester tester,
  _Repo repo, {
  Object? Function(bool Function())? register,
  void Function(Object?)? remove,
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminPortalHome(
        repository: repo,
        registerUnload: register ?? (_) => null,
        removeUnload: remove ?? (_) {},
      ),
    ),
  );
  await tester.pump();
}

/// Reaches the live leave guard the portal shell holds, by opening the Student
/// Roster page and marking codes as undownloaded on the guard it was handed.
StudentRosterLeaveGuard _guardOf(WidgetTester tester) => tester
    .widget<StudentRosterPage>(find.byType(StudentRosterPage))
    .leaveGuard!;

void main() {
  testWidgets('header sign-out asks the roster leave guard first', (
    tester,
  ) async {
    final repo = _Repo();
    await _pumpPortal(tester, repo);

    await tester.tap(find.text('Student Roster'));
    await tester.pumpAndSettle();
    _guardOf(tester).hasUndownloadedCodes = true;

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    // The guard's warning, not a silent sign-out.
    expect(find.text('Leave without downloading?'), findsOneWidget);
    expect(repo.signOutCalls, 0);

    await tester.tap(find.text('Stay on page'));
    await tester.pumpAndSettle();
    expect(repo.signOutCalls, 0);
  });

  testWidgets('confirming the guard lets the sign-out through', (tester) async {
    final repo = _Repo();
    await _pumpPortal(tester, repo);

    await tester.tap(find.text('Student Roster'));
    await tester.pumpAndSettle();
    _guardOf(tester).hasUndownloadedCodes = true;

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave anyway'));
    await tester.pumpAndSettle();

    expect(repo.signOutCalls, 1);
  });

  testWidgets('with nothing pending the sign-out is not interrupted', (
    tester,
  ) async {
    final repo = _Repo();
    await _pumpPortal(tester, repo);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Leave without downloading?'), findsNothing);
    expect(repo.signOutCalls, 1);
  });

  testWidgets('the browser unload guard is registered and removed', (
    tester,
  ) async {
    final repo = _Repo();
    final registered = <bool Function()>[];
    final removed = <Object?>[];
    await _pumpPortal(
      tester,
      repo,
      register: (shouldWarn) {
        registered.add(shouldWarn);
        return 'handle-1';
      },
      remove: removed.add,
    );

    expect(registered.length, 1);
    // It reports exactly the state the in-app guard uses.
    expect(registered.single(), isFalse);
    await tester.tap(find.text('Student Roster'));
    await tester.pumpAndSettle();
    _guardOf(tester).hasUndownloadedCodes = true;
    expect(registered.single(), isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(removed, ['handle-1']);
  });
}
