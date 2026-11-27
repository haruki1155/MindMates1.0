import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../theme/admin_theme.dart';
import 'admin_portal.dart';

class AdminChangePasswordScreen extends StatefulWidget {
  const AdminChangePasswordScreen({super.key, required this.repository});
  final AdminPortalRepository repository;

  @override
  State<AdminChangePasswordScreen> createState() =>
      _AdminChangePasswordScreenState();
}

class _AdminChangePasswordScreenState extends State<AdminChangePasswordScreen> {
  final formKey = GlobalKey<FormState>();
  final currentPassword = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool submitting = false;
  bool obscure = true;
  bool _obscureCurrent = true;
  late bool _showCurrentPassword;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _showCurrentPassword = !widget.repository.hasRecentSignInPassword;
  }

  @override
  void dispose() {
    currentPassword.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 500 ? 22 : 32,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.password, size: 52),
                      const SizedBox(height: 12),
                      const Text(
                        'Change your temporary password',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You must choose a private password before accessing the MindMate portal.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_showCurrentPassword) ...[
                        TextFormField(
                          key: const Key('current-password-field'),
                          controller: currentPassword,
                          enabled: !submitting,
                          obscureText: _obscureCurrent,
                          decoration: InputDecoration(
                            labelText: 'Current (temporary) password',
                            helperText:
                                'Enter the temporary password from your email to confirm your identity.',
                            helperMaxLines: 2,
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureCurrent = !_obscureCurrent,
                              ),
                              icon: Icon(
                                _obscureCurrent
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (!_showCurrentPassword) return null;
                            if ((value ?? '').isEmpty) {
                              return 'Enter your current temporary password.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        key: const Key('new-password-field'),
                        controller: password,
                        enabled: !submitting,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('confirm-password-field'),
                        controller: confirmation,
                        enabled: !submitting,
                        obscureText: obscure,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                        ),
                        validator: (value) => value != password.text
                            ? 'Passwords do not match.'
                            : null,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          key: const Key('change-password-error'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AdminColors.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AdminColors.danger.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AdminColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('submit-change-password'),
                          onPressed: submitting ? null : _submit,
                          child: Text(
                            submitting
                                ? 'Updating…'
                                : 'Change password and continue',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('change-password-sign-out'),
                        onPressed: submitting ? null : _signOut,
                        child: const Text('Sign out and return to login'),
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

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.length < 12) return 'Use at least 12 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(text) ||
        !RegExp(r'[a-z]').hasMatch(text) ||
        !RegExp(r'[0-9]').hasMatch(text) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(text)) {
      return 'Include uppercase, lowercase, number, and symbol.';
    }
    if (_showCurrentPassword &&
        currentPassword.text.isNotEmpty &&
        text == currentPassword.text) {
      return 'Choose a new password different from your temporary password.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (submitting) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() {
      submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.repository.completeMandatoryPasswordChange(
        password.text,
        currentPassword: _showCurrentPassword ? currentPassword.text : null,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AdminPortalHome(repository: widget.repository),
        ),
        (_) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'requires-recent-login') {
          _showCurrentPassword = true;
          _errorMessage =
              'Your sign-in session needs quick confirmation. Enter your temporary password above and try again.';
        } else if (error.code == 'wrong-password' ||
            error.code == 'invalid-credential') {
          _showCurrentPassword = true;
          _errorMessage =
              'The temporary password is incorrect. Check your email or sign out and sign in again.';
        } else {
          _errorMessage = FirebaseErrorMessage.describe(
            error,
            fallback:
                'Unable to update your password right now. Please try again.',
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = FirebaseErrorMessage.describe(
          error,
          fallback:
              'Unable to update your password right now. Please try again.',
        );
      });
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _signOut() async {
    if (submitting) return;
    setState(() => submitting = true);
    try {
      await widget.repository.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AdminLoginScreen(repository: widget.repository),
        ),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        _errorMessage = FirebaseErrorMessage.describe(
          error,
          fallback: 'Unable to sign out right now. Please try again.',
        );
      });
    }
  }
}
