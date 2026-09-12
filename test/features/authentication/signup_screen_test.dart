import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/signup_screen.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('department selection enables related courses', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
    await _dismissInstructions(tester);

    expect(find.textContaining('Unofficial'), findsNothing);
    expect(find.text('College or Department'), findsWidgets);
    expect(find.text('Course or Program'), findsWidgets);
    expect(find.text('Select college first'), findsOneWidget);

    await _selectDropdownItem(
      tester,
      fieldLabel: 'College or Department',
      itemLabel: 'College of Nursing',
    );

    await _selectDropdownItem(
      tester,
      fieldLabel: 'Course or Program',
      itemLabel: 'BS Nursing',
    );

    expect(find.text('College of Nursing'), findsOneWidget);
    expect(find.text('BS Nursing'), findsOneWidget);
  });

  testWidgets('changing department clears the previous course', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
    await _dismissInstructions(tester);

    await _selectDropdownItem(
      tester,
      fieldLabel: 'College or Department',
      itemLabel: 'College of Nursing',
    );
    await _selectDropdownItem(
      tester,
      fieldLabel: 'Course or Program',
      itemLabel: 'BS Nursing',
    );

    await _selectDropdownItem(
      tester,
      fieldLabel: 'College or Department',
      itemLabel: 'College of Pharmacy',
    );

    expect(find.text('College of Pharmacy'), findsOneWidget);
    expect(find.text('BS Nursing'), findsNothing);

    await _selectDropdownItem(
      tester,
      fieldLabel: 'Course or Program',
      itemLabel: 'BS Pharmacy',
    );
    expect(find.text('BS Pharmacy'), findsOneWidget);
  });

  testWidgets('signup requires department and course', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _dismissInstructions(tester);

    await _fillRequiredTextFields(tester);
    await _acceptTerms(tester);

    await tester.tap(find.text('Sign Up'));
    await tester.pump();

    expect(find.text('College or department is required'), findsOneWidget);
    expect(find.text('Course or program is required'), findsOneWidget);
    expect(authProvider.signupCalls, 0);
  });

  testWidgets('signup passes selected department and course', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _dismissInstructions(tester);

    await _fillRequiredTextFields(tester);
    await _selectDropdownItem(
      tester,
      fieldLabel: 'College or Department',
      itemLabel:
          'College of Information and Technology Education / College of Computer Studies',
    );
    await _selectDropdownItem(
      tester,
      fieldLabel: 'Course or Program',
      itemLabel: 'BS Information Technology',
    );
    await _acceptTerms(tester);

    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(authProvider.signupCalls, 1);
    expect(
      authProvider.department,
      'College of Information and Technology Education / College of Computer Studies',
    );
    expect(authProvider.course, 'BS Information Technology');
    expect(authProvider.generatedEmail, '2026.1@mindmate.local');
    expect(find.text('onboarding target'), findsOneWidget);
  });

  testWidgets('official UCU email automatically switches to teaching fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(
      _SignupHarness(authProvider: authProvider, role: AssessmentRole.faculty),
    );
    await _dismissInstructions(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'juandelacruz@ucu.edu.ph',
    );
    await tester.pump();

    expect(find.text('College or Department'), findsWidgets);
    expect(find.text('Employee ID'), findsWidgets);
    expect(find.text('Teaching personnel account detected'), findsOneWidget);
    expect(find.text('Course or Program'), findsNothing);
    expect(find.text('Year Level'), findsNothing);
    expect(find.text('Position or Designation'), findsWidgets);
    expect(find.text('Sector'), findsNothing);
  });

  testWidgets(
    'official UCU registration submits teaching role and employee ID',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final authProvider = _FakeAuthProvider();
      await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
      await _dismissInstructions(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address'),
        'juandelacruz@ucu.edu.ph',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'First Name'),
        'Juan',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Last Name'),
        'Dela Cruz',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Employee ID'),
        'EMP-1001',
      );
      await tester.tap(find.text('Select date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _selectDropdownItem(
        tester,
        fieldLabel: 'College or Department',
        itemLabel: 'College of Nursing',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Position or Designation'),
        'Instructor',
      );
      await _selectDropdownItem(
        tester,
        fieldLabel: 'Sex / Gender',
        itemLabel: 'Male',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'password123',
      );
      await _acceptTerms(tester);
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(authProvider.signupCalls, 1);
      expect(authProvider.role, AssessmentRole.faculty);
      expect(authProvider.employeeId, 'EMP-1001');
      expect(authProvider.position, 'Instructor');
      expect(authProvider.gender, 'Male');
    },
  );

  testWidgets('non-teaching selection still shows universal student form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(
      _SignupHarness(authProvider: authProvider, role: AssessmentRole.staff),
    );
    await _dismissInstructions(tester);

    expect(find.text('Sector'), findsNothing);
    expect(find.text('College or Department'), findsWidgets);
    expect(find.text('Course or Program'), findsWidgets);
    expect(find.text('Year Level'), findsWidgets);
  });
}

Future<void> _fillRequiredTextFields(WidgetTester tester) async {
  await tester.tap(find.text('Select date'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('15').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email Address'),
    'student@gmail.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'First Name'),
    'Leo',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Last Name'),
    'Molar',
  );
  await tester.enterText(
    find.widgetWithText(
      TextFormField,
      find.text('Student ID').evaluate().isNotEmpty
          ? 'Student ID'
          : 'Employee ID',
    ),
    '2026-1',
  );
  await _selectDropdownItem(
    tester,
    fieldLabel: 'Year Level',
    itemLabel: '2nd Year',
  );
  await _selectDropdownItem(
    tester,
    fieldLabel: 'Sex / Gender',
    itemLabel: 'Prefer not to say',
  );
  final position = find.widgetWithText(
    TextFormField,
    'Position or Designation',
  );
  if (position.evaluate().isNotEmpty) {
    await tester.enterText(position, 'Coordinator');
  }
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'password123',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Confirm Password'),
    'password123',
  );
  await tester.pump();
}

Future<void> _dismissInstructions(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.text('Before you create an account'), findsOneWidget);
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<void> _acceptTerms(WidgetTester tester) async {
  final termsControl = find.byKey(const Key('registration-terms-control'));
  await tester.ensureVisible(termsControl);
  await tester.tap(termsControl);
  await tester.pumpAndSettle();

  final agreeButton = find.byKey(const Key('terms-agree'));
  expect(tester.widget<FilledButton>(agreeButton).onPressed, isNull);
  await tester.drag(
    find.byKey(const Key('terms-scroll-view')),
    const Offset(0, -2000),
  );
  await tester.pumpAndSettle();
  expect(tester.widget<FilledButton>(agreeButton).onPressed, isNotNull);
  await tester.tap(agreeButton);
  await tester.pumpAndSettle();

  expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
}

Future<void> _selectDropdownItem(
  WidgetTester tester, {
  required String fieldLabel,
  required String itemLabel,
}) async {
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.hintText == fieldLabel,
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();

  final item = find.text(itemLabel).last;
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

class _SignupHarness extends StatelessWidget {
  const _SignupHarness({
    required this.authProvider,
    this.role = AssessmentRole.student,
  });

  final AuthProvider authProvider;
  final AssessmentRole role;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(_FakeUserRepository()),
        ),
        ChangeNotifierProvider<AssessmentProvider>(
          create: (_) =>
              AssessmentProvider(_FakeAssessmentRepository())..selectRole(role),
        ),
      ],
      child: MaterialApp(
        home: const SignupScreen(),
        routes: {
          RouteNames.onboarding: (_) =>
              const Scaffold(body: Center(child: Text('onboarding target'))),
        },
      ),
    );
  }
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());

  int signupCalls = 0;
  String? department;
  String? course;
  String? sector;
  String? employeeId;
  String? yearLevel;
  String? position;
  String? schoolId;
  String? generatedEmail;
  AssessmentRole? role;
  String? gender;

  @override
  String? get currentUserEmail => null;

  @override
  String? get currentUserDisplayName => null;

  @override
  Future<String?> signUp({
    required String password,
    required String firstName,
    required String lastName,
    required String schoolId,
    required String department,
    required String course,
    String? sector,
    String? employeeId,
    String? yearLevel,
    String? position,
    String? middleName,
    AssessmentRole? role,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    signupCalls += 1;
    this.department = department;
    this.course = course;
    this.sector = sector;
    this.employeeId = employeeId;
    this.yearLevel = yearLevel;
    this.position = position;
    this.schoolId = schoolId;
    generatedEmail = AuthRepository.authEmailForSchoolId(schoolId);
    this.role = role;
    this.gender = gender;
    return 'user_1';
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());
}

class _FakeUserRepository extends UserRepository {
  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    return UserModel(id: uid, email: 'leo@example.com');
  }
}

class _FakeAssessmentRepository extends AssessmentRepository {}
