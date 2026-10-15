import 'package:flutter/material.dart';

/// Keeps the final V4 save behind an explicit user action.
class AssessmentSubmissionReviewScreen extends StatefulWidget {
  const AssessmentSubmissionReviewScreen({super.key});

  @override
  State<AssessmentSubmissionReviewScreen> createState() =>
      _AssessmentSubmissionReviewScreenState();
}

class _AssessmentSubmissionReviewScreenState
    extends State<AssessmentSubmissionReviewScreen> {
  bool _submitting = false;

  void _confirm() {
    if (_submitting) return;
    setState(() => _submitting = true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(title: const Text('Review assessment')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ready to submit?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Your answers are ready for the secure assessment save. Your final summary will appear only after you choose Submit assessment.',
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Back to assessment'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _confirm,
                child: const Text('Submit assessment'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
