import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/forgot_password_screen.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('password recovery requires and submits a School ID', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _RecoveryAuthProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: const MaterialApp(home: ForgotPasswordScreen()),
      ),
    );

    expect(find.text('School ID'), findsOneWidget);
    expect(find.text('Email'), findsNothing);

    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(find.text('School ID is required.'), findsOneWidget);
    expect(provider.calls, 0);

    await tester.enterText(find.byType(TextFormField), ' 20260001 ');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(provider.calls, 1);
    expect(provider.schoolId, ' 20260001 ');
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('School ID 20260001'), findsOneWidget);
  });
}

class _RecoveryAuthProvider extends AuthProvider {
  _RecoveryAuthProvider() : super(AuthRepository(AuthService()));

  int calls = 0;
  String? schoolId;

  @override
  Future<bool> sendPasswordResetForSchoolId(String schoolId) async {
    calls += 1;
    this.schoolId = schoolId;
    return true;
  }
}
