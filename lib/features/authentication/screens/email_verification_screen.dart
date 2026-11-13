import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/profile_roles.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../auth_flow_routes.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  static const _resendDelay = 60;

  /// How long the green "Email verified" state stays visible before the
  /// screen moves on to profile setup.
  static const _verifiedHoldDuration = Duration(milliseconds: 1200);

  /// How often the screen checks in the background whether the email has
  /// been verified, so the button can turn green without a tap.
  static const _autoCheckInterval = Duration(seconds: 5);
  Timer? _autoCheckTimer;
  bool _autoChecking = false;

  /// True when verification was detected in the background; the button then
  /// shows "Continue" and waits for the user's tap.
  bool _autoVerified = false;
  bool _checking = false;
  bool _sending = false;
  bool _cancelling = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _message;
  _StatusTone _messageTone = _StatusTone.info;
  bool _emailSent = false;
  bool _verified = false;

  bool get _busy => _checking || _sending || _cancelling || _verified;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoCheckTimer = Timer.periodic(
      _autoCheckInterval,
      (_) => _checkSilently(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resend();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoCheckTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the mail app is the most likely moment the link was opened.
    if (state == AppLifecycleState.resumed) _checkSilently();
  }

  /// Background check: turns the screen green when the email is verified.
  /// Failures are ignored; the user can still tap the button to check.
  Future<void> _checkSilently() async {
    if (_autoChecking || _busy) return;
    _autoChecking = true;
    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.reloadCurrentUser();
      if (!mounted || _busy || !authProvider.currentUserEmailVerified) return;
      _autoCheckTimer?.cancel();
      setState(() {
        _verified = true;
        _autoVerified = true;
        _messageTone = _StatusTone.verified;
        _message = 'Email verified. Tap Continue to set up your profile.';
      });
    } catch (_) {
      // Silent by design: a manual check reports errors.
    } finally {
      _autoChecking = false;
    }
  }

  UserProvider? _userProviderOrNull() {
    try {
      return context.read<UserProvider>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isStudentAccount() async {
    final userProvider = _userProviderOrNull();
    if (userProvider == null) return false;
    try {
      final userId = context.read<AuthProvider>().userId;
      if (userProvider.user == null && userId != null) {
        await userProvider.loadProfile(userId);
      }
    } catch (_) {
      // Unknown role: treat as an employee signup.
    }
    return userProvider.user?.effectivePopulationRole == PopulationRole.student;
  }

  /// Where a freshly verified account goes next: the first-login gate for
  /// its profile, falling back to profile setup.
  Future<String> _nextRoute() async {
    final userProvider = _userProviderOrNull();
    if (userProvider == null) return RouteNames.profileSetup;
    try {
      final userId = context.read<AuthProvider>().userId;
      if (userId != null && await userProvider.loadProfile(userId)) {
        final user = userProvider.user;
        if (user != null) {
          return gateRouteForUser(user) ?? RouteNames.profileSetup;
        }
      }
    } catch (_) {
      // Fall through to profile setup.
    }
    return RouteNames.profileSetup;
  }

  Future<void> _continueToProfile() async {
    final route = await _nextRoute();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (route) => false);
  }

  Future<void> _checkVerification() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.reloadCurrentUser();
      if (!mounted) return;
      if (authProvider.currentUserEmailVerified) {
        setState(() {
          _verified = true;
          _checking = false;
          _messageTone = _StatusTone.verified;
          _message = 'Email verified. Continuing to your profile…';
        });
        await Future<void>.delayed(_verifiedHoldDuration);
        if (!mounted) return;
        final route = await _nextRoute();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(route, (route) => false);
      } else {
        setState(() {
          _messageTone = _StatusTone.notVerified;
          _message =
              'Not verified yet. Open the link in your email, then return here.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageTone = _StatusTone.error;
        _message = FirebaseErrorMessage.describe(
          error,
          fallback: 'Unable to check verification status. Try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || _resendSeconds > 0) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await context.read<AuthProvider>().sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _messageTone = _StatusTone.info;
        _emailSent = true;
        _message = 'Verification email sent. Check your inbox and spam folder.';
      });
      _startResendCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageTone = _StatusTone.error;
        _message = FirebaseErrorMessage.describe(
          error,
          fallback: 'Unable to resend the verification email right now.',
        );
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = _resendDelay);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  Future<void> _useAnotherEmail() async {
    final email =
        context.read<AuthProvider>().currentUserEmail ?? 'this email address';
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Use another email?'),
            content: Text(
              'This removes the unfinished registration for $email, including its reserved ID. You can then register again with the correct email.',
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
      // Resolve before cancelling: the cancel signs the account out.
      final auth = context.read<AuthProvider>();
      final wasStudent = await _isStudentAccount();
      await auth.cancelPendingRegistration();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        wasStudent ? RouteNames.studentActivation : RouteNames.signup,
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageTone = _StatusTone.error;
        _message =
            context.read<AuthProvider>().errorMessage ??
            'Unable to cancel this pending registration. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email =
        context.watch<AuthProvider>().currentUserEmail ?? 'your email address';
    final resendLabel = _resendSeconds > 0
        ? 'Resend in ${_resendSeconds}s'
        : _sending
        ? 'Sending email...'
        : 'Resend verification email';

    return Scaffold(
      backgroundColor: _Colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const _SoftCircle(top: -72, right: -68, size: 180),
            const _SoftCircle(bottom: -96, left: -72, size: 210, green: true),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  28,
                  24,
                  28 + MediaQuery.paddingOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 56,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Header(),
                          const SizedBox(height: 24),
                          _VerificationCard(
                            email: email,
                            emailSent: _emailSent,
                            verified: _verified,
                            checking: _checking,
                            busy: _busy,
                            resendLabel: resendLabel,
                            resendEnabled: !_busy && _resendSeconds == 0,
                            message: _message,
                            messageTone: _messageTone,
                            onCheck: _checkVerification,
                            continueMode: _autoVerified,
                            onContinue: _continueToProfile,
                            onResend: _resend,
                            onUseAnotherEmail: _useAnotherEmail,
                          ),
                          const SizedBox(height: 18),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: _Colors.muted,
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Your email is used only to secure and recover your account.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _Colors.muted,
                                    fontSize: 11,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _StepPill(label: 'STEP 1 OF 2'),
        SizedBox(height: 14),
        Text(
          'Verify your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _Colors.text,
            fontSize: 29,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'One quick check keeps your MindMate account secure.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _Colors.muted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.email,
    required this.emailSent,
    required this.verified,
    required this.checking,
    required this.busy,
    required this.resendLabel,
    required this.resendEnabled,
    required this.message,
    required this.messageTone,
    required this.onCheck,
    required this.continueMode,
    required this.onContinue,
    required this.onResend,
    required this.onUseAnotherEmail,
  });

  final String email;
  final bool emailSent;
  final bool verified;
  final bool checking;
  final bool busy;
  final String resendLabel;
  final bool resendEnabled;
  final String? message;
  final _StatusTone messageTone;
  final VoidCallback onCheck;

  /// Verification was detected in the background: the green button reads
  /// "Continue" and stays enabled until the user taps it.
  final bool continueMode;
  final VoidCallback onContinue;
  final VoidCallback onResend;
  final VoidCallback onUseAnotherEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _Colors.border),
        boxShadow: [
          BoxShadow(
            color: _Colors.shadow.withAlpha(18),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(22),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_unread_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            emailSent ? 'Check your inbox' : 'Sending your secure link',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _Colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: _Colors.emailSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.alternate_email_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: SelectableText(
                    email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _Colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _VerificationBadge(verified: verified),
          const SizedBox(height: 20),
          const _Instruction(
            number: '1',
            text: 'Open the email from MindMate.',
          ),
          const SizedBox(height: 12),
          const _Instruction(number: '2', text: 'Tap the verification link.'),
          const SizedBox(height: 12),
          const _Instruction(
            number: '3',
            text: 'Return here and continue your profile setup.',
          ),
          if (message != null) ...[
            const SizedBox(height: 18),
            _Status(message: message!, tone: messageTone),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: continueMode ? onContinue : (busy ? null : onCheck),
              icon: checking
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      continueMode
                          ? Icons.arrow_forward_rounded
                          : Icons.verified_rounded,
                      size: 19,
                    ),
              label: Text(
                continueMode
                    ? 'Continue'
                    : checking
                    ? 'Checking status...'
                    : 'I verified my email',
              ),
              style: _checkButtonStyle(verified: verified),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: resendEnabled ? onResend : null,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(resendLabel),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onUseAnotherEmail,
            child: const Text('Wrong email? Use another email'),
          ),
          const Text(
            'Can’t find it? Check your Spam or Promotions folder.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _Colors.muted,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: _Colors.accentSoft,
          child: Text(
            number,
            style: const TextStyle(
              color: _Colors.text,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _Colors.body,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

enum _StatusTone { info, error, notVerified, verified }

/// Always-visible verification status: red until the email is verified,
/// then green.
class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final (label, foreground, background, icon) = verified
        ? (
            'Email verified',
            _Colors.verified,
            const Color(0xFFE8F5E9),
            Icons.verified_rounded,
          )
        : (
            'Not yet verified',
            AppColors.error,
            const Color(0xFFFDECEA),
            Icons.cancel_outlined,
          );
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        key: const Key('email-verification-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.message, required this.tone});
  final String message;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, icon) = switch (tone) {
      _StatusTone.info => (
        AppColors.primary,
        const Color(0xFFEAF6F2),
        Icons.info_outline_rounded,
      ),
      _StatusTone.error => (
        const Color(0xFF923B35),
        const Color(0xFFFFEEEC),
        Icons.error_outline_rounded,
      ),
      _StatusTone.notVerified => (
        AppColors.error,
        const Color(0xFFFDECEA),
        Icons.cancel_outlined,
      ),
      _StatusTone.verified => (
        _Colors.verified,
        const Color(0xFFE8F5E9),
        Icons.check_circle_outline_rounded,
      ),
    };
    return Container(
      key: const Key('email-verification-status'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _Colors.accent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _Colors.text,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SoftCircle extends StatelessWidget {
  const _SoftCircle({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    this.green = false,
  });
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final bool green;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (green ? AppColors.primary : _Colors.accent).withAlpha(32),
          ),
        ),
      ),
    );
  }
}

/// "I verified my email" button: red until the email is verified, then green.
/// It stays green while disabled during the hold before profile setup.
ButtonStyle _checkButtonStyle({required bool verified}) =>
    FilledButton.styleFrom(
      backgroundColor: verified ? _Colors.verified : AppColors.error,
      foregroundColor: Colors.white,
      disabledBackgroundColor: verified
          ? _Colors.verified
          : AppColors.error.withAlpha(110),
      disabledForegroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
    );

class _Colors {
  const _Colors._();
  static const background = Color(0xFFFFFCF4);
  static const accent = Color(0xFFFFC944);
  static const accentSoft = Color(0xFFFFEAB0);
  static const emailSurface = Color(0xFFF1F8F5);
  static const border = Color(0xFFECE3D1);
  static const text = Color(0xFF17201D);
  static const body = Color(0xFF3F4D49);
  static const muted = Color(0xFF687571);
  static const shadow = Color(0xFF4B3A12);
  static const verified = Color(0xFF2E7D32);
}
