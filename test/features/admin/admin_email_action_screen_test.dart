import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/admin_main.dart';
import 'package:mind_mates/core/config/app_environment.dart';
import 'package:mind_mates/features/admin/screens/admin_email_action_screen.dart';
import 'package:mind_mates/firebase_options_selector.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakeActionCodeInfo extends Fake implements ActionCodeInfo {
  _FakeActionCodeInfo({required this.operation, required this.data});

  @override
  final ActionCodeInfoOperation operation;

  @override
  final Map<String, dynamic> data;
}

class _FakeUser extends Fake implements User {
  _FakeUser({this.emailVerified = false});

  @override
  bool emailVerified;
  int reloadCalls = 0;

  @override
  Future<void> reload() async {
    reloadCalls += 1;
  }
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  _FakeFirebaseAuth({this.user});

  final _FakeUser? user;
  String? checkEmail = 'staff@example.edu';
  String? resetEmail = 'staff@example.edu';
  Object? checkError;
  Object? applyError;
  Object? verifyResetError;
  Object? confirmResetError;
  final List<String> checkedCodes = [];
  final List<String> appliedCodes = [];
  final List<({String code, String newPassword})> confirmedResets = [];

  @override
  User? get currentUser => user;

  @override
  Future<ActionCodeInfo> checkActionCode(String code) async {
    checkedCodes.add(code);
    final error = checkError;
    if (error != null) throw error;
    return _FakeActionCodeInfo(
      operation: ActionCodeInfoOperation.verifyEmail,
      data: {'email': checkEmail},
    );
  }

  @override
  Future<void> applyActionCode(String code) async {
    appliedCodes.add(code);
    final error = applyError;
    if (error != null) throw error;
    if (user != null) user!.emailVerified = true;
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    final error = verifyResetError;
    if (error != null) throw error;
    return resetEmail ?? 'staff@example.edu';
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    final error = confirmResetError;
    if (error != null) throw error;
    confirmedResets.add((code: code, newPassword: newPassword));
  }
}

void main() {
  group('MindMateAdminApp routing', () {
    testWidgets(
      'routes /verify-email with mode=verifyEmail and oobCode to AdminEmailActionScreen',
      (tester) async {
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            '/verify-email?mode=verifyEmail&oobCode=synthetic-verify-code';
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );

        final user = _FakeUser();
        final auth = _FakeFirebaseAuth(user: user);
        final replacedLocations = <String>[];

        await tester.pumpWidget(
          MindMateAdminApp(
            auth: auth,
            onReplaceLocation: replacedLocations.add,
            authGateBuilder: (_) =>
                const Scaffold(body: Text('Sign In Gate')),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AdminEmailActionScreen), findsOneWidget);
        expect(find.text('Sign In Gate'), findsNothing);
        expect(find.text('Email verified'), findsOneWidget);
        expect(auth.checkedCodes, ['synthetic-verify-code']);
        expect(auth.appliedCodes, ['synthetic-verify-code']);
        expect(user.reloadCalls, 1);

        await tester.tap(find.text('Continue to sign in'));
        await tester.pump();
        expect(replacedLocations, hasLength(1));
        expect(
          replacedLocations.single,
          isNot(contains('mindmate-admin-staging.vercel.app')),
        );
        expect(replacedLocations.single, isNot(contains('oobCode')));
      },
    );

    // Recovery emails link here because Firebase Hosting reserves /__/*.
    testWidgets(
      'routes /reset-password with mode=resetPassword and oobCode to AdminEmailActionScreen',
      (tester) async {
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            '/reset-password?mode=resetPassword&oobCode=synthetic-reset';
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );

        await tester.pumpWidget(
          MindMateAdminApp(
            auth: _FakeFirebaseAuth()..resetEmail = 'staff@example.edu',
            onReplaceLocation: (_) {},
            authGateBuilder: (_) =>
                const Scaffold(body: Text('Sign In Gate')),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AdminEmailActionScreen), findsOneWidget);
        expect(find.text('Sign In Gate'), findsNothing);
        expect(find.text('Choose a new password'), findsOneWidget);
      },
    );

    testWidgets(
      'rejects expired and invalid codes on /reset-password without a password form',
      (tester) async {
        for (final (code, message) in [
          (
            'expired-action-code',
            'This link has expired. Return to sign in and request a new one.',
          ),
          (
            'invalid-action-code',
            'This link is invalid or has already been used. Request a new one.',
          ),
        ]) {
          final auth = _FakeFirebaseAuth()
            ..verifyResetError = FirebaseAuthException(code: code);
          final locations = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              home: AdminEmailActionScreen(
                key: ValueKey(code),
                uri: Uri.parse(
                  'https://mindmate-staging.web.app/reset-password?mode=resetPassword&oobCode=synthetic-$code',
                ),
                auth: auth,
                onReplaceLocation: locations.add,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text(message), findsOneWidget);
          expect(find.byType(TextFormField), findsNothing);
          expect(auth.confirmedResets, isEmpty);
          await tester.tap(find.text('Return to sign in'));
          await tester.pump();
          expect(locations, ['https://mindmate-staging.web.app/']);
        }
      },
    );

    testWidgets(
      'routes root and /verify-email without oobCode to auth gate',
      (tester) async {
        for (final route in ['/', '/verify-email']) {
          tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
          await tester.pumpWidget(
            MindMateAdminApp(
              key: ValueKey(route),
              authGateBuilder: (_) =>
                  const Scaffold(body: Text('Sign In Gate')),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Sign In Gate'), findsOneWidget);
          expect(find.byType(AdminEmailActionScreen), findsNothing);
        }
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
      },
    );
  });

  group('AdminEmailActionScreen verification and recovery flows', () {
    testWidgets(
      'verifies valid code and redirects back to validated portal origin without obsolete domain',
      (tester) async {
        final user = _FakeUser();
        final auth = _FakeFirebaseAuth(user: user);
        final replacedLocations = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: AdminEmailActionScreen(
              uri: Uri.parse(
                'https://paaccmindmate.com/verify-email?mode=verifyEmail&oobCode=synthetic-ok-code',
              ),
              auth: auth,
              onReplaceLocation: replacedLocations.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Email verified'), findsOneWidget);
        expect(
          find.textContaining('administrator review'),
          findsOneWidget,
        );
        expect(find.text('Continue to sign in'), findsOneWidget);

        await tester.tap(find.text('Continue to sign in'));
        await tester.pump();

        expect(replacedLocations, ['https://paaccmindmate.com/']);
      },
    );

    testWidgets('displays error for expired or invalid action codes', (
      tester,
    ) async {
      final scenarios = <({String code, String expectedMessage})>[
        (
          code: 'expired-action-code',
          expectedMessage:
              'This link has expired. Return to sign in and request a new one.',
        ),
        (
          code: 'invalid-action-code',
          expectedMessage:
              'This link is invalid or has already been used. Request a new one.',
        ),
      ];

      for (final scenario in scenarios) {
        final auth = _FakeFirebaseAuth(user: _FakeUser())
          ..applyError = FirebaseAuthException(code: scenario.code);
        final replacedLocations = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: AdminEmailActionScreen(
              key: ValueKey(scenario.code),
              uri: Uri.parse(
                'https://paaccmindmate.com/verify-email?mode=verifyEmail&oobCode=synthetic-bad-code',
              ),
              auth: auth,
              onReplaceLocation: replacedLocations.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Link unavailable'), findsOneWidget);
        expect(find.text(scenario.expectedMessage), findsOneWidget);
        expect(find.text('Return to sign in'), findsOneWidget);

        await tester.tap(find.text('Return to sign in'));
        await tester.pump();
        expect(replacedLocations, ['https://paaccmindmate.com/']);
      }
    });

    testWidgets(
      'shows already-verified state when code was consumed and user is verified',
      (tester) async {
        final auth = _FakeFirebaseAuth(user: _FakeUser(emailVerified: true))
          ..applyError = FirebaseAuthException(code: 'invalid-action-code');

        await tester.pumpWidget(
          MaterialApp(
            home: AdminEmailActionScreen(
              uri: Uri.parse(
                'https://paaccmindmate.com/verify-email?mode=verifyEmail&oobCode=synthetic-used-code',
              ),
              auth: auth,
              onReplaceLocation: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Email already verified'), findsOneWidget);
        expect(find.text('Continue to sign in'), findsOneWidget);
      },
    );

    testWidgets(
      'preserves password-reset and email-recovery action flows on /__/auth/action',
      (tester) async {
        final resetAuth = _FakeFirebaseAuth()..resetEmail = 'staff@example.edu';
        final resetLocations = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: AdminEmailActionScreen(
              uri: Uri.parse(
                'https://paaccmindmate.com/__/auth/action?mode=resetPassword&oobCode=synthetic-reset',
              ),
              auth: resetAuth,
              onReplaceLocation: resetLocations.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Choose a new password'), findsOneWidget);
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'StrongPass123');
        await tester.enterText(fields.at(1), 'StrongPass123');
        await tester.tap(find.text('Update password'));
        await tester.pumpAndSettle();

        expect(resetAuth.confirmedResets, [
          (code: 'synthetic-reset', newPassword: 'StrongPass123'),
        ]);
        expect(find.text('Password updated'), findsOneWidget);
        await tester.tap(find.text('Continue to sign in'));
        await tester.pump();
        expect(resetLocations, ['https://paaccmindmate.com/']);

        final recoverAuth = _FakeFirebaseAuth()
          ..checkEmail = 'staff@example.edu';
        final recoverLocations = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: AdminEmailActionScreen(
              key: const ValueKey('recoverEmail'),
              uri: Uri.parse(
                'https://paaccmindmate.com/__/auth/action?mode=recoverEmail&oobCode=synthetic-recover',
              ),
              auth: recoverAuth,
              onReplaceLocation: recoverLocations.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Restore your email'), findsOneWidget);
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        expect(recoverAuth.appliedCodes, ['synthetic-recover']);
        expect(find.text('Email restored'), findsOneWidget);
        await tester.tap(find.text('Continue to sign in'));
        await tester.pump();
        expect(recoverLocations, ['https://paaccmindmate.com/']);
      },
    );

    testWidgets(
      'expired reset code shows a request-again error without a password form',
      (tester) async {
        final auth = _FakeFirebaseAuth()
          ..verifyResetError = FirebaseAuthException(code: 'expired-action-code');
        await tester.pumpWidget(
          MaterialApp(
            home: AdminEmailActionScreen(
              uri: Uri.parse(
                'https://paaccmindmate.com/__/auth/action?mode=resetPassword&oobCode=synthetic-expired',
              ),
              auth: auth,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('expired'), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.textContaining('synthetic-expired'), findsNothing);
        expect(auth.confirmedResets, isEmpty);
      },
    );

    testWidgets(
      'a reused reset code is refused at submit and the password is not changed',
      (tester) async {
        final auth = _FakeFirebaseAuth()
          ..confirmResetError = FirebaseAuthException(code: 'invalid-action-code');
        await tester.pumpWidget(
          MaterialApp(
            home: AdminEmailActionScreen(
              uri: Uri.parse(
                'https://mindmate-staging.web.app/__/auth/action?mode=resetPassword&oobCode=synthetic-used',
              ),
              auth: auth,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'StrongPass123');
        await tester.enterText(fields.at(1), 'StrongPass123');
        await tester.tap(find.text('Update password'));
        await tester.pumpAndSettle();

        expect(find.textContaining('already been used'), findsOneWidget);
        expect(find.text('Password updated'), findsNothing);
        expect(auth.confirmedResets, isEmpty);
        expect(find.textContaining('synthetic-used'), findsNothing);
      },
    );

    testWidgets(
      'both Staging admin hosts complete a reset and return to their own sign-in',
      (tester) async {
        for (final host in ['paaccmindmate.com', 'mindmate-staging.web.app']) {
          final auth = _FakeFirebaseAuth();
          final locations = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              home: AdminEmailActionScreen(
                key: ValueKey(host),
                uri: Uri.parse(
                  'https://$host/__/auth/action?mode=resetPassword&oobCode=synthetic-$host'
                  '&continueUrl=https%3A%2F%2Fevil.example%2F',
                ),
                auth: auth,
                onReplaceLocation: locations.add,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final fields = find.byType(TextFormField);
          await tester.enterText(fields.at(0), 'StrongPass123');
          await tester.enterText(fields.at(1), 'StrongPass123');
          await tester.tap(find.text('Update password'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Continue to sign in'));
          await tester.pump();

          expect(auth.confirmedResets.single.code, 'synthetic-$host');
          // Same validated origin, no action-code params, continueUrl ignored.
          expect(locations, ['https://$host/'], reason: host);
        }
      },
    );
  });

  group('Origin and environment isolation', () {
    test('resolveReturnToSignInUrl strips action params and prevents cross-environment redirects', () {
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(
            'https://paaccmindmate.com/verify-email?mode=verifyEmail&oobCode=secret',
          ),
          environment: AppEnvironment.staging,
        ),
        'https://paaccmindmate.com/',
      );
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(
            'http://localhost:8080/verify-email?mode=verifyEmail&oobCode=secret',
          ),
          environment: AppEnvironment.staging,
        ),
        'http://localhost:8080/',
      );
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(
            'https://mindmate-admin-staging.vercel.app/verify-email?mode=verifyEmail&oobCode=secret',
          ),
          environment: AppEnvironment.staging,
        ),
        '/',
      );
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(
            'https://mind-mates-cd2cf.web.app/verify-email?mode=verifyEmail&oobCode=secret',
          ),
          environment: AppEnvironment.staging,
        ),
        '/',
      );
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(
            'https://paaccmindmate.com/verify-email?mode=verifyEmail&oobCode=secret',
          ),
          environment: AppEnvironment.production,
        ),
        '/',
      );
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(
            'http://paaccmindmate.com/verify-email?mode=verifyEmail&oobCode=secret',
          ),
          environment: AppEnvironment.staging,
        ),
        '/',
      );
      // The staging Firebase Hosting fallback used by recovery emails.
      const resetOnStagingHosting =
          'https://mindmate-staging.web.app/reset-password?mode=resetPassword&oobCode=secret';
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(resetOnStagingHosting),
          environment: AppEnvironment.staging,
        ),
        'https://mindmate-staging.web.app/',
      );
      expect(
        AdminEmailActionScreen.resolveReturnToSignInUrl(
          Uri.parse(resetOnStagingHosting),
          environment: AppEnvironment.production,
        ),
        '/',
      );
    });

    test('AppEnvironmentConfig isolates staging and production Firebase project IDs', () {
      expect(
        () => AppEnvironmentConfig.validateFirebaseIdentity(
          projectId: MindMatesFirebaseOptions.currentPlatform.projectId,
          callableRegion: AppEnvironmentConfig.functionsRegion,
          releaseBuild: false,
        ),
        returnsNormally,
      );
      expect(
        () => AppEnvironmentConfig.validateFirebaseIdentity(
          projectId: AppEnvironmentConfig.current == AppEnvironment.production
              ? 'mindmate-staging'
              : 'mind-mates-cd2cf',
          callableRegion: AppEnvironmentConfig.functionsRegion,
          releaseBuild: false,
        ),
        throwsStateError,
      );
    });

    test('staff approval remains gated behind administrator review after verification', () {
      const awaitingEmail = PortalAccessEvaluation(
        state: PortalAccessState.emailVerificationRequired,
        email: 'staff@example.edu',
        requestedRole: AccessRole.portalStaff,
        reference: 'REQ-12345678',
      );
      const awaitingAdmin = PortalAccessEvaluation(
        state: PortalAccessState.pendingAdminApproval,
        email: 'staff@example.edu',
        requestedRole: AccessRole.portalStaff,
        reference: 'REQ-12345678',
      );
      const approved = PortalAccessEvaluation(
        state: PortalAccessState.granted,
        email: 'staff@example.edu',
      );

      expect(awaitingEmail.isGranted, isFalse);
      expect(awaitingAdmin.isGranted, isFalse);
      expect(approved.isGranted, isTrue);
      expect(AccessRole.appUser.canUsePortal, isFalse);
    });
  });
}
