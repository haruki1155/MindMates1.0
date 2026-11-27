import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_change_password_screen.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/appointment_queue_item.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _FakePasswordChangeRepo extends AdminPortalRepository {
  _FakePasswordChangeRepo({this.recentPasswordAvailable = false});

  bool recentPasswordAvailable;
  int signOutCalls = 0;
  final List<({String password, String? currentPassword})> submittedCalls = [];
  Future<void> Function(String password, String? currentPassword)? onComplete;

  @override
  bool get hasRecentSignInPassword => recentPasswordAvailable;

  @override
  AccessRole get currentAccessRole => AccessRole.portalStaff;

  @override
  bool get isSuperAdmin => false;

  @override
  User? get currentAuthUser => null;

  final _notifications =
      StreamController<List<AppNotificationModel>>.broadcast();

  @override
  Stream<List<AppNotificationModel>> watchPortalNotifications() =>
      _notifications.stream;

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
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() =>
      Stream<List<AppointmentQueueItem>>.value(const []);

  @override
  Stream<PaccAvailabilityModel> watchPaccAvailability() =>
      Stream<PaccAvailabilityModel>.value(
        const PaccAvailabilityModel(
          openDays: [1, 2, 3, 4, 5],
          opensAt: '08:00',
          closesAt: '17:00',
          presence: CounselorPresence.inOffice,
          acceptsWalkIns: true,
        ),
      );

  @override
  Future<void> completeMandatoryPasswordChange(
    String password, {
    String? currentPassword,
  }) async {
    submittedCalls.add((password: password, currentPassword: currentPassword));
    if (onComplete != null) {
      await onComplete!(password, currentPassword);
    }
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    recentPasswordAvailable = false;
  }
}

Future<void> _pumpChangePasswordScreen(
  WidgetTester tester,
  _FakePasswordChangeRepo repo,
) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminChangePasswordScreen(repository: repo)),
  );
  await tester.pump();
}

void main() {
  group('AdminChangePasswordScreen', () {
    testWidgets(
      'fresh-login mode hides current password field and submits without it',
      (tester) async {
        final repo = _FakePasswordChangeRepo(recentPasswordAvailable: true);
        await _pumpChangePasswordScreen(tester, repo);

        expect(
          find.byKey(const Key('current-password-field')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const Key('new-password-field')),
          'StrongPass!234',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-field')),
          'StrongPass!234',
        );
        await tester.tap(find.byKey(const Key('submit-change-password')));
        await tester.pumpAndSettle();

        expect(repo.submittedCalls, [
          (password: 'StrongPass!234', currentPassword: null),
        ]);
        expect(find.byType(AdminPortalHome), findsOneWidget);
      },
    );

    testWidgets(
      'restored-session mode shows current password field, validates inputs, and submits current password',
      (tester) async {
        final repo = _FakePasswordChangeRepo(recentPasswordAvailable: false);
        await _pumpChangePasswordScreen(tester, repo);

        expect(
          find.byKey(const Key('current-password-field')),
          findsOneWidget,
        );

        // Empty current password rejected.
        await tester.enterText(
          find.byKey(const Key('new-password-field')),
          'StrongPass!234',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-field')),
          'StrongPass!234',
        );
        await tester.tap(find.byKey(const Key('submit-change-password')));
        await tester.pump();

        expect(
          find.text('Enter your current temporary password.'),
          findsOneWidget,
        );
        expect(repo.submittedCalls, isEmpty);

        // Reusing temporary password as new password rejected.
        await tester.enterText(
          find.byKey(const Key('current-password-field')),
          'StrongPass!234',
        );
        await tester.tap(find.byKey(const Key('submit-change-password')));
        await tester.pump();

        expect(
          find.text(
            'Choose a new password different from your temporary password.',
          ),
          findsOneWidget,
        );
        expect(repo.submittedCalls, isEmpty);

        // Valid current + distinct new password succeeds.
        await tester.enterText(
          find.byKey(const Key('current-password-field')),
          'TempPass#9999',
        );
        await tester.tap(find.byKey(const Key('submit-change-password')));
        await tester.pumpAndSettle();

        expect(repo.submittedCalls, [
          (password: 'StrongPass!234', currentPassword: 'TempPass#9999'),
        ]);
        expect(find.byType(AdminPortalHome), findsOneWidget);
      },
    );

    testWidgets(
      'requires-recent-login reveals current password field and shows friendly inline error without raw code',
      (tester) async {
        final repo = _FakePasswordChangeRepo(recentPasswordAvailable: true)
          ..onComplete = (_, _) async {
            throw FirebaseAuthException(
              code: 'requires-recent-login',
              message:
                  'This operation is sensitive and requires recent authentication.',
            );
          };
        await _pumpChangePasswordScreen(tester, repo);

        expect(
          find.byKey(const Key('current-password-field')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const Key('new-password-field')),
          'StrongPass!234',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-field')),
          'StrongPass!234',
        );
        await tester.tap(find.byKey(const Key('submit-change-password')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('current-password-field')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('change-password-error')), findsOneWidget);
        expect(
          find.text(
            'Your sign-in session needs quick confirmation. Enter your temporary password above and try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('firebase_auth/'), findsNothing);
      },
    );

    testWidgets(
      'wrong-password / invalid-credential shows friendly inline error',
      (tester) async {
        final repo = _FakePasswordChangeRepo(recentPasswordAvailable: false)
          ..onComplete = (_, _) async {
            throw FirebaseAuthException(code: 'wrong-password');
          };
        await _pumpChangePasswordScreen(tester, repo);

        await tester.enterText(
          find.byKey(const Key('current-password-field')),
          'WrongTemp#1234',
        );
        await tester.enterText(
          find.byKey(const Key('new-password-field')),
          'StrongPass!234',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-field')),
          'StrongPass!234',
        );
        await tester.tap(find.byKey(const Key('submit-change-password')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('change-password-error')), findsOneWidget);
        expect(
          find.text(
            'The temporary password is incorrect. Check your email or sign out and sign in again.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'sign-out button signs out and navigates back to AdminLoginScreen',
      (tester) async {
        final repo = _FakePasswordChangeRepo(recentPasswordAvailable: false);
        await _pumpChangePasswordScreen(tester, repo);

        await tester.tap(find.byKey(const Key('change-password-sign-out')));
        await tester.pumpAndSettle();

        expect(repo.signOutCalls, 1);
        expect(find.byType(AdminLoginScreen), findsOneWidget);
      },
    );
  });

  group('AdminPortalRepository.completeMandatoryPasswordChangeWith', () {
    test(
      'reauthenticates, retries updatePassword, and refreshes ID token before server completion when requires-recent-login is thrown',
      () async {
        final events = <String>[];
        var attempts = 0;
        final repo = AdminPortalRepository(
          callableInvoker: (name, data) async {
            events.add('callable:$name');
            return {'ok': true};
          },
        );

        await repo.completeMandatoryPasswordChangeWith(
          newPassword: 'StrongPass!234',
          currentPassword: 'TempPass#9999',
          userEmail: 'staff@example.com',
          updatePassword: (password) async {
            events.add('updatePassword:$password');
            attempts += 1;
          },
          reauthenticate: (email, password) async {
            events.add('reauthenticate:$email:$password');
          },
          refreshIdToken: () async {
            events.add('refreshIdToken');
          },
        );

        expect(attempts, 1);
        expect(events, [
          'reauthenticate:staff@example.com:TempPass#9999',
          'updatePassword:StrongPass!234',
          'refreshIdToken',
          'callable:completeAdminPasswordChange',
          'refreshIdToken',
        ]);
        expect(repo.mustChangePassword, isFalse);
        expect(repo.hasRecentSignInPassword, isFalse);

        // Also test the fallback retry path when updatePassword initially throws
        // requires-recent-login without explicit currentPassword first failing,
        // or rethrows when no currentPassword fallback exists.
        final retryEvents = <String>[];
        var retryAttempts = 0;
        await expectLater(
          () => repo.completeMandatoryPasswordChangeWith(
            newPassword: 'StrongPass!234',
            userEmail: 'staff@example.com',
            updatePassword: (password) async {
              retryEvents.add('updatePassword');
              retryAttempts += 1;
              if (retryAttempts == 1) {
                throw FirebaseAuthException(code: 'requires-recent-login');
              }
            },
            reauthenticate: (_, _) async {
              retryEvents.add('reauthenticate');
            },
            refreshIdToken: () async {
              retryEvents.add('refreshIdToken');
            },
          ),
          throwsA(
            isA<FirebaseAuthException>().having(
              (e) => e.code,
              'code',
              'requires-recent-login',
            ),
          ),
        );
        expect(retryEvents, ['updatePassword']);
      },
    );

    test(
      'retries updatePassword after requires-recent-login when cached recent sign-in password exists',
      () async {
        final events = <String>[];
        var attempts = 0;
        final repo = AdminPortalRepository(
          callableInvoker: (name, data) async {
            events.add('callable:$name');
            return {'ok': true};
          },
        )..seedRecentSignInPasswordForTest('TempPass#9999');

        expect(repo.hasRecentSignInPassword, isTrue);

        await repo.completeMandatoryPasswordChangeWith(
          newPassword: 'NewPassword!12',
          userEmail: 'staff@example.com',
          updatePassword: (password) async {
            attempts += 1;
            events.add('updatePassword:$attempts:$password');
            if (attempts == 1) {
              throw FirebaseAuthException(code: 'requires-recent-login');
            }
          },
          reauthenticate: (email, password) async {
            events.add('reauthenticate:$email:$password');
          },
          refreshIdToken: () async {
            events.add('refreshIdToken');
          },
        );

        expect(attempts, 2);
        expect(events, [
          'updatePassword:1:NewPassword!12',
          'reauthenticate:staff@example.com:TempPass#9999',
          'updatePassword:2:NewPassword!12',
          'refreshIdToken',
          'callable:completeAdminPasswordChange',
          'refreshIdToken',
        ]);
        expect(repo.hasRecentSignInPassword, isFalse);
      },
    );
  });
}
