import 'package:flutter/material.dart';

import '../models/intervention_models.dart';

/// Session-only feedback. Nothing in this screen writes to Firebase or analytics.
class InterventionFeedbackScreen extends StatefulWidget {
  const InterventionFeedbackScreen({super.key});

  @override
  State<InterventionFeedbackScreen> createState() =>
      _InterventionFeedbackScreenState();
}

class _InterventionFeedbackScreenState
    extends State<InterventionFeedbackScreen> {
  InterventionFeedbackChoice? _choice;
  final _reflection = TextEditingController();

  @override
  void dispose() {
    _reflection.dispose();
    super.dispose();
  }

  void _submit() {
    final choice = _choice;
    if (choice == null) return;
    final text = _reflection.text.trim();
    Navigator.of(context).pop(
      InterventionFeedback(
        choice: choice,
        reflection: text.isEmpty ? null : text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activity check-in')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Did this activity help you feel better?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          for (final item in const [
            (InterventionFeedbackChoice.helped, 'Yes, it helped'),
            (InterventionFeedbackChoice.neutral, 'Neutral / Not sure'),
            (InterventionFeedbackChoice.didNotHelp, "No, it didn't help"),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChoiceChip(
                label: Text(item.$2),
                selected: _choice == item.$1,
                onSelected: (_) => setState(() => _choice = item.$1),
              ),
            ),
          TextField(
            controller: _reflection,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'How are you feeling afterward? (optional)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _choice == null ? null : _submit,
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip feedback'),
          ),
        ],
      ),
    ),
  );
}
