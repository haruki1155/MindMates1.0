import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';

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
    for (final c in [first, last, employee, email, position, password, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Request PAACC Portal Access')),
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
                      'Request PAACC Portal Access',
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
                          _role(AccessRole.portalStaff, 'PAACC Staff'),
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
    setState(() => busy = true);
    try {
      await widget.repository.registerStaff(
        email: email.text,
        password: password.text,
        firstName: first.text,
        lastName: last.text,
        employeeId: employee.text,
        position: position.text,
        requestedRole: requestedRole,
      );
      await widget.repository.signOut();
      if (!mounted) return;
      final roleLabel = requestedRole == AccessRole.counselor
          ? 'Counselor'
          : 'PAACC Staff';
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Access Request Submitted'),
          content: Text(
            'Your $roleLabel access request is pending administrator review. A verification email was sent to ${email.text.trim()}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Return to Sign In'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      final message = error is FirebaseException
          ? switch (error.code) {
              'email-already-in-use' => 'This email address is already in use.',
              'invalid-email' => 'Enter a valid institutional email address.',
              'weak-password' => 'Choose a stronger password.',
              'already-exists' =>
                'An account or pending request already exists for these details.',
              'permission-denied' =>
                'You are not allowed to submit this request.',
              _ =>
                'The access request could not be submitted. Please try again.',
            }
          : error is StateError
          ? error.message
          : 'The access request could not be submitted. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
