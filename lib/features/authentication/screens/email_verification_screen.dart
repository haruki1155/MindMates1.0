import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/route_names.dart';
import '../../../services/firebase/firebase_error_message.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const _resendDelay = 60;
  bool _checking = false;
  bool _sending = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _message;
  bool _messageIsError = false;
  bool _emailSent = false;

  bool get _busy => _checking || _sending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resend();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
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
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(RouteNames.profileSetup, (route) => false);
      } else {
        setState(() {
          _messageIsError = false;
          _message =
              'Not verified yet. Open the link in your email, then return here.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
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
        _messageIsError = false;
        _emailSent = true;
        _message = 'Verification email sent. Check your inbox and spam folder.';
      });
      _startResendCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
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
                            checking: _checking,
                            busy: _busy,
                            resendLabel: resendLabel,
                            resendEnabled: !_busy && _resendSeconds == 0,
                            message: _message,
                            messageIsError: _messageIsError,
                            onCheck: _checkVerification,
                            onResend: _resend,
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
    required this.checking,
    required this.busy,
    required this.resendLabel,
    required this.resendEnabled,
    required this.message,
    required this.messageIsError,
    required this.onCheck,
    required this.onResend,
  });

  final String email;
  final bool emailSent;
  final bool checking;
  final bool busy;
  final String resendLabel;
  final bool resendEnabled;
  final String? message;
  final bool messageIsError;
  final VoidCallback onCheck;
  final VoidCallback onResend;

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
            _Status(message: message!, isError: messageIsError),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: busy ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_rounded, size: 19),
              label: Text(
                checking ? 'Checking status...' : 'I verified my email',
              ),
              style: _primaryButtonStyle,
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

class _Status extends StatelessWidget {
  const _Status({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final foreground = isError ? const Color(0xFF923B35) : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFEEEC) : const Color(0xFFEAF6F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: foreground,
          ),
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

final _primaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: AppColors.primary,
  foregroundColor: Colors.white,
  disabledBackgroundColor: AppColors.primary.withAlpha(110),
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
}
