import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_info/screens/student_information_screen.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';
import 'package:mind_mates/repositories/student_roster_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:provider/provider.dart';

const _consent =
    'I agree to the collection and processing of my personal information '
    'under the Data Privacy Act of 2012 (RA 10173).';

Map<String, Object?> _infoResponse({
  bool withPersonal = false,
  List<Map<String, Object?>> corrections = const [],
}) => {
  'official': {
    'studentNo': '2021-00123',
    'surname': 'Dela Cruz',
    'firstName': 'Leo',
    'middleName': 'M',
    'dateOfBirth': '2005-02-03',
    'college': 'College of Computing',
    'course': 'BSIT',
    'yearLevel': '2nd Year',
    'email': 'leo@example.com',
  },
  'personal': withPersonal
      ? {
          'sex': 'Male',
          'civilStatus': 'Single',
          'spouse': '',
          'nationality': 'Filipino',
          'placeOfBirth': 'Alaminos',
          'cityAddress': null,
          'homeAddress': {
            'number': '1',
            'street': 'Main',
            'barangay': 'Poblacion',
            'cityTown': 'Alaminos',
            'province': 'Pangasinan',
            'zipCode': '2404',
          },
          'father': '',
          'fatherOccupation': '',
          'mother': '',
          'motherOccupation': '',
          'guardian': 'Ana',
          'guardianRelationship': 'Mother',
          'guardianAddress': 'Alaminos',
          'telephone': '',
          'cellphone': '09171234567',
        }
      : null,
  'corrections': corrections,
};

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository(this.afterSave);
  UserModel afterSave;
  int loads = 0;

  @override
  Future<UserModel?> fetchUserProfile(String uid) async {
    loads++;
    return afterSave;
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(_FakeAuthRepository());
  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;
}

class _FakeAssessmentRepository extends AssessmentRepository {
  @override
  Future<bool> ensureQuickAssessmentCompletion(String userId) async => true;
}

const _student = UserModel(
  id: 'u1',
  email: 'leo@example.com',
  populationRole: PopulationRole.student,
  personalInfoRequired: true,
  profileVersion: 3,
);

void main() {
  late List<Map<String, Object?>> calls;
  late _FakeUserRepository userRepo;
  late _FakeAuthProvider authProvider;

  Future<void> pump(
    WidgetTester tester, {
    StudentInfoMode mode = StudentInfoMode.onboarding,
    Map<String, Object?>? response,
    Object? saveError,
    UserModel? reloaded,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    calls = [];
    authProvider = _FakeAuthProvider();
    userRepo = _FakeUserRepository(
      reloaded ?? _student.copyWith(personalInfoRequired: false),
    );
    final userProvider = UserProvider(userRepo)..setUser(_student);
    final repo = StudentRosterRepository(
      academicLoader: () async => (
        colleges: const [
          AcademicOption(id: 'colA', name: 'College of Computing'),
          AcademicOption(id: 'colB', name: 'College of Other'),
        ],
        courses: const [
          AcademicOption(id: 'crsA', name: 'BSIT', collegeId: 'colA'),
          AcademicOption(id: 'crsB', name: 'BS Other', collegeId: 'colB'),
        ],
      ),
      invoker: (name, data) async {
        calls.add({'name': name, ...data});
        if (name == 'saveStudentPersonalInfo' && saveError != null) {
          throw saveError;
        }
        if (name == 'getMyStudentInformation') {
          return response ?? _infoResponse();
        }
        if (name == 'requestStudentCorrection') return {'requestId': 'r1'};
        return {};
      },
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AssessmentProvider>.value(
            value: AssessmentProvider(_FakeAssessmentRepository()),
          ),
        ],
        child: MaterialApp(
          routes: {
            RouteNames.profileSetup: (_) =>
                const Scaffold(body: Center(child: Text('setup target'))),
            RouteNames.login: (_) =>
                const Scaffold(body: Center(child: Text('login target'))),
            RouteNames.home: (_) =>
                const Scaffold(body: Center(child: Text('home target'))),
            RouteNames.onboarding: (_) =>
                const Scaffold(body: Center(child: Text('onboarding target'))),
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StudentInformationScreen(
                        mode: mode,
                        repository: repo,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(Key('field-$key'));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
  }

  Future<void> pick(WidgetTester tester, String key, String option) async {
    final finder = find.byKey(Key('field-$key'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillAll(WidgetTester tester) async {
    await pick(tester, 'sex', 'Male');
    await pick(tester, 'civilStatus', 'Single');
    await enter(tester, 'nationality', 'Filipino');
    await enter(tester, 'placeOfBirth', 'Alaminos');
    await enter(tester, 'homeAddress.barangay', 'Poblacion');
    await enter(tester, 'homeAddress.cityTown', 'Alaminos');
    await enter(tester, 'homeAddress.province', 'Pangasinan');
    await enter(tester, 'guardian', 'Ana Cruz');
    await enter(tester, 'guardianRelationship', 'Mother');
    await enter(tester, 'guardianAddress', 'Alaminos City');
    await enter(tester, 'cellphone', '09171234567');
  }

  Future<void> acceptConsent(WidgetTester tester) async {
    await tester.ensureVisible(find.text(_consent));
    await tester.tap(find.text(_consent));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton());
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
  }

  testWidgets('onboarding shows consent and Save is disabled until checked', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(_consent), findsOneWidget);
    await fillAll(tester);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await acceptConsent(tester);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
  });

  testWidgets('edit mode has no consent checkbox', (tester) async {
    await pump(
      tester,
      mode: StudentInfoMode.edit,
      response: _infoResponse(withPersonal: true),
    );
    expect(find.text(_consent), findsNothing);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);
  });

  testWidgets('official fields are read-only with correction actions', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('2021-00123'), findsOneWidget);
    expect(find.text('Dela Cruz'), findsOneWidget);
    expect(find.text('Feb 3, 2005'), findsOneWidget);
    // Only Student No. and Email have no correction action.
    expect(find.text('Request correction'), findsNWidgets(7));
    expect(find.byKey(const Key('correct-studentNo')), findsNothing);
    expect(find.byKey(const Key('correct-email')), findsNothing);
    expect(find.byKey(const Key('correct-college')), findsOneWidget);
    expect(find.text('leo@example.com'), findsOneWidget);
  });

  testWidgets('first save from edit mode needs the consent checkbox', (
    tester,
  ) async {
    await pump(tester, mode: StudentInfoMode.edit);
    expect(find.text(_consent), findsOneWidget);
    await fillAll(tester);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await acceptConsent(tester);
    await tapSave(tester);
    final save = calls.firstWhere(
      (c) => c['name'] == 'saveStudentPersonalInfo',
    );
    expect(save['privacyConsent'], true);
  });

  testWidgets('onboarding sign out signs out and opens login', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(authProvider.signOuts, 1);
    expect(find.text('login target'), findsOneWidget);
  });

  testWidgets('college correction offers colleges and submits the id', (
    tester,
  ) async {
    await pump(tester, mode: StudentInfoMode.edit);
    await tester.ensureVisible(find.byKey(const Key('correct-college')));
    await tester.tap(find.byKey(const Key('correct-college')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('correction-value')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('College of Other').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('correction-reason')), 'Moved');
    await tester.pump();
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    final call = calls.firstWhere(
      (c) => c['name'] == 'requestStudentCorrection',
    );
    expect(call['field'], 'college');
    expect(call['requestedValue'], 'colB');
  });

  testWidgets('course correction lists only the current college courses', (
    tester,
  ) async {
    await pump(tester, mode: StudentInfoMode.edit);
    await tester.ensureVisible(find.byKey(const Key('correct-course')));
    await tester.tap(find.byKey(const Key('correct-course')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('correction-value')));
    await tester.pumpAndSettle();
    expect(find.text('BS Other'), findsNothing);
    await tester.tap(find.text('BSIT').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('correction-reason')),
      'Shifted',
    );
    await tester.pump();
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    final call = calls.firstWhere(
      (c) => c['name'] == 'requestStudentCorrection',
    );
    expect(call['field'], 'course');
    expect(call['requestedValue'], 'crsA');
  });

  testWidgets('spouse field appears only when Married', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('field-spouse')), findsNothing);
    await pick(tester, 'civilStatus', 'Married');
    expect(find.byKey(const Key('field-spouse')), findsOneWidget);
    await pick(tester, 'civilStatus', 'Single');
    expect(find.byKey(const Key('field-spouse')), findsNothing);
  });

  testWidgets('client validation blocks save and shows field errors', (
    tester,
  ) async {
    await pump(tester);
    await acceptConsent(tester);
    await tapSave(tester);
    expect(find.text('Cellphone is required.'), findsOneWidget);
    expect(find.text('Guardian is required.'), findsOneWidget);
    expect(calls.where((c) => c['name'] == 'saveStudentPersonalInfo'), isEmpty);
  });

  testWidgets('server invalid-argument errors render under their fields', (
    tester,
  ) async {
    await pump(
      tester,
      saveError: FirebaseFunctionsException(
        code: 'invalid-argument',
        message: 'Please correct the highlighted fields.',
        details: {
          'errors': {
            'cellphone': 'Enter a valid Philippine mobile number.',
            'homeAddress.barangay': 'Barangay is required.',
          },
        },
      ),
    );
    await fillAll(tester);
    await acceptConsent(tester);
    await tapSave(tester);
    expect(
      find.text('Enter a valid Philippine mobile number.'),
      findsOneWidget,
    );
    expect(find.text('Barangay is required.'), findsOneWidget);
  });

  testWidgets('a revoked account sees the server reason, not a network hint', (
    tester,
  ) async {
    await pump(
      tester,
      saveError: FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'This account has been revoked.',
      ),
    );
    await fillAll(tester);
    await acceptConsent(tester);
    await tapSave(tester);
    expect(find.text('This account has been revoked.'), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
  });

  testWidgets('onboarding save reloads the user and follows the gate', (
    tester,
  ) async {
    await pump(
      tester,
      reloaded: _student.copyWith(
        personalInfoRequired: false,
        profileSetupCompleted: false,
      ),
    );
    await fillAll(tester);
    await acceptConsent(tester);
    await tapSave(tester);
    final save = calls.firstWhere(
      (c) => c['name'] == 'saveStudentPersonalInfo',
    );
    expect(save['privacyConsent'], true);
    expect(userRepo.loads, 1);
    expect(find.text('setup target'), findsOneWidget);
  });

  testWidgets(
    'legacy student with finished setup lands on normal destination',
    (tester) async {
      await pump(
        tester,
        reloaded: _student.copyWith(
          personalInfoRequired: false,
          profileSetupCompleted: true,
          firstName: 'Leo',
          lastName: 'Cruz',
          schoolId: '2021-00123',
          department: 'CCS',
          course: 'BSIT',
          yearLevel: '2nd Year',
        ),
      );
      await fillAll(tester);
      await acceptConsent(tester);
      await tapSave(tester);
      expect(find.text('home target'), findsOneWidget);
    },
  );

  testWidgets('edit mode save pops with a SnackBar', (tester) async {
    await pump(
      tester,
      mode: StudentInfoMode.edit,
      response: _infoResponse(withPersonal: true),
    );
    await tapSave(tester);
    expect(find.text('Student information saved.'), findsOneWidget);
    expect(find.byType(StudentInformationScreen), findsNothing);
  });

  testWidgets('correction sheet submits requestCorrection with field key', (
    tester,
  ) async {
    await pump(tester, mode: StudentInfoMode.edit);
    await tester.ensureVisible(find.byKey(const Key('correct-surname')));
    await tester.tap(find.byKey(const Key('correct-surname')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('correction-value')),
      'Del Cruz',
    );
    await tester.enterText(
      find.byKey(const Key('correction-reason')),
      'Misspelled',
    );
    await tester.pump();
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    final call = calls.firstWhere(
      (c) => c['name'] == 'requestStudentCorrection',
    );
    expect(call['field'], 'surname');
    expect(call['requestedValue'], 'Del Cruz');
    expect(call['reason'], 'Misspelled');
  });

  testWidgets('pending corrections render with status chips', (tester) async {
    await pump(
      tester,
      mode: StudentInfoMode.edit,
      response: _infoResponse(
        corrections: [
          {
            'id': 'c1',
            'field': 'surname',
            'currentValue': 'Dela Cruz',
            'requestedValue': 'Del Cruz',
            'reason': 'Misspelled',
            'status': 'pending',
            'reviewReason': '',
            'createdAt': '2026-11-01T00:00:00Z',
          },
          {
            'id': 'c2',
            'field': 'firstName',
            'currentValue': 'Leo',
            'requestedValue': 'Leon',
            'reason': 'x',
            'status': 'rejected',
            'reviewReason': 'No proof',
            'createdAt': '2026-11-01T00:00:00Z',
          },
        ],
      ),
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    // A field with a pending request cannot be corrected again.
    expect(find.byKey(const Key('correct-surname')), findsNothing);
    expect(find.byKey(const Key('correct-firstName')), findsOneWidget);
  });
}

Finder saveButton() => find.widgetWithText(FilledButton, 'Save');
