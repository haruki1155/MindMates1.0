import 'package:flutter/material.dart';

import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../theme/admin_theme.dart';

class CreateStaffAccountPage extends StatefulWidget {
  const CreateStaffAccountPage({
    super.key,
    required this.repository,
    this.onOpenUserManagement,
  });

  final AdminPortalRepository repository;
  final VoidCallback? onOpenUserManagement;

  @override
  State<CreateStaffAccountPage> createState() => _CreateStaffAccountPageState();
}

class _CreateStaffAccountPageState extends State<CreateStaffAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  AccessRole _selectedRole = AccessRole.counselor;
  bool _submitting = false;
  String? _errorMessage;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Enter the email address for this account.';
    }
    if (trimmed.length > 254 || !_emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final created = await widget.repository.createStaffAccountByAdmin(
        email: _emailController.text.trim(),
        role: _selectedRole,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      final action = await showDialog<_CreatedDialogAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AccountCreatedDialog(
          created: created,
          canOpenUsers: widget.onOpenUserManagement != null,
        ),
      );
      if (!mounted) return;
      _emailController.clear();
      _firstNameController.clear();
      _lastNameController.clear();
      setState(() => _errorMessage = null);
      if (action == _CreatedDialogAction.viewUsers) {
        widget.onOpenUserManagement?.call();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = FirebaseErrorMessage.describe(
          error,
          fallback:
              'Unable to create the account right now. Check your details and try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isSuperAdmin) {
      return const Center(
        child: Text('Super-administrator access is required.'),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
        28,
        MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Provision a PACC Counselor or Portal Staff account. '
                      'An auto-generated temporary password will be emailed '
                      'directly to the recipient.',
                      style: TextStyle(color: AdminColors.muted, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '1. Choose account role',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 520;
                        final cards = [
                          _RoleOptionCard(
                            key: const Key('role-card-counselor'),
                            role: AccessRole.counselor,
                            title: 'Counselor',
                            description:
                                'Handles student inquiries, counseling appointments, '
                                'clinical cases, and assessments.',
                            icon: Icons.psychology_alt_outlined,
                            selected: _selectedRole == AccessRole.counselor,
                            enabled: !_submitting,
                            onTap: () => setState(
                              () => _selectedRole = AccessRole.counselor,
                            ),
                          ),
                          _RoleOptionCard(
                            key: const Key('role-card-staff'),
                            role: AccessRole.portalStaff,
                            title: 'Portal Staff',
                            description:
                                'Manages announcements, operational schedules, '
                                'and monitoring workflows.',
                            icon: Icons.badge_outlined,
                            selected: _selectedRole == AccessRole.portalStaff,
                            enabled: !_submitting,
                            onTap: () => setState(
                              () => _selectedRole = AccessRole.portalStaff,
                            ),
                          ),
                        ];
                        if (stacked) {
                          return Column(
                            children: [
                              cards[0],
                              const SizedBox(height: 10),
                              cards[1],
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      '2. Account email & optional details',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('create-account-email'),
                      controller: _emailController,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        hintText: 'counselor@school.edu.ph',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final firstNameField = TextFormField(
                          controller: _firstNameController,
                          enabled: !_submitting,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: 'First name (optional)',
                            counterText: '',
                          ),
                        );
                        final lastNameField = TextFormField(
                          controller: _lastNameController,
                          enabled: !_submitting,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: 'Last name (optional)',
                            counterText: '',
                          ),
                        );
                        if (constraints.maxWidth < 480) {
                          return Column(
                            children: [
                              firstNameField,
                              const SizedBox(height: 12),
                              lastNameField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: firstNameField),
                            const SizedBox(width: 12),
                            Expanded(child: lastNameField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.border),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_reset_outlined,
                            size: 20,
                            color: AdminColors.accentStrong,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No manual password is needed. MindMate generates '
                              'a secure temporary password, emails it to the '
                              'recipient, and requires them to set their own '
                              'password upon first sign-in.',
                              style: TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
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
                      child: FilledButton.icon(
                        key: const Key('submit-create-account'),
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1_outlined),
                        label: Text(
                          _submitting
                              ? 'Creating account & sending email…'
                              : 'Create Account',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleOptionCard extends StatelessWidget {
  const _RoleOptionCard({
    super.key,
    required this.role,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AccessRole role;
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AdminColors.accentSoft : AdminColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AdminColors.accentStrong : AdminColors.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? AdminColors.ink : AdminColors.muted,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: selected
                            ? AdminColors.accentStrong
                            : AdminColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _CreatedDialogAction { createAnother, viewUsers }

class _AccountCreatedDialog extends StatelessWidget {
  const _AccountCreatedDialog({
    required this.created,
    required this.canOpenUsers,
  });

  final CreatedStaffAccount created;
  final bool canOpenUsers;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.mark_email_read_outlined, color: AdminColors.greenFg),
        SizedBox(width: 10),
        Expanded(child: Text('Account Created')),
      ],
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'An email has been sent to ${created.email} containing the '
            "account's temporary password.",
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryLine('Email', created.email),
                const SizedBox(height: 4),
                _summaryLine('Role', created.roleLabel),
                const SizedBox(height: 4),
                _summaryLine(
                  'First sign-in',
                  'Password change required upon login',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Let the recipient know to check their inbox (and spam folder), '
            'sign in using the temporary password, and set their private '
            'password right away.',
            style: TextStyle(color: AdminColors.muted, fontSize: 13),
          ),
        ],
      ),
    ),
    actions: [
      if (canOpenUsers)
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(_CreatedDialogAction.viewUsers),
          child: const Text('View User Management'),
        ),
      FilledButton(
        onPressed: () =>
            Navigator.of(context).pop(_CreatedDialogAction.createAnother),
        child: const Text('Create Another Account'),
      ),
    ],
  );

  Widget _summaryLine(String label, String value) => Text.rich(
    TextSpan(
      style: const TextStyle(fontSize: 13),
      children: [
        TextSpan(
          text: '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(text: value),
      ],
    ),
  );
}
