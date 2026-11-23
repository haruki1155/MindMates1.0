import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../auth_flow_routes.dart';
import 'email_verification_screen.dart';

/// Route target for [RouteNames.emailVerification]. Students who sign in with
/// their Student ID verify their recovery email with an emailed code; every
/// other account keeps the existing link-based screen unchanged.
class EmailVerificationGate extends StatelessWidget {
  const EmailVerificationGate({super.key});

  @override
  Widget build(BuildContext context) {
    final studentIdAccount = context.select<AuthProvider, bool>(
      (auth) => auth.currentUserIsStudentAlias,
    );
    return studentIdAccount
        ? const StudentRecoveryVerificationScreen()
        : const EmailVerificationScreen();
  }
}

/// Verifies a Student ID account's recovery email with a one-time code that is
/// emailed to the address the student gave at activation. Only a masked
/// address is ever shown: the account's internal Auth email is never displayed.
class StudentRecoveryVerificationScreen extends StatefulWidget {
  const StudentRecoveryVerificationScreen({super.key});

  @override
  State<StudentRecoveryVerificationScreen> createState() =>
      _StudentRecoveryVerificationScreenState();
}

class _StudentRecoveryVerificationScreenState
    extends State<StudentRecoveryVerificationScreen> {
  static const _resendDelay = 60;
  static const _verifiedHold = Duration(milliseconds: 1200);

  final _codeController = TextEditingController();
  Timer? _cooldownTimer;
  String _maskedEmail = '';
  int _resendSeconds = 0;
  bool _sending = false;
  bool _verifying = false;
  bool _cancelling = false;
  bool _verified = false;
  bool _finishing = false;
  bool _finishFailed = false;
  String? _message;
  bool _messageIsError = false;

  bool get _busy => _sending || _verifying || _cancelling || _finishing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestCode();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _show(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _requestCode() async {
    if (_busy || _resendSeconds > 0) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      final result = await context
          .read<AuthProvider>()
          .requestRecoveryEmailCode();
      if (!mounted) return;
      if (result.alreadyVerified) {
        await _continue();
        return;
      }
      setState(() => _maskedEmail = result.maskedEmail);
      _show(
        'Check your inbox and spam folder. The code expires in 15 minutes.',
      );
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      _show(
        FirebaseErrorMessage.describe(
          error,
          fallback: 'Unable to send the verification code right now.',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendSeconds = _resendDelay);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  /// `ABCDE-FGHJK` from whatever the student typed, or null when it cannot be
  /// a code. The server normalizes and validates again.
  String? _typedCode() {
    final letters = _codeController.text.toUpperCase().replaceAll(
      RegExp(r'[\s-]'),
      '',
    );
    if (letters.length != 10) return null;
    return '${letters.substring(0, 5)}-${letters.substring(5)}';
  }

  Future<void> _verify() async {
    if (_busy) return;
    final code = _typedCode();
    if (code == null) {
      _show('Enter the 10-character code from your email.', error: true);
      return;
    }
    setState(() {
      _verifying = true;
      _message = null;
    });
    try {
      await context.read<AuthProvider>().confirmRecoveryEmailCode(code);
      if (!mounted) return;
      _cooldownTimer?.cancel();
      setState(() {
        _verified = true;
        _verifying = false;
      });
      _show('Email verified. Continuing…');
      await Future<void>.delayed(_verifiedHold);
      if (!mounted) return;
      await _continue();
    } catch (error) {
      if (!mounted) return;
      _show(_describeVerifyError(error), error: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String _describeVerifyError(Object error) {
    final base = FirebaseErrorMessage.describe(
      error,
      fallback: 'Unable to verify the code. Try again.',
    );
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      final remaining = details is Map ? details['attemptsRemaining'] : null;
      if (remaining is int && remaining >= 0) {
        return remaining == 0
            ? '$base Request a new code to try again.'
            : '$base $remaining ${remaining == 1 ? 'attempt' : 'attempts'} left.';
      }
    }
    return base;
  }

  static const _finishAttempts = 3;
  static const _finishRetryDelay = Duration(milliseconds: 700);

  /// Claims the roster record, loads the new profile and routes to the first-
  /// login gate (Student Information first). A failure never falls through to
  /// a stale or empty profile: the student can retry, and the finish step is
  /// idempotent on the server.
  Future<void> _continue() async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _finishFailed = false;
    });
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    String? route;
    for (
      var attempt = 0;
      attempt < _finishAttempts && route == null;
      attempt++
    ) {
      if (attempt > 0) await Future<void>.delayed(_finishRetryDelay);
      if (!mounted) return;
      try {
        await auth.completeStudentAccountSetup();
      } catch (_) {
        // Already complete, expired or transient: the profile load decides.
      }
      try {
        final userId = auth.userId;
        if (userId != null && await userProvider.loadProfile(userId)) {
          final user = userProvider.user;
          if (user != null) {
            route = gateRouteForUser(user) ?? RouteNames.profileSetup;
          }
        }
      } catch (_) {
        // Retried below.
      }
    }
    if (!mounted) return;
    if (route == null) {
      setState(() {
        _finishing = false;
        _finishFailed = true;
      });
      _show(
        'Your email is verified, but we could not finish setting up your account. Check your connection and try again.',
        error: true,
      );
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(route, (route) => false);
  }

  Future<void> _useAnotherEmail() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Use another email?'),
            content: const Text(
              'This removes your unfinished setup, including your reserved Student ID. You can then start again with the correct email.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep this email'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Use another email'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _cancelling = true;
      _message = null;
    });
    try {
      await context.read<AuthProvider>().cancelPendingRegistration();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(RouteNames.studentActivation, (route) => false);
    } catch (_) {
      if (!mounted) return;
      _show(
        context.read<AuthProvider>().errorMessage ??
            'Unable to cancel this pending setup. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resendLabel = _resendSeconds > 0
        ? 'Resend in ${_resendSeconds}s'
        : _sending
        ? 'Sending…'
        : 'Resend code';
    final where = _maskedEmail.isEmpty
        ? 'your recovery email address'
        : _maskedEmail;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 44,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Verify your recovery email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We sent a 10-character code to $where. You will use this email to reset your password if you ever forget it.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    key: const Key('recovery-code-field'),
                    controller: _codeController,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9 -]'),
                      ),
                      LengthLimitingTextInputFormatter(14),
                    ],
                    onSubmitted: (_) => _verify(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _messageIsError
                            ? AppColors.error
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_finishFailed)
                    FilledButton(
                      key: const Key('recovery-finish-retry'),
                      onPressed: _continue,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('Try again'),
                    )
                  else
                    FilledButton(
                      key: const Key('recovery-verify-button'),
                      onPressed: _busy || _verified ? null : _verify,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: AppColors.primary,
                      ),
                      child: Text(
                        _verified
                            ? 'Verified'
                            : _verifying
                            ? 'Verifying…'
                            : 'Verify email',
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('recovery-resend-button'),
                    onPressed: _busy || _verified || _resendSeconds > 0
                        ? null
                        : _requestCode,
                    child: Text(resendLabel),
                  ),
                  TextButton(
                    key: const Key('recovery-use-another-email'),
                    onPressed: _busy ? null : _useAnotherEmail,
                    child: const Text('Wrong email? Use another email'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
