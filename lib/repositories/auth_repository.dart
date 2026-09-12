import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../database/firestore_collections.dart';
import '../features/quick_assessment/models/quick_assessment_models.dart';
import '../services/auth/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/firebase_app_check_service.dart';
import '../services/firebase/firebase_callable_router.dart';
import '../services/firebase/firebase_runtime_diagnostics.dart';

class AuthRepository {
  AuthRepository(
    this._authService, {
    FirestoreService? firestoreService,
    FirebaseFunctions? functions,
  }) : _firestoreService = firestoreService ?? FirestoreService(),
       _providedFunctions = functions;

  final AuthService _authService;
  final FirestoreService _firestoreService;
  final FirebaseFunctions? _providedFunctions;
  FirebaseFunctions get _functions =>
      _providedFunctions ??
      FirebaseFunctions.instanceFor(region: 'us-central1');

  String? get currentUserId => _authService.currentUser?.uid;
  String? get currentUserEmail => _authService.currentUser?.email;
  bool get currentUserEmailVerified =>
      _authService.currentUser?.emailVerified ?? false;
  String? get currentUserDisplayName => _authService.currentUserDisplayName;
  String? get currentUserPhotoUrl => _authService.currentUserPhotoUrl;
  Stream<String?> watchAuthenticatedUserIds() =>
      _authService.authStateChanges.map((user) => user?.uid);

  Future<String?> restoreCurrentUser() async {
    final user = await _authService.restoreCurrentUser();
    return user?.uid;
  }

  Future<void> reloadCurrentUser() => _authService.reloadCurrentUser();
  Future<void> sendEmailVerification() => _authService.sendEmailVerification();

  static const _authEmailDomain = 'mindmate.local';
  static const institutionalEmailDomain = 'ucu.edu.ph';

  static bool isInstitutionalEmployeeEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final parts = normalized.split('@');
    return parts.length == 2 &&
        parts.first.isNotEmpty &&
        parts.last == institutionalEmailDomain;
  }

  static AssessmentRole registrationRoleForEmail(String email) =>
      isInstitutionalEmployeeEmail(email)
      ? AssessmentRole.faculty
      : AssessmentRole.student;

  static String authEmailForSchoolId(String schoolId) {
    final normalized = schoolId
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
        .replaceAll(RegExp(r'\.+'), '.')
        .replaceAll(RegExp(r'^\.|\.$'), '');
    final localPart = normalized.isEmpty ? 'user' : normalized;
    return '$localPart@$_authEmailDomain';
  }

  Future<UserCredential> signIn({
    required String schoolId,
    required String password,
  }) async {
    final email = await resolveAuthEmailForSchoolId(schoolId);
    return _authService.signIn(email: email, password: password);
  }

  Future<String> resolveAuthEmailForSchoolId(String schoolId) async {
    final identifier = schoolId.trim();
    if (identifier.isEmpty || identifier.contains('@')) {
      throw FirebaseAuthException(code: 'invalid-credential');
    }
    final response = await _functions
        .routedCallable('resolveSchoolIdAuthEmail')
        .call({'schoolId': identifier});
    final data = response.data;
    final email = data is Map ? data['email']?.toString().trim() : null;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(code: 'invalid-credential');
    }
    return email;
  }

  Future<void> sendPasswordResetForSchoolId(String schoolId) async {
    final email = await resolveAuthEmailForSchoolId(schoolId);
    if (email.toLowerCase().endsWith('@$_authEmailDomain')) {
      throw FirebaseAuthException(
        code: 'password-reset-unavailable',
        message:
            'This older account has no verified recovery email. Contact MindMate support.',
      );
    }
    await _authService.sendPasswordResetEmail(email);
  }

  Future<UserCredential> signInWithGoogle() => _authService.signInWithGoogle();

  Future<UserCredential> signUp({
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
    return _signUpWithEmail(
      email: authEmailForSchoolId(schoolId),
      password: password,
      firstName: firstName,
      lastName: lastName,
      schoolId: schoolId,
      department: department,
      course: course,
      sector: sector,
      employeeId: employeeId,
      yearLevel: yearLevel,
      position: position,
      middleName: middleName,
      role: role,
      dateOfBirth: dateOfBirth,
      gender: gender,
    );
  }

  Future<UserCredential> signUpWithEmail({
    required String email,
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
  }) => _signUpWithEmail(
    email: email,
    password: password,
    firstName: firstName,
    lastName: lastName,
    schoolId: schoolId,
    department: department,
    course: course,
    sector: sector,
    employeeId: employeeId,
    yearLevel: yearLevel,
    position: position,
    middleName: middleName,
    role: role,
    dateOfBirth: dateOfBirth,
    gender: gender,
  );

  Future<UserCredential> _signUpWithEmail({
    required String email,
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
    final authEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(authEmail)) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address.',
      );
    }
    // Avoid creating an Auth-only account when this installation cannot call
    // the App Check-enforced profile provisioning backend.
    FirebaseRuntimeDiagnostics.log(event: 'signup_app_check_preflight_started');
    try {
      await FirebaseAppCheckService.refreshToken();
      await FirebaseAppCheckService.requireToken();
      FirebaseRuntimeDiagnostics.log(
        event: 'signup_app_check_preflight_succeeded',
      );
    } catch (error, stackTrace) {
      FirebaseRuntimeDiagnostics.log(
        event: 'signup_app_check_preflight_failed',
        error: error,
        errorCode: 'app-check',
      );
      Error.throwWithStackTrace(SignupAppCheckException(error), stackTrace);
    }
    late final UserCredential credential;
    try {
      FirebaseRuntimeDiagnostics.log(event: 'signup_auth_creation_started');
      credential = await _authService.signUp(
        email: authEmail,
        password: password,
      );
      FirebaseRuntimeDiagnostics.log(event: 'signup_auth_creation_succeeded');
    } on FirebaseAuthException catch (error) {
      FirebaseRuntimeDiagnostics.log(
        event: 'signup_auth_creation_failed',
        error: error,
      );
      if (error.code != 'email-already-in-use') rethrow;

      // A previous signup may have created the Auth account before profile
      // provisioning was interrupted. Authenticate that account and repair it
      // only when its Firestore profile is genuinely missing.
      try {
        credential = await _authService.signIn(
          email: authEmail,
          password: password,
        );
      } on FirebaseAuthException catch (signInError) {
        // Keep the original registration conflict when the submitted password
        // does not belong to the existing account. Exposing the sign-in error
        // here incorrectly suggests that a new registration can continue by
        // changing its password and hides the actual duplicate email.
        if ({
          'invalid-credential',
          'wrong-password',
          'user-not-found',
        }.contains(signInError.code)) {
          throw FirebaseAuthException(
            code: 'email-already-in-use',
            message:
                'This email address is already registered. Sign in or use a different email address.',
          );
        }
        rethrow;
      }
      final recoveredUser = credential.user;
      Map<String, dynamic>? existingProfile;
      if (recoveredUser != null) {
        try {
          existingProfile = await _firestoreService.getDocument(
            FirestoreCollections.users,
            recoveredUser.uid,
          );
        } catch (profileError, stackTrace) {
          Error.throwWithStackTrace(
            SignupProfileLookupException(recoveredUser.uid, profileError),
            stackTrace,
          );
        }
      }
      if (existingProfile != null) {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'An account already exists for this School ID.',
        );
      }
    }
    final user = credential.user;

    if (user != null) {
      try {
        await _saveProfile(
          uid: user.uid,
          authEmail: authEmail,
          firstName: firstName,
          lastName: lastName,
          schoolId: schoolId,
          department: department,
          course: course,
          sector: sector,
          employeeId: employeeId,
          yearLevel: yearLevel,
          position: position,
          middleName: middleName,
          role: role,
          dateOfBirth: dateOfBirth,
          gender: gender,
        );
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          SignupProfileProvisioningException(user.uid, error),
          stackTrace,
        );
      }
    }

    return credential;
  }

  Future<String> completeProfileSetup({
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
    final uid = currentUserId;
    final authEmail = currentUserEmail;
    if (uid == null || authEmail == null || authEmail.trim().isEmpty) {
      throw StateError('The pending signup session is no longer available.');
    }
    try {
      await _saveProfile(
        uid: uid,
        authEmail: authEmail,
        firstName: firstName,
        lastName: lastName,
        schoolId: schoolId,
        department: department,
        course: course,
        sector: sector,
        employeeId: employeeId,
        yearLevel: yearLevel,
        position: position,
        middleName: middleName,
        role: role,
        dateOfBirth: dateOfBirth,
        gender: gender,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SignupProfileProvisioningException(uid, error),
        stackTrace,
      );
    }
    return uid;
  }

  Future<String> completeFederatedProfileSetup({
    required String firstName,
    required String lastName,
    required String schoolId,
    required String department,
    required String course,
    required String yearLevel,
    required DateTime dateOfBirth,
    String? middleName,
    String? employeeId,
    String? position,
    AssessmentRole role = AssessmentRole.student,
    String? gender,
  }) async {
    final user = _authService.currentUser;
    if (user == null ||
        user.email == null ||
        user.email!.endsWith('@mindmate.local')) {
      throw StateError('A Google-authenticated session is required.');
    }
    await _saveProfile(
      uid: user.uid,
      authEmail: user.email!,
      firstName: firstName,
      lastName: lastName,
      schoolId: schoolId,
      department: department,
      course: course,
      yearLevel: yearLevel,
      middleName: middleName,
      employeeId: employeeId,
      position: position,
      role: role,
      dateOfBirth: dateOfBirth,
      gender: gender,
    );
    return user.uid;
  }

  Future<void> _saveProfile({
    required String uid,
    required String authEmail,
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
    final populationRole = role?.populationRole;
    if (populationRole == null) {
      throw StateError('Choose an account role before creating the profile.');
    }
    if (_authService.currentUser?.uid != uid) {
      throw StateError('The authenticated signup session is unavailable.');
    }
    await _authService.currentUser!.getIdToken(true);
    await FirebaseAppCheckService.refreshToken();
    await FirebaseAppCheckService.requireToken();
    final response = await _functions
        .routedCallable('provisionAppUserProfile')
        .call({
          'firstName': firstName.trim(),
          'middleName': middleName?.trim() ?? '',
          'lastName': lastName.trim(),
          'name': [
            firstName.trim(),
            if ((middleName ?? '').trim().isNotEmpty) middleName!.trim(),
            lastName.trim(),
          ].join(' '),
          'employeeId': employeeId?.trim() ?? '',
          'department': department.trim(),
          'course': course.trim(),
          'yearLevel': yearLevel?.trim() ?? '',
          'sector': sector?.trim() ?? '',
          'position': position?.trim() ?? '',
          'populationRole': populationRole.storedValue,
          'schoolId': schoolId.trim(),
          if (dateOfBirth != null)
            'dateOfBirth': dateOfBirth.toUtc().toIso8601String(),
          'gender': gender?.trim() ?? '',
        });
    final responseData = response.data;
    FirebaseRuntimeDiagnostics.log(
      event: 'signup_profile_provisioned',
      correlationId: responseData is Map
          ? responseData['correlationId']?.toString()
          : null,
    );
  }

  Future<void> signOut() {
    return _authService.signOut();
  }
}

class SignupProfileProvisioningException implements Exception {
  const SignupProfileProvisioningException(this.userId, this.cause);

  final String userId;
  final Object cause;

  @override
  String toString() => 'Account created, but profile setup failed: $cause';
}

class SignupAppCheckException implements Exception {
  const SignupAppCheckException(this.cause);

  final Object cause;

  @override
  String toString() => 'Firebase App Check preflight failed (code=app-check).';
}

class SignupProfileLookupException implements Exception {
  const SignupProfileLookupException(this.userId, this.cause);

  final String userId;
  final Object cause;

  @override
  String toString() =>
      'Signed in, but the existing profile check failed: $cause';
}
