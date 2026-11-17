import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/platform/browser_navigation.dart';
import '../theme/admin_theme.dart';

class AdminEmailActionScreen extends StatefulWidget {
  const AdminEmailActionScreen({
    required this.uri,
    this.auth,
    this.onReplaceLocation,
    super.key,
  });

  final Uri uri;
  final FirebaseAuth? auth;
  final void Function(String url)? onReplaceLocation;

  static const _obsoleteAdminHosts = <String>{
    'mindmate-admin-staging.vercel.app',
  };
  static const _stagingOnlyHosts = <String>{
    'paaccmindmate.com',
    'www.paaccmindmate.com',
    'mindmate-staging.web.app',
    'mindmate-staging.firebaseapp.com',
    'mindmate-admin-staging.vercel.app',
  };
  static const _productionOnlyHosts = <String>{
    'mind-mates-cd2cf.web.app',
    'mind-mates-cd2cf.firebaseapp.com',
  };
  static const _developmentOnlyHosts = <String>{
    'mindmate-dev-4e91c.web.app',
    'mindmate-dev-4e91c.firebaseapp.com',
  };

  static bool supports(Uri uri) {
    final mode = uri.queryParameters['mode'];
    return uri.queryParameters['oobCode']?.isNotEmpty == true &&
        const {'resetPassword', 'verifyEmail', 'recoverEmail'}.contains(mode);
  }

  /// Resolves a validated same-environment sign-in origin without retaining
  /// sensitive action-code query parameters.
  static String resolveReturnToSignInUrl(
    Uri currentUri, {
    Uri? fallbackBaseUri,
    AppEnvironment? environment,
  }) {
    final env = environment ?? AppEnvironmentConfig.current;
    for (final candidate in [currentUri, ?fallbackBaseUri]) {
      final validated = _validatedOriginRoot(candidate, env);
      if (validated != null) return validated;
    }
    return '/';
  }

  static String? _validatedOriginRoot(Uri candidate, AppEnvironment env) {
    final scheme = candidate.scheme.toLowerCase();
    final host = candidate.host.toLowerCase();
    if (host.isEmpty || _obsoleteAdminHosts.contains(host)) return null;
    final isLocalhost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (scheme != 'https' && !(scheme == 'http' && isLocalhost)) return null;
    final disallowedHosts = switch (env) {
      AppEnvironment.staging => {
        ..._productionOnlyHosts,
        ..._developmentOnlyHosts,
      },
      AppEnvironment.production => {
        ..._stagingOnlyHosts,
        ..._developmentOnlyHosts,
      },
      AppEnvironment.development => _productionOnlyHosts,
    };
    if (disallowedHosts.contains(host)) return null;
    return Uri(
      scheme: scheme,
      host: host,
      port: candidate.hasPort ? candidate.port : null,
      path: '/',
    ).toString();
  }

  @override
  State<AdminEmailActionScreen> createState() => _AdminEmailActionScreenState();
}

class _AdminEmailActionScreenState extends State<AdminEmailActionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = true;
  bool _complete = false;
  bool _alreadyVerified = false;
  String? _email;
  String? _error;

  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  String get _mode => widget.uri.queryParameters['mode'] ?? '';
  String get _code => widget.uri.queryParameters['oobCode'] ?? '';

  @override
  void initState() {
    super.initState();
    _prepareAction();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _prepareAction() async {
    try {
      if (_mode == 'resetPassword') {
        _email = await _auth.verifyPasswordResetCode(_code);
      } else {
        final info = await _auth.checkActionCode(_code);
        _email = info.data['email']?.toString();
        if (_mode == 'verifyEmail') {
          // A verification link has one clear purpose. Apply Firebase's
          // signed action code automatically, then show the MindMate result.
          await _auth.applyActionCode(_code);
          await _auth.currentUser?.reload();
          _complete = true;
        }
      }
    } on FirebaseAuthException catch (error) {
      if (_mode == 'verifyEmail' &&
          error.code == 'invalid-action-code' &&
          _auth.currentUser?.emailVerified == true) {
        _alreadyVerified = true;
      } else {
        _error = _messageFor(error);
      }
    } catch (_) {
      _error = 'This account link could not be verified. Request a new link.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_loading || _complete || _alreadyVerified || _error != null) return;
    if (_mode == 'resetPassword' &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _loading = true);
    try {
      if (_mode == 'resetPassword') {
        await _auth.confirmPasswordReset(
          code: _code,
          newPassword: _password.text,
        );
      } else {
        await _auth.applyActionCode(_code);
      }
      if (mounted) setState(() => _complete = true);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The request could not be completed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(FirebaseAuthException error) => switch (error.code) {
    'expired-action-code' =>
      'This link has expired. Return to sign in and request a new one.',
    'invalid-action-code' =>
      'This link is invalid or has already been used. Request a new one.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' => 'The account for this link no longer exists.',
    'weak-password' => 'Choose a stronger password with at least 8 characters.',
    _ => 'The account action could not be completed. Please request a new link and try again.',
  };

  String get _title {
    if (_complete || _alreadyVerified) {
      return switch (_mode) {
        'resetPassword' => 'Password updated',
        'verifyEmail' => _alreadyVerified ? 'Email already verified' : 'Email verified',
        'recoverEmail' => 'Email restored',
        _ => 'Completed',
      };
    }
    return switch (_mode) {
      'resetPassword' => 'Choose a new password',
      'verifyEmail' => 'Verify your email',
      'recoverEmail' => 'Restore your email',
      _ => 'Account action',
    };
  }

  String get _description {
    if (_complete || _alreadyVerified) {
      return switch (_mode) {
        'resetPassword' =>
          'Your password was changed successfully. You can now sign in.',
        'verifyEmail' => _alreadyVerified
            ? 'This email address has already been verified. Sign in to view your PACC access request status.'
            : 'Your email address has been verified. Sign in to continue your PACC access request and administrator review.',
        'recoverEmail' => 'Your previous email address has been restored.',
        _ => 'Your request was completed successfully.',
      };
    }
    return switch (_mode) {
      'resetPassword' =>
        'Enter a secure password for ${_email ?? 'your account'}.',
      'verifyEmail' =>
        'Confirm that you want to verify ${_email ?? 'this email address'}.',
      'recoverEmail' =>
        'Confirm that you want to restore ${_email ?? 'your previous email address'}.',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 500 ? 24 : 36,
                ),
                child: _loading && _email == null && _error == null
                    ? const SizedBox(
                        height: 260,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Column(
                              children: [
                                Text('MindMate', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                                SizedBox(height: 4),
                                Text('COUNSELING MANAGEMENT SYSTEM', style: TextStyle(fontSize: 10, letterSpacing: 1, color: AdminColors.muted)),
                                SizedBox(height: 24),
                              ],
                            ),
                            Icon(
                              _error != null
                                  ? Icons.link_off_rounded
                                  : (_complete || _alreadyVerified)
                                  ? Icons.check_circle_rounded
                                  : Icons.lock_reset_rounded,
                              size: 64,
                              color: _error != null
                                  ? Colors.red.shade700
                                  : _complete
                                  ? AdminColors.success
                                  : AdminColors.accentStrong,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _error == null ? _title : 'Link unavailable',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error ?? _description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(height: 1.45),
                            ),
                            if (_mode == 'resetPassword' &&
                                _error == null &&
                                !_complete) ...[
                              const SizedBox(height: 26),
                              TextFormField(
                                controller: _password,
                                obscureText: true,
                                enabled: !_loading,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'New password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if ((value ?? '').length < 8) {
                                    return 'Use at least 8 characters.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirmation,
                                obscureText: true,
                                enabled: !_loading,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Confirm new password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) => value != _password.text
                                    ? 'Passwords do not match.'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (_error == null && !_complete && !_alreadyVerified && _mode != 'verifyEmail')
                              FilledButton.icon(
                                onPressed: _loading ? null : _submit,
                                icon: _loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: Text(
                                  _mode == 'resetPassword'
                                      ? 'Update password'
                                      : 'Confirm',
                                ),
                              ),
                            if (_complete || _alreadyVerified || _error != null)
                              FilledButton.icon(
                                onPressed: () => _returnToAdmin(),
                                icon: const Icon(Icons.login_rounded),
                                label: Text(
                                  _error == null
                                      ? 'Continue to sign in'
                                      : 'Return to sign in',
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _returnToAdmin() {
    // A full navigation removes the one-time action code from browser history.
    final destination = AdminEmailActionScreen.resolveReturnToSignInUrl(
      widget.uri,
      fallbackBaseUri: Uri.base,
    );
    (widget.onReplaceLocation ?? replaceBrowserLocation)(destination);
  }
}
