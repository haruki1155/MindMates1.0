import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/student_roster_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/route_names.dart';

/// Two-step activation of a roster record: identity (Student No., one-time
/// activation code, date of birth), then the account email and password.
class StudentActivationScreen extends StatefulWidget {
  const StudentActivationScreen({super.key});

  @override
  State<StudentActivationScreen> createState() =>
      _StudentActivationScreenState();
}

class _StudentActivationScreenState extends State<StudentActivationScreen> {
  static const _mismatchCopy = "Those details don't match our records.";
  static const _expiredCopy =
      'This activation code has expired. Ask the PACC office for a new one.';
  static const _alreadyActivatedCopy =
      'This account is already activated. Sign in or use Forgot password.';
  static const _emailInUseCopy = 'This email address is already registered.';
  static const _unknownCopy =
      "We couldn't complete activation right now. Check your connection and try again.";
  static const _signInFailedCopy =
      'Your account was activated, but we could not sign you in. Go back to sign in.';

  final _identityFormKey = GlobalKey<FormState>();
  final _accountFormKey = GlobalKey<FormState>();
  final _studentNoController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  DateTime? _dateOfBirth;
  int _step = 0;
  String? _error;
  bool _alreadyActivated = false;

  @override
  void initState() {
    super.initState();
    _studentNoController.addListener(_refresh);
    _codeController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _studentNoController.dispose();
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _identityComplete =>
      _studentNoController.text.trim().isNotEmpty &&
      _codeController.text.trim().isNotEmpty &&
      _dateOfBirth != null;

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDateOfBirth() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(today.year - 120),
      lastDate: today,
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  void _continue() {
    if (!_identityComplete) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _step = 1;
      _error = null;
      _alreadyActivated = false;
    });
  }

  Future<void> _activate() async {
    FocusScope.of(context).unfocus();
    if (!(_accountFormKey.currentState?.validate() ?? false)) return;
    final dob = _dateOfBirth;
    if (dob == null) return;

    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    setState(() {
      _error = null;
      _alreadyActivated = false;
    });
    try {
      await auth.activateStudentAccount(
        studentNo: _studentNoController.text.trim(),
        activationCode: _codeController.text.trim(),
        dateOfBirthKey: _dateKey(dob),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on StudentActivationException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _copyFor(error);
        _alreadyActivated =
            error.reason == StudentActivationFailure.alreadyActivated;
      });
      return;
    } on StudentActivationSignInException {
      if (!mounted) return;
      setState(() {
        _error = _signInFailedCopy;
        _alreadyActivated = true;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _unknownCopy);
      return;
    }
    if (!mounted) return;
    navigator.pushNamedAndRemoveUntil(
      RouteNames.emailVerification,
      (route) => false,
    );
  }

  String _copyFor(StudentActivationException error) {
    switch (error.reason) {
      case StudentActivationFailure.mismatch:
        return _mismatchCopy;
      case StudentActivationFailure.expired:
        return _expiredCopy;
      case StudentActivationFailure.alreadyActivated:
        return _alreadyActivatedCopy;
      case StudentActivationFailure.emailInUse:
        return _emailInUseCopy;
      case StudentActivationFailure.invalidInput:
        final message = error.message?.trim();
        return message == null || message.isEmpty ? _unknownCopy : message;
      case StudentActivationFailure.unknown:
        return _unknownCopy;
    }
  }

  void _goToSignIn() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
  }

  String? _required(String? value, String field) =>
      value == null || value.trim().isEmpty ? '$field is required' : null;

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;
    return Scaffold(
      backgroundColor: _ActivationColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _ActivationColors.text,
        title: const Text(
          'Activate student account',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                decoration: BoxDecoration(
                  color: _ActivationColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _ActivationColors.border),
                ),
                child: _step == 0
                    ? _buildIdentityStep()
                    : _buildAccountStep(isLoading),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityStep() {
    final dob = _dateOfBirth;
    return Form(
      key: _identityFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(
            step: 'Step 1 of 2',
            text: 'Enter the details from your activation slip.',
          ),
          const SizedBox(height: 16),
          _ActivationField(
            controller: _studentNoController,
            label: 'Student No.',
            icon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          _ActivationField(
            controller: _codeController,
            label: 'Activation code',
            hint: 'XXXXX-XXXXX',
            helper: 'Your activation code is on the slip from the PACC office.',
            icon: Icons.vpn_key_outlined,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_UpperCaseFormatter()],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickDateOfBirth,
            child: InputDecorator(
              decoration: _decoration(
                label: 'Date of Birth',
                icon: Icons.cake_outlined,
              ),
              child: Text(
                dob == null ? 'Select date' : _dateKey(dob),
                style: const TextStyle(
                  color: _ActivationColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _PrimaryButton(
            label: 'Continue',
            onPressed: _identityComplete ? _continue : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountStep(bool isLoading) {
    return Form(
      key: _accountFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(
            step: 'Step 2 of 2',
            text: 'Choose the email and password for your account.',
          ),
          const SizedBox(height: 16),
          _ActivationField(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Email address is required';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _ActivationField(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: true,
            textInputAction: TextInputAction.next,
            validator: (value) {
              final requiredError = _required(value, 'Password');
              if (requiredError != null) return requiredError;
              if (value!.length < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _ActivationField(
            controller: _confirmController,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            obscureText: true,
            textInputAction: TextInputAction.done,
            validator: (value) {
              final requiredError = _required(value, 'Confirm password');
              if (requiredError != null) return requiredError;
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('activation-error'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: _ActivationColors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  if (_alreadyActivated)
                    TextButton(
                      onPressed: _goToSignIn,
                      child: const Text('Sign in'),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          _PrimaryButton(
            label: 'Activate account',
            loading: isLoading,
            onPressed: isLoading ? null : _activate,
          ),
          TextButton(
            onPressed: isLoading
                ? null
                : () => setState(() {
                    _step = 0;
                    _error = null;
                    _alreadyActivated = false;
                  }),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

InputDecoration _decoration({
  required String label,
  IconData? icon,
  String? hint,
  String? helper,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 2,
    labelStyle: const TextStyle(
      color: _ActivationColors.mutedText,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
    floatingLabelStyle: const TextStyle(
      color: _ActivationColors.text,
      fontSize: 13,
      fontWeight: FontWeight.w800,
    ),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 20, color: _ActivationColors.text),
    border: border(_ActivationColors.fieldBorder),
    enabledBorder: border(_ActivationColors.fieldBorder),
    focusedBorder: border(_ActivationColors.primary, 1.4),
    errorBorder: border(_ActivationColors.error),
    focusedErrorBorder: border(_ActivationColors.error, 1.4),
  );
}

class _ActivationField extends StatelessWidget {
  const _ActivationField({
    required this.controller,
    required this.label,
    this.icon,
    this.hint,
    this.helper,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.obscureText = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      validator: validator,
      style: const TextStyle(
        color: _ActivationColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: _decoration(
        label: label,
        icon: icon,
        hint: hint,
        helper: helper,
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.text});

  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step,
          style: const TextStyle(
            color: _ActivationColors.mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: const TextStyle(
            color: _ActivationColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _ActivationColors.primary,
          foregroundColor: _ActivationColors.text,
          disabledBackgroundColor: _ActivationColors.primary.withAlpha(90),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        child: loading
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _ActivationColors.text,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _ActivationColors {
  const _ActivationColors._();

  static const background = Color(0xFFFFFCF4);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFFFFC944);
  static const border = Color(0xFFF0E5C8);
  static const fieldBorder = Color(0xFFE7DDC9);
  static const text = Color(0xFF17201D);
  static const mutedText = Color(0xFF66736F);
  static const error = Color(0xFFB3261E);
}
