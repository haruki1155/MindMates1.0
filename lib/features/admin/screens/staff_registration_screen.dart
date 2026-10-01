import 'package:flutter/material.dart';
import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';

class StaffRegistrationScreen extends StatefulWidget {
  const StaffRegistrationScreen({super.key, required this.repository});
  final AdminPortalRepository repository;
  @override
  State<StaffRegistrationScreen> createState() =>
      _StaffRegistrationScreenState();
}

class _StaffRegistrationScreenState extends State<StaffRegistrationScreen> {
  final formKey = GlobalKey<FormState>();
  final first = TextEditingController(),
      last = TextEditingController(),
      employee = TextEditingController(),
      email = TextEditingController(),
      position = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  AccessRole requestedRole = AccessRole.portalStaff;
  bool busy = false, showPassword = false, showConfirm = false;
  @override
  void dispose() {
    for (final c in [
      first,
      last,
      employee,
      email,
      position,
      password,
      confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Request PACC Portal Access')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request PACC Portal Access',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Staff accounts require administrator approval before portal access is enabled.',
                    ),
                    const SizedBox(height: 26),
                    _section('Personal information'),
                    _columns(
                      _field(first, 'First name'),
                      _field(last, 'Last name'),
                    ),
                    const SizedBox(height: 16),
                    _section('Employment information'),
                    _columns(
                      _field(employee, 'Employee ID'),
                      _field(position, 'Position / Designation'),
                    ),
                    const SizedBox(height: 16),
                    _section('Account information'),
                    _field(email, 'Institutional email', emailField: true),
                    _columns(
                      _passwordField(
                        password,
                        'Password',
                        () => setState(() => showPassword = !showPassword),
                        showPassword,
                      ),
                      _passwordField(
                        confirm,
                        'Confirm password',
                        () => setState(() => showConfirm = !showConfirm),
                        showConfirm,
                      ),
                    ),
                    const Text(
                      'Use at least 8 characters with an uppercase letter and a number.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 22),
                    _section('Requested portal role'),
                    RadioGroup<AccessRole>(
                      groupValue: requestedRole,
                      onChanged: (role) {
                        if (role != null) {
                          setState(() => requestedRole = role);
                        }
                      },
                      child: Column(
                        children: [
                          _role(AccessRole.portalStaff, 'PACC Staff'),
                          const SizedBox(height: 10),
                          _role(AccessRole.counselor, 'Counselor'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Counselor access includes sensitive student information and requires administrator approval.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy ? null : submit,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          busy
                              ? 'Submitting request…'
                              : 'Submit Access Request',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Access is granted only after administrator review.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
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
  );
  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );
  Widget _columns(Widget a, Widget b) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < 520
        ? Column(children: [a, const SizedBox(height: 10), b])
        : Row(
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ),
  );
  Widget _field(
    TextEditingController c,
    String label, {
    bool emailField = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: c,
      keyboardType: emailField ? TextInputType.emailAddress : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return 'Required';
        if (emailField && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
          return 'Enter a valid email address';
        }
        if (label == 'Employee ID' && (t.length < 3 || t.length > 40)) {
          return 'Enter a valid employee ID';
        }
        return null;
      },
    ),
  );
  Widget _passwordField(
    TextEditingController c,
    String label,
    VoidCallback toggle,
    bool visible,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: c,
      obscureText: !visible,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: visible ? 'Hide password' : 'Show password',
          onPressed: toggle,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: (v) {
        final t = v ?? '';
        if (t.isEmpty) return 'Required';
        if (label == 'Password' &&
            (t.length < 8 ||
                !RegExp(r'[A-Z]').hasMatch(t) ||
                !RegExp(r'\d').hasMatch(t))) {
          return 'Use 8+ characters, uppercase, and a number';
        }
        if (label == 'Confirm password' && t != password.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    ),
  );
  Widget _role(AccessRole role, String title) => InkWell(
    onTap: () => setState(() => requestedRole = role),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: requestedRole == role ? const Color(0xFFFFF3B0) : null,
        border: Border.all(
          color: requestedRole == role
              ? const Color(0xFFC9A400)
              : Colors.black26,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Radio<AccessRole>(value: role),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final normalizedEmail = email.text.trim().toLowerCase();
    final roleLabel = requestedRole == AccessRole.counselor
        ? 'Counselor'
        : 'PACC Staff';
    final confirmed = await _confirmRegistrationEmail(
      normalizedEmail: normalizedEmail,
      roleLabel: roleLabel,
    );
    if (!confirmed || !mounted) return;
    email.text = normalizedEmail;
    setState(() => busy = true);
    try {
      final submission = await widget.repository.registerStaff(
        email: normalizedEmail,
        password: password.text,
        firstName: first.text,
        lastName: last.text,
        employeeId: employee.text,
        position: position.text,
        requestedRole: requestedRole,
      );
      if (!mounted) return;
      var cancellingPendingRegistration = false;
      final outcome = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Verify Your Email'),
            content: Text(
              'Your $roleLabel access request has been created.\n\n'
              '${submission.verificationSent ? 'We sent a verification email to' : 'The request was saved, but a verification email could not be sent to'} '
              '${email.text.trim()}.\n\n'
              'After verification, sign in again to view the status of your request.\n\n'
              'Reference: ${submission.reference ?? 'Pending'}\n'
              'Verify your email address before your request can be reviewed by an administrator.',
            ),
            actions: [
              TextButton(
                onPressed: cancellingPendingRegistration
                    ? null
                    : () async {
                        await widget.repository.signOut();
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, false);
                        }
                      },
                child: const Text('Return to Sign In'),
              ),
              FilledButton(
                onPressed: cancellingPendingRegistration
                    ? null
                    : () async {
                        final confirmed =
                            await showDialog<bool>(
                              context: dialogContext,
                              builder: (confirmationContext) => AlertDialog(
                                title: const Text('Use another email?'),
                                content: const Text(
                                  'This removes the unfinished access request and releases its employee ID reservation.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                      confirmationContext,
                                      false,
                                    ),
                                    child: const Text('Keep this email'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(
                                      confirmationContext,
                                      true,
                                    ),
                                    child: const Text('Use another email'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (!confirmed) return;
                        setDialogState(
                          () => cancellingPendingRegistration = true,
                        );
                        try {
                          await widget.repository.cancelPendingRegistration();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(
                              () => cancellingPendingRegistration = false,
                            );
                          }
                          if (!mounted || !dialogContext.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                FirebaseErrorMessage.describe(
                                  error,
                                  fallback:
                                      'Unable to cancel this pending registration. Please try again.',
                                ),
                              ),
                            ),
                          );
                        }
                      },
                child: Text(
                  cancellingPendingRegistration
                      ? 'Cancelling...'
                      : 'Use Another Email',
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (outcome == true) {
        _clearForm();
      } else if (outcome == false) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) return;
      final message = FirebaseErrorMessage.describe(
        error,
        fallback:
            'The access request could not be submitted. Please check your details and try again.',
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Request not submitted'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirmRegistrationEmail({
    required String normalizedEmail,
    required String roleLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirm your email'),
            content: Text(
              'A verification link will be sent to:\n\n$normalizedEmail\n\nYou are requesting $roleLabel access.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Edit Email'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm & Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _clearForm() {
    for (final controller in [
      first,
      last,
      employee,
      email,
      position,
      password,
      confirm,
    ]) {
      controller.clear();
    }
    setState(() => requestedRole = AccessRole.portalStaff);
  }
}
