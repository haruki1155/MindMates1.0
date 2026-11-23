import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/forgot_password_screen.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('the School ID path is explicit and keeps its existing behaviour', (
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

    expect(find.text('Student ID'), findsOneWidget);
    await tester.tap(find.byKey(const Key('forgot-path-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('School ID'), findsOneWidget);
    expect(find.text('Student ID'), findsNothing);
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
    expect(provider.studentIdCalls, 0);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('School ID 20260001'), findsOneWidget);
  });

  testWidgets('a student resets with the Student ID and gets a non-committal answer', (
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

    expect(find.text('Student ID'), findsOneWidget);
    expect(find.textContaining('verified recovery email'), findsWidgets);
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(find.text('Student ID is required.'), findsOneWidget);
    expect(provider.studentIdCalls, 0);

    await tester.enterText(find.byType(TextFormField), ' 2020-12345 ');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(provider.studentIdCalls, 1);
    expect(provider.studentId, ' 2020-12345 ');
    expect(provider.calls, 0, reason: 'the legacy School ID flow is not used');
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('If that Student ID has a verified recovery email'), findsOneWidget);
    expect(find.textContaining('was sent'), findsNothing);
    expect(find.textContaining('mindmate.local'), findsNothing);
  });

  testWidgets('a Student ID reset failure shows the error and not the success card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _RecoveryAuthProvider()..studentIdResult = false;
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: const MaterialApp(home: ForgotPasswordScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '2020-12345');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsNothing);
    expect(find.text('Too many requests. Please wait 15 minutes and try again.'), findsOneWidget);
  });
}

class _RecoveryAuthProvider extends AuthProvider {
  _RecoveryAuthProvider() : super(AuthRepository(AuthService()));

  int calls = 0;
  int studentIdCalls = 0;
  String? schoolId;
  String? studentId;
  bool studentIdResult = true;
  String? _error;

  @override
  String? get errorMessage => _error;

  @override
  Future<bool> sendPasswordResetForStudentId(String studentId) async {
    studentIdCalls += 1;
    this.studentId = studentId;
    if (!studentIdResult) {
      _error = 'Too many requests. Please wait 15 minutes and try again.';
    }
    return studentIdResult;
  }

  @override
  Future<bool> sendPasswordResetForSchoolId(String schoolId) async {
    calls += 1;
    this.schoolId = schoolId;
    return true;
  }
}
