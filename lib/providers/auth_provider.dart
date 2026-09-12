import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/quick_assessment/models/quick_assessment_models.dart';
import '../repositories/auth_repository.dart';
import '../services/firebase/firebase_error_message.dart';

enum SignupState {
  idle,
  complete,
  appCheckRejected,
  profileSetupPending,
  profileLookupPending,
  duplicateEmail,
  duplicateSchoolId,
  networkFailed,
  authenticationFailed,
}

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repository, {this.onSessionCleared});

  final AuthRepository _repository;
  final VoidCallback? onSessionCleared;

  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _userId;
  String? _errorMessage;
  String? _registrationEmail;
  String? _pendingSignupSchoolId;
  SignupState _signupState = SignupState.idle;
  StreamSubscription<String?>? _authSubscription;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get userId => _userId ?? _repository.currentUserId;

  /// The current Firebase user ID, excluding any cached provider state.
  String? get authenticatedUserId => _repository.currentUserId;
  String? get currentUserEmail {
    try {
      return _repository.currentUserEmail;
    } catch (_) {
      return null;
    }
  }

  bool get currentUserEmailVerified {
    try {
      return _repository.currentUserEmailVerified;
    } catch (_) {
      return false;
    }
  }

  Future<void> reloadCurrentUser() => _repository.reloadCurrentUser();
  Future<void> sendEmailVerification() => _repository.sendEmailVerification();
  Future<bool> sendPasswordResetForSchoolId(String schoolId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.sendPasswordResetForSchoolId(schoolId);
      return true;
    } catch (error, stackTrace) {
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Password reset failed.',
      );
      _errorMessage = FirebaseErrorMessage.describe(
        error,
        fallback: 'Unable to send a password reset link. Please try again.',
      );
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setRegistrationEmail(String email) => _registrationEmail = email.trim();
  String? get currentUserDisplayName => _repository.currentUserDisplayName;
  String? get currentUserPhotoUrl => _repository.currentUserPhotoUrl;
  String? get errorMessage => _errorMessage;
  SignupState get signupState => _signupState;
  bool get hasPendingProfileSetup =>
      _signupState == SignupState.profileSetupPending;
  bool get hasPendingProfileLookup =>
      _signupState == SignupState.profileLookupPending;

  void monitorAuthState() {
    _authSubscription ??= _repository.watchAuthenticatedUserIds().listen((id) {
      if (id == null || id.isEmpty) {
        _clearSession();
        return;
      }
      if (_userId == id && _isAuthenticated) return;
      _userId = id;
      _isAuthenticated = true;
      notifyListeners();
    });
  }

  String? hydrateCurrentUser() {
    final id = _repository.currentUserId;
    if (id == null || id.isEmpty) {
      _clearSession();
      return null;
    }

    _userId = id;
    _isAuthenticated = true;
    notifyListeners();
    return id;
  }

  Future<String?> restoreCurrentUser() async {
    String? id = _repository.currentUserId;
    if (id == null) {
      try {
        id = await _repository.restoreCurrentUser();
      } catch (error, stackTrace) {
        FirebaseErrorMessage.log(
          error,
          stackTrace,
          area: 'Restoring Firebase Auth session failed.',
        );
        return null;
      }
    }
    if (id == null || id.isEmpty) {
      _clearSession();
      return null;
    }
    _userId = id;
    _isAuthenticated = true;
    notifyListeners();
    return id;
  }

  Future<String?> resolveAuthenticatedUserId() async {
    final liveId = authenticatedUserId;
    if (liveId != null && liveId.isNotEmpty) return liveId;
    return restoreCurrentUser();
  }

  void setAuthenticated(bool value) {
    _isAuthenticated = value;
    notifyListeners();
  }

  Future<String?> signIn({
    required String schoolId,
    required String password,
  }) async {
    return _runAuthAction(() async {
      final credential = await _repository.signIn(
        schoolId: schoolId,
        password: password,
      );
      return credential.user?.uid ?? _repository.currentUserId;
    }, signOutOnFailure: true);
  }

  Future<String?> signInWithGoogle() {
    return _runAuthAction(() async {
      final credential = await _repository.signInWithGoogle();
      return credential.user?.uid ?? _repository.currentUserId;
    }, signOutOnFailure: true);
  }

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
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final String? id;
      if (hasPendingProfileSetup &&
          _repository.currentUserId != null &&
          _pendingSignupSchoolId == schoolId.trim()) {
        id = await _repository.completeProfileSetup(
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
      } else {
        final credential = _registrationEmail?.isNotEmpty == true
            ? await _repository.signUpWithEmail(
                email: _registrationEmail!,
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
              )
            : await _repository.signUp(
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
        id = credential.user?.uid ?? _repository.currentUserId;
      }
      if (id == null || id.isEmpty) {
        throw StateError('Unable to identify authenticated user.');
      }

      _userId = id;
      _isAuthenticated = true;
      _signupState = SignupState.complete;
      _pendingSignupSchoolId = null;
      return id;
    } on SignupAppCheckException catch (error, stackTrace) {
      _clearSession(notify: false);
      _signupState = SignupState.appCheckRejected;
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Signup App Check preflight failed.',
      );
      try {
        await _repository.signOut();
      } catch (signOutError, signOutStackTrace) {
        FirebaseErrorMessage.log(
          signOutError,
          signOutStackTrace,
          area: 'Cleanup sign-out failed.',
        );
      }
      _errorMessage = FirebaseErrorMessage.appCheckMessage();
      return null;
    } on SignupProfileProvisioningException catch (error, stackTrace) {
      _userId = error.userId;
      _pendingSignupSchoolId = schoolId.trim();
      _isAuthenticated = _repository.currentUserId == error.userId;
      _signupState = SignupState.profileSetupPending;
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Signup profile provisioning failed.',
      );
      _errorMessage =
          '${FirebaseErrorMessage.describe(error.cause, fallback: 'Your account was created, but profile setup is incomplete.')} Your account is signed in; tap Retry profile setup.';
      return null;
    } on SignupProfileLookupException catch (error, stackTrace) {
      _userId = error.userId;
      _isAuthenticated = _repository.currentUserId == error.userId;
      _signupState = SignupState.profileLookupPending;
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Existing signup profile lookup failed.',
      );
      _errorMessage =
          '${FirebaseErrorMessage.describe(error.cause, fallback: 'Your account is signed in, but its profile could not be checked.')} Tap Retry account check.';
      return null;
    } catch (error, stackTrace) {
      _clearSession(notify: false);
      _signupState = _failedSignupState(error);
      FirebaseErrorMessage.log(error, stackTrace, area: 'Signup failed.');
      try {
        await _repository.signOut();
      } catch (signOutError, signOutStackTrace) {
        FirebaseErrorMessage.log(
          signOutError,
          signOutStackTrace,
          area: 'Cleanup sign-out failed.',
        );
      }
      _errorMessage = FirebaseErrorMessage.describe(
        error,
        fallback: 'Unable to create account. Please try again.',
      );
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> completeGoogleProfile({
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
  }) {
    return _runAuthAction(
      () => _repository.completeFederatedProfileSetup(
        firstName: firstName,
        lastName: lastName,
        schoolId: schoolId,
        department: department,
        course: course,
        yearLevel: yearLevel,
        dateOfBirth: dateOfBirth,
        middleName: middleName,
        employeeId: employeeId,
        position: position,
        role: role,
        gender: gender,
      ),
    );
  }

  SignupState _failedSignupState(Object error) {
    if (FirebaseErrorMessage.isAppCheckFailure(error)) {
      return SignupState.appCheckRejected;
    }
    if (FirebaseErrorMessage.codeOf(error) == 'email-already-in-use') {
      return SignupState.duplicateEmail;
    }
    if (FirebaseErrorMessage.isNetworkFailure(error)) {
      return SignupState.networkFailed;
    }
    return SignupState.authenticationFailed;
  }

  Future<void> signOut() async {
    await _repository.signOut();
    _clearSession(notify: false);
    notifyListeners();
  }

  void _clearSession({bool notify = true}) {
    _isAuthenticated = false;
    _userId = null;
    _registrationEmail = null;
    _pendingSignupSchoolId = null;
    _signupState = SignupState.idle;
    onSessionCleared?.call();
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<String?> _runAuthAction(
    Future<String?> Function() action, {
    bool signOutOnFailure = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final id = await action();
      if (id == null || id.isEmpty) {
        throw StateError('Unable to identify authenticated user.');
      }

      _userId = id;
      _isAuthenticated = true;
      return id;
    } catch (error, stackTrace) {
      _isAuthenticated = false;
      _userId = null;
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Authentication action failed.',
      );
      if (signOutOnFailure) {
        try {
          await _repository.signOut();
        } catch (signOutError, signOutStackTrace) {
          FirebaseErrorMessage.log(
            signOutError,
            signOutStackTrace,
            area: 'Cleanup sign-out failed.',
          );
        }
      }
      _errorMessage = FirebaseErrorMessage.describe(
        error,
        fallback: 'Something went wrong. Please try again.',
      );
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
