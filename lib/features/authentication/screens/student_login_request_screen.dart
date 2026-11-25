import 'package:flutter/material.dart';

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
  bool _sent = false;
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
      _sent = false;
    });
    try {
      await _repository.requestStudentLogin(_studentId.text);
      if (!mounted) return;
      setState(() => _sent = true);
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
      appBar: AppBar(title: const Text('Student login')),
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
                      'Enter your Student ID. We will email your login to the '
                      'email address the school has on file for you.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _studentId,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Student ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Enter your Student ID.'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _sending ? null : _submit,
                      child: _sending
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Email me my login'),
                    ),
                    if (_sent) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'If your Student ID is on the school roster with an '
                        'email address, we have sent your Student ID and a '
                        'temporary password to it. Check your inbox and spam '
                        'folder. The temporary password works for 24 hours. '
                        'If nothing arrives, visit the PACC office.',
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Back to sign in'),
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
