import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/screens/create_staff_account_page.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _ProvisionRepo extends AdminPortalRepository {
  _ProvisionRepo({this.superAdmin = true, this.error});

  final bool superAdmin;
  final Object? error;
  final calls = <Map<String, Object?>>[];

  @override
  bool get isSuperAdmin => superAdmin;

  @override
  Future<CreatedStaffAccount> createStaffAccountByAdmin({
    required String email,
    required AccessRole role,
    String firstName = '',
    String lastName = '',
  }) async {
    calls.add({
      'email': email,
      'role': role.storedValue,
      'firstName': firstName,
      'lastName': lastName,
    });
    if (error != null) throw error!;
    return CreatedStaffAccount(
      uid: 'staff-123',
      email: email.trim().toLowerCase(),
      role: role,
      roleLabel: role == AccessRole.counselor ? 'Counselor' : 'Portal Staff',
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _ProvisionRepo repo, {
  VoidCallback? onOpenUsers,
}) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: Scaffold(
        body: CreateStaffAccountPage(
          repository: repo,
          onOpenUserManagement: onOpenUsers,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('blocks non-super-admin access', (tester) async {
    await _pump(tester, _ProvisionRepo(superAdmin: false));
    expect(find.text('Super-administrator access is required.'), findsOneWidget);
    expect(find.byKey(const Key('submit-create-account')), findsNothing);
  });

  testWidgets('validates email format before calling repository', (tester) async {
    final repo = _ProvisionRepo();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('submit-create-account')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the email address for this account.'), findsOneWidget);
    expect(repo.calls, isEmpty);

    await tester.enterText(
      find.byKey(const Key('create-account-email')),
      'not-valid-email',
    );
    await tester.tap(find.byKey(const Key('submit-create-account')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets(
    'creates Counselor or Portal Staff account, shows email confirmation dialog, and resets or navigates',
    (tester) async {
      final repo = _ProvisionRepo();
      var openedUsers = 0;
      await _pump(tester, repo, onOpenUsers: () => openedUsers++);

      await tester.tap(find.byKey(const Key('role-card-staff')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('create-account-email')),
        'staff.user@school.edu',
      );
      await tester.tap(find.byKey(const Key('submit-create-account')));
      await tester.pumpAndSettle();

      expect(repo.calls, [
        {
          'email': 'staff.user@school.edu',
          'role': 'portalStaff',
          'firstName': '',
          'lastName': '',
        },
      ]);
      expect(find.text('Account Created'), findsOneWidget);
      expect(
        find.textContaining('An email has been sent to staff.user@school.edu'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Password change required upon login'),
        findsOneWidget,
      );

      await tester.tap(find.text('Create Another Account'));
      await tester.pumpAndSettle();
      expect(find.text('Account Created'), findsNothing);
      final field = tester.widget<TextFormField>(
        find.byKey(const Key('create-account-email')),
      );
      expect(field.controller?.text, isEmpty);

      await tester.tap(find.byKey(const Key('role-card-counselor')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('create-account-email')),
        'counselor@school.edu',
      );
      await tester.tap(find.byKey(const Key('submit-create-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View User Management'));
      await tester.pumpAndSettle();
      expect(openedUsers, 1);
    },
  );

  testWidgets('surfaces inline error without clearing email on failure', (
    tester,
  ) async {
    final repo = _ProvisionRepo(
      error: FirebaseFunctionsException(
        code: 'already-exists',
        message: 'An account with this email address already exists.',
      ),
    );
    await _pump(tester, repo);

    await tester.enterText(
      find.byKey(const Key('create-account-email')),
      'dup@school.edu',
    );
    await tester.tap(find.byKey(const Key('submit-create-account')));
    await tester.pumpAndSettle();

    expect(
      find.text('An account with this email address already exists.'),
      findsOneWidget,
    );
    expect(find.text('dup@school.edu'), findsOneWidget);
    expect(find.text('Account Created'), findsNothing);
  });

  testWidgets('AdminLoginScreen hides self-service Request PACC Portal Access button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AdminTheme.data, home: const AdminLoginScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Request PACC Portal Access'), findsNothing);
    expect(
      find.textContaining('Contact your PACC Administrator'),
      findsOneWidget,
    );
  });
}
