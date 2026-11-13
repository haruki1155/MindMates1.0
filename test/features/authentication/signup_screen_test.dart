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
  testWidgets('signup opens directly on the form without a rules modal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Email Address'), findsWidgets);
    expect(_guideText('Email guide'), findsOneWidget);
    expect(_guideText('Use your @ucu.edu.ph employee email.'), findsOneWidget);
    expect(find.text('Student account'), findsNothing);
    expect(find.text('Student ID'), findsNothing);
    expect(find.text('Employee ID'), findsWidgets);
    expect(find.text('Course or Program'), findsNothing);
    expect(find.text('Year Level'), findsNothing);
  });

  testWidgets('email guide follows the typed email', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
    await _settleSignup(tester);

    const studentPointer =
        "Students activate accounts through the roster. Tap 'Activate student account'.";
    const cases = [
      ('leo@gmail.com', studentPointer),
      ('  Juan@UCU.edu.ph ', 'Institutional email detected.'),
      ('juan@ucu.edu.ph.com', studentPointer),
      ('juan@student.ucu.edu.ph', studentPointer),
      ('', 'Use your @ucu.edu.ph employee email.'),
    ];
    for (final (input, expected) in cases) {
      await tester.enterText(find.byType(TextFormField).first, input);
      await tester.pump();
      expect(_guideText('Email guide'), findsOneWidget, reason: input);
      expect(_guideText(expected), findsOneWidget, reason: input);
    }
    expect(find.text('Student account'), findsNothing);
    expect(find.text('Teaching personnel account detected'), findsNothing);
  });

  testWidgets('department selection has no course picker', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
    await _settleSignup(tester);

    expect(find.text('College or Department'), findsWidgets);
    expect(find.text('Course or Program'), findsNothing);

    await _selectDropdownItem(
      tester,
      fieldLabel: 'College or Department',
      itemLabel: 'College of Nursing',
    );
    expect(find.text('College of Nursing'), findsOneWidget);
  });

  testWidgets('signup requires department', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _settleSignup(tester);

    await _fillRequiredTextFields(tester);
    await _acceptTerms(tester);

    await tester.tap(find.text('Sign Up'));
    await tester.pump();

    expect(find.text('College or department is required'), findsOneWidget);
    expect(authProvider.signupCalls, 0);
  });

  testWidgets('non-ucu email shows an error and does not submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _settleSignup(tester);

    await _fillRequiredTextFields(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'student@gmail.com',
    );
    await _selectDropdownItem(
      tester,
      fieldLabel: 'College or Department',
      itemLabel: 'College of Nursing',
    );
    await _acceptTerms(tester);

    await tester.tap(find.text('Sign Up'));
    await tester.pump();

    expect(
      find.text('Use your @ucu.edu.ph employee email address'),
      findsOneWidget,
    );
    expect(authProvider.signupCalls, 0);
  });

  testWidgets('signup passes selected department for employees', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _settleSignup(tester);

    await _fillRequiredTextFields(tester);
    await _selectDropdownItem(
      tester,
      fieldLabel: 'College or Department',
      itemLabel:
          'College of Information and Technology Education / College of Computer Studies',
    );
    await _acceptTerms(tester);

    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & Continue'));
    await tester.pumpAndSettle();

    expect(authProvider.signupCalls, 1);
    expect(
      authProvider.department,
      'College of Information and Technology Education / College of Computer Studies',
    );
    expect(authProvider.course, '');
    expect(authProvider.role, AssessmentRole.faculty);
    expect(authProvider.employeeId, '2026-1');
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
    await _settleSignup(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'juandelacruz@ucu.edu.ph',
    );
    await tester.pump();

    expect(find.text('College or Department'), findsWidgets);
    expect(find.text('Employee ID'), findsWidgets);
    expect(_guideText('Institutional email detected.'), findsOneWidget);
    expect(find.text('Course or Program'), findsNothing);
    expect(find.text('Year Level'), findsNothing);
    expect(find.text('Position or Designation'), findsWidgets);
    expect(find.text('Sector'), findsNothing);
  });

  testWidgets('student email on sign up points to student activation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_SignupHarness(authProvider: _FakeAuthProvider()));
    await _settleSignup(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'leo@gmail.com',
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Activate student account'));
    await tester.tap(find.text('Activate student account'));
    await tester.pumpAndSettle();
    expect(find.text('activation target'), findsOneWidget);
  });

  testWidgets(
    'official UCU registration submits teaching role and employee ID',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final authProvider = _FakeAuthProvider();
      await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
      await _settleSignup(tester);

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
      await tester.tap(find.text('Confirm & Continue'));
      await tester.pumpAndSettle();

      expect(authProvider.signupCalls, 1);
      expect(authProvider.role, AssessmentRole.faculty);
      expect(authProvider.employeeId, 'EMP-1001');
      expect(authProvider.position, 'Instructor');
      expect(authProvider.gender, 'Male');
    },
  );

  testWidgets('sign up has no student option or student-only fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _SignupHarness(
        authProvider: _FakeAuthProvider(),
        role: AssessmentRole.staff,
      ),
    );
    await _settleSignup(tester);

    expect(find.text('Course or Program'), findsNothing);
    expect(find.text('Year Level'), findsNothing);
    expect(find.text('Student ID'), findsNothing);
    expect(find.textContaining('Student account'), findsNothing);
  });

  testWidgets('a Google profile setup can always get back to sign in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A personal Google account: the email field is read-only and its address
    // can never pass the @ucu.edu.ph validator, so without this exit the
    // screen is a dead end.
    final authProvider = _FakeAuthProvider(googleEmail: 'leo@gmail.com');
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _settleSignup(tester);

    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Email Address'),
          )
          .controller
          ?.text,
      'leo@gmail.com',
    );

    final back = find.text('Back to sign in');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(authProvider.signOutCalls, 1);
    expect(find.text('login target'), findsOneWidget);
  });

  testWidgets('student activation from a Google profile setup keeps login reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(googleEmail: 'leo@gmail.com');
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _settleSignup(tester);

    await tester.ensureVisible(find.text('Activate student account'));
    await tester.tap(find.text('Activate student account'));
    await tester.pumpAndSettle();

    expect(authProvider.signOutCalls, 1);
    expect(find.text('activation target'), findsOneWidget);

    // Popping activation must land on sign in, not on the orphaned signup form.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('login target'), findsOneWidget);
  });

  testWidgets('the password signup path also offers a way back to sign in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider();
    await tester.pumpWidget(_SignupHarness(authProvider: authProvider));
    await _settleSignup(tester);

    final back = find.text('Back to sign in');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();

    // Nothing to sign out of on the password path.
    expect(authProvider.signOutCalls, 0);
    expect(find.text('login target'), findsOneWidget);
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
    'leo@ucu.edu.ph',
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
    find.widgetWithText(TextFormField, 'Employee ID'),
    '2026-1',
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

Finder _guideText(String text) => find.descendant(
  of: find.byKey(const Key('signup-email-guide')),
  matching: find.text(text),
);

Future<void> _settleSignup(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.text('Before you create an account'), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
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
          RouteNames.studentActivation: (_) =>
              const Scaffold(body: Center(child: Text('activation target'))),
          RouteNames.onboarding: (_) =>
              const Scaffold(body: Center(child: Text('onboarding target'))),
          RouteNames.login: (_) =>
              const Scaffold(body: Center(child: Text('login target'))),
        },
      ),
    );
  }
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({this.googleEmail}) : super(_FakeAuthRepository());

  final String? googleEmail;
  int signOutCalls = 0;
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
  String? get currentUserEmail => googleEmail;

  @override
  String? get currentUserDisplayName => null;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }

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
