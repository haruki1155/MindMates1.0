import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _AuthTestRepo extends AdminPortalRepository {
  Completer<PortalAccessEvaluation>? signInCompleter;
  Completer<void>? signOutCompleter;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  User? get currentAuthUser => null;

  @override
  AccessRole get currentAccessRole => AccessRole.portalStaff;

  @override
  bool get isSuperAdmin => false;

  @override
  Stream<List<AppNotificationModel>> watchPortalNotifications() =>
      Stream.value(const []);

  @override
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() =>
      Stream.value(const []);

  @override
  Stream<PaccAvailabilityModel?> watchPaccAvailability() => Stream.value(null);

  @override
  Future<PortalAccessEvaluation> signInStaff({
    required String schoolId,
    required String password,
  }) {
    signInCalls++;
    return signInCompleter!.future;
  }

  @override
  Future<void> signOut() {
    signOutCalls++;
    return signOutCompleter!.future;
  }
}

void main() {
  testWidgets(
    'AdminLoginScreen blocks duplicate submits, shows Signing in… spinner, and stays on failure',
    (tester) async {
      final repo = _AuthTestRepo();
      repo.signInCompleter = Completer<PortalAccessEvaluation>();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: AdminTheme.data,
            home: AdminLoginScreen(repository: repo),
          ),
        ),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'staff@example.com');
      await tester.enterText(fields.at(1), 'secret123');

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(repo.signInCalls, 1);
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Duplicate tap while pending is blocked.
      await tester.tap(find.text('Signing in…'));
      await tester.pump();
      expect(repo.signInCalls, 1);

      // Failure keeps user on login and shows error.
      repo.signInCompleter!.completeError(StateError('Network down'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byType(AdminLoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Portal header sign-out Cancel keeps session, shows Signing out… while pending, and stays on failure',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _AuthTestRepo();
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: AdminPortalHome(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      // Cancel leaves session intact.
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.signOutCalls, 0);
      expect(find.byType(AdminPortalHome), findsOneWidget);

      // Confirm sign-out with pending future -> shows Signing out… spinner.
      repo.signOutCompleter = Completer<void>();
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pump();

      expect(repo.signOutCalls, 1);
      expect(find.text('Signing out…'), findsOneWidget);

      // Failure does NOT navigate to login.
      repo.signOutCompleter!.completeError(StateError('Sign-out failed'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminPortalHome), findsOneWidget);
      expect(find.byType(AdminLoginScreen), findsNothing);

      // Success navigates to AdminLoginScreen.
      repo.signOutCompleter = Completer<void>()..complete();
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminLoginScreen), findsOneWidget);
    },
  );
}
