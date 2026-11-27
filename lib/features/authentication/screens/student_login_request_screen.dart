import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../repositories/student_roster_repository.dart';

/// Students ask for their login here. The answer is always the same message:
/// it never says whether the Student ID exists or which email it was sent to.
class StudentLoginRequestScreen extends StatefulWidget {
  const StudentLoginRequestScreen({super.key, this.repository});

  final StudentRosterRepository? repository;

  @override
  State<StudentLoginRequestScreen> createState() =>
      _StudentLoginRequestScreenState();
}

class _StudentLoginRequestScreenState extends State<StudentLoginRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _studentId = TextEditingController();
  late final StudentRosterRepository _repository =
      widget.repository ?? StudentRosterRepository();
  bool _sending = false;
  StudentLoginRequestOutcome? _outcome;
  String? _error;

  @override
  void dispose() {
    _studentId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
      _outcome = null;
    });
    try {
      final outcome = await _repository.requestStudentLogin(_studentId.text);
      if (!mounted) return;
      setState(() => _outcome = outcome);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'We could not send your login right now. Please try again later.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          'Student Login',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDDE7E3)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.mark_email_unread_outlined,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Get your student login',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter your Student ID to receive your temporary password by email.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _studentId,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Student ID',
                          hintText: 'e.g. 2021-00123',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFD0DDD8),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFD0DDD8),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.6,
                            ),
                          ),
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter your Student ID.'
                            : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _sending ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Email me my login'),
                      ),
                      if (_outcome == StudentLoginRequestOutcome.sent) ...[
                        const SizedBox(height: 18),
                        _ConfirmationCallout(),
                      ],
                      if (_outcome ==
                          StudentLoginRequestOutcome.alreadyActivated) ...[
                        const SizedBox(height: 18),
                        _AlreadyActivatedCallout(),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorCallout(message: _error!),
                      ],
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Back to sign in'),
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

class _ConfirmationCallout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('login-request-confirmation'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Login details sent',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'If your Student ID is on the school roster, we emailed your temporary password.',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 12),
          _TipRow(
            icon: Icons.inbox_outlined,
            text: 'Check your inbox and spam folder.',
          ),
          SizedBox(height: 6),
          _TipRow(
            icon: Icons.schedule_outlined,
            text: 'Temporary password expires in 24 hours.',
          ),
          SizedBox(height: 6),
          _TipRow(
            icon: Icons.support_agent_outlined,
            text: 'Need help? Visit the PACC office.',
          ),
        ],
      ),
    );
  }
}

class _AlreadyActivatedCallout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('login-request-already-activated'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.gpp_maybe_outlined,
                color: AppColors.error,
                size: 22,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Account already activated',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'This Student ID already has an active MindMate account.',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 12),
          _TipRow(
            icon: Icons.login_rounded,
            iconColor: AppColors.error,
            text: 'Already yours? Go back to sign in or tap Forgot Password.',
          ),
          SizedBox(height: 6),
          _TipRow(
            icon: Icons.support_agent_outlined,
            iconColor: AppColors.error,
            text:
                'If this is your Student ID and someone else used it, visit the PACC office right away to raise and recover your account.',
          ),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({
    required this.icon,
    required this.text,
    this.iconColor = AppColors.primary,
  });

  final IconData icon;
  final String text;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorCallout extends StatelessWidget {
  const _ErrorCallout({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
