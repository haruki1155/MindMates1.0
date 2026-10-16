import 'package:flutter/material.dart';

import '../models/intervention_models.dart';
import '../widgets/assessment_presentation.dart';

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
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 40)
                  .clamp(0, double.infinity)
                  .toDouble(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A moment to reflect',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                AssessmentSurfaceCard(
                  color: AssessmentPresentation.softPrimary(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.favorite_outline_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 30,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Did this activity help you feel better?',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your feedback stays with this assessment session.',
                        style: TextStyle(
                          color: AssessmentPresentation.muted(context),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                for (final item in const [
                  (InterventionFeedbackChoice.helped, 'Yes, it helped'),
                  (InterventionFeedbackChoice.neutral, 'Neutral / Not sure'),
                  (InterventionFeedbackChoice.didNotHelp, "No, it didn't help"),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FeedbackChoiceTile(
                      label: item.$2,
                      selected: _choice == item.$1,
                      onTap: () => setState(() => _choice = item.$1),
                    ),
                  ),
                const SizedBox(height: 6),
                TextField(
                  controller: _reflection,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'How are you feeling afterward? (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _choice == null ? null : _submit,
                  child: const Text('Continue assessment'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Skip feedback'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FeedbackChoiceTile extends StatelessWidget {
  const _FeedbackChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        borderRadius: AssessmentPresentation.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AssessmentPresentation.cardRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: AssessmentPresentation.cardRadius,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
