import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_environment.dart';

class AuthService {
  AuthService({this.firebaseAuth});

  final FirebaseAuth? firebaseAuth;

  FirebaseAuth get _instance => firebaseAuth ?? FirebaseAuth.instance;

  User? get currentUser => _instance.currentUser;
  Future<void> reloadCurrentUser() =>
      _instance.currentUser?.reload() ?? Future.value();
  String? get currentUserDisplayName => _instance.currentUser?.displayName;
  String? get currentUserPhotoUrl => _instance.currentUser?.photoURL;
  Stream<User?> get authStateChanges => _instance.authStateChanges();

  Future<User?> restoreCurrentUser({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final existing = _instance.currentUser;
    if (existing != null) return existing;
    try {
      return await _instance.authStateChanges().first.timeout(timeout);
    } on TimeoutException {
      return _instance.currentUser;
    }
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) {
    return _instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendEmailVerification() async {
    final user = _instance.currentUser;
    if (user == null) throw StateError('A signed-in account is required.');
    if (!user.emailVerified) await user.sendEmailVerification();
  }

  Future<void> sendPasswordResetEmail(String email) =>
      _instance.sendPasswordResetEmail(email: email.trim());

  Future<UserCredential> signInWithGoogle() async {
    await GoogleSignIn.instance.initialize(
      serverClientId: _googleServerClientId,
    );
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'google-id-token-missing',
        message: 'Google did not return an identity token.',
      );
    }
    return _instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  Future<void> signOut() {
    return _instance.signOut();
  }

  String get _googleServerClientId => switch (AppEnvironmentConfig.current) {
    AppEnvironment.development =>
      '1004916101316-q0bk543hbspqju7r77lim4686qvi0orh.apps.googleusercontent.com',
    AppEnvironment.staging =>
      '978195258114-f19i0ntghiguga85qlo4b4ou701o20vf.apps.googleusercontent.com',
    AppEnvironment.production =>
      '842251480963-csirkeh4ah6a02sg89id6qfkr41rrk91.apps.googleusercontent.com',
  };
}
