import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../repositories/student_roster_repository.dart';
import '../../../routes/route_names.dart';
import '../auth_flow_routes.dart';

/// Shown after a student signs in with the temporary password, and nothing
/// else is reachable until a permanent password is set. The server enforces
/// that; this screen is only how the student does it.
class StudentChangePasswordScreen extends StatefulWidget {
  const StudentChangePasswordScreen({super.key, this.repository});

  final StudentRosterRepository? repository;

  @override
  State<StudentChangePasswordScreen> createState() =>
      _StudentChangePasswordScreenState();
}

class _StudentChangePasswordScreenState
    extends State<StudentChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late final StudentRosterRepository _repository =
      widget.repository ?? StudentRosterRepository();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final pw = value ?? '';
    if (pw.length < 10) return 'Use at least 10 characters.';
    if (!RegExp('[a-z]').hasMatch(pw) ||
        !RegExp('[A-Z]').hasMatch(pw) ||
        !RegExp('[0-9]').hasMatch(pw)) {
      return 'Use upper-case and lower-case letters and a number.';
    }
    return null;
  }

  String _messageFor(Object error) {
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      final reason = details is Map ? details['reason'] : null;
      switch (reason) {
        case 'expired':
          return 'This temporary password has expired. Sign out and ask for a new login.';
        case 'recent-login-required':
        case 'sign-in-again':
          return 'Please sign out, sign in again, and retry.';
        case 'weak-password':
          return error.message ?? 'Choose a stronger password.';
      }
    }
    return 'We could not save your password. Please try again.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final authProvider = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final navigator = Navigator.of(context);
    final studentId = userProvider.user?.schoolId ?? '';
    final password = _password.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.completePasswordChange(password);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error);
      });
      return;
    }
    // The server revoked the temporary session; a fresh sign-in picks up the
    // cleared first-login state.
    final userId = await authProvider.signInWithStudentId(
      studentId: studentId,
      password: password,
    );
    if (!mounted) return;
    if (userId == null || !await userProvider.loadProfile(userId)) {
      await authProvider.signOut();
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
      return;
    }
    final next = gateRouteForUser(userProvider.user!) ?? RouteNames.splash;
    navigator.pushNamedAndRemoveUntil(next, (route) => false);
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    navigator.pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Create your password'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'You signed in with a temporary password. Choose your '
                        'own password to continue. You will use it every time '
                        'you sign in.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmation,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                        ),
                        validator: (value) =>
                            value != _password.text ? 'Passwords do not match.' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save password'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
