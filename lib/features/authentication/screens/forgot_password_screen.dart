import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _schoolIdController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _schoolIdController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final sent = await context
        .read<AuthProvider>()
        .sendPasswordResetForSchoolId(_schoolIdController.text);
    if (mounted && sent) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: _RecoveryColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const _SoftCircle(top: -78, right: -64, size: 184),
            const _SoftCircle(bottom: -100, left: -80, size: 220, green: true),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  24,
                  22,
                  24,
                  28 + MediaQuery.paddingOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 50,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton.filledTonal(
                              tooltip: 'Back to sign in',
                              onPressed: provider.isLoading
                                  ? null
                                  : () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _sent
                              ? _SuccessCard(
                                  schoolId: _schoolIdController.text.trim(),
                                  onBack: () => Navigator.pop(context),
                                )
                              : _RequestCard(
                                  formKey: _formKey,
                                  controller: _schoolIdController,
                                  loading: provider.isLoading,
                                  error: provider.errorMessage,
                                  onSubmit: _sendResetLink,
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

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.formKey,
    required this.controller,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool loading;
  final String? error;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) => _Card(
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RecoveryIcon(icon: Icons.lock_reset_rounded),
          const SizedBox(height: 20),
          const Text(
            'Reset your password',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _RecoveryColors.text,
              fontSize: 27,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter the School ID you use to sign in. We’ll send a secure reset link to your verified email address.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _RecoveryColors.muted,
              height: 1.45,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: controller,
            enabled: !loading,
            autofocus: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.username],
            onFieldSubmitted: (_) {
              if (!loading) onSubmit();
            },
            validator: (value) =>
                value?.trim().isEmpty == true ? 'School ID is required.' : null,
            decoration: InputDecoration(
              labelText: 'School ID',
              hintText: 'Enter your registered School ID',
              prefixIcon: const Icon(Icons.badge_outlined),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            _StatusMessage(message: error!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: loading ? null : onSubmit,
              icon: loading
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.mark_email_unread_rounded),
              label: Text(
                loading ? 'Sending reset link...' : 'Send reset link',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _RecoveryColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'For your privacy, the recovery email is never displayed here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _RecoveryColors.muted,
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.schoolId, required this.onBack});

  final String schoolId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _RecoveryIcon(icon: Icons.mark_email_read_rounded, success: true),
        const SizedBox(height: 20),
        const Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _RecoveryColors.text,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'A password reset link was sent for School ID $schoolId. Open the link, choose a new password, then return to sign in.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _RecoveryColors.muted,
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        const _Tip(
          icon: Icons.schedule_rounded,
          text: 'The link may take a minute to arrive.',
        ),
        const SizedBox(height: 10),
        const _Tip(
          icon: Icons.folder_open_rounded,
          text: 'Check Spam or Promotions if needed.',
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Back to sign in'),
            style: FilledButton.styleFrom(
              backgroundColor: _RecoveryColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 25),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _RecoveryColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x164B3A12),
          blurRadius: 28,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: child,
  );
}

class _RecoveryIcon extends StatelessWidget {
  const _RecoveryIcon({required this.icon, this.success = false});
  final IconData icon;
  final bool success;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        color: (success ? _RecoveryColors.softGreen : _RecoveryColors.primary)
            .withAlpha(45),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 40,
        color: success ? _RecoveryColors.success : _RecoveryColors.text,
      ),
    ),
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEEEC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFF923B35),
          size: 19,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF923B35),
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

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: _RecoveryColors.success),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: _RecoveryColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
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
  Widget build(BuildContext context) => Positioned(
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
          color: (green ? _RecoveryColors.softGreen : _RecoveryColors.primary)
              .withAlpha(40),
        ),
      ),
    ),
  );
}

class _RecoveryColors {
  const _RecoveryColors._();
  static const background = Color(0xFFFFFCF4);
  static const primary = Color(0xFFFFC944);
  static const softGreen = Color(0xFFBFE3D6);
  static const success = Color(0xFF23745D);
  static const border = Color(0xFFECE3D1);
  static const text = Color(0xFF17201D);
  static const muted = Color(0xFF687571);
}
