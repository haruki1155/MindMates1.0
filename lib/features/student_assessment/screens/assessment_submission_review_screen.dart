import 'package:flutter/material.dart';

import '../widgets/assessment_presentation.dart';

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
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Review assessment'),
        backgroundColor: AssessmentPresentation.softAccent(context),
        foregroundColor: AssessmentPresentation.onSoftAccent(context),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AssessmentSurfaceCard(
                      color: AssessmentPresentation.softAccent(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AssessmentStatusPill(label: 'Final step'),
                          const SizedBox(height: 14),
                          Text(
                            'Ready to submit?',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Your answers are ready for the secure assessment save. Your final summary will appear only after you choose Submit assessment.',
                            style: TextStyle(height: 1.5),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      style: AssessmentPresentation.outlinedButtonStyle(
                        context,
                      ),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Back to assessment'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: AssessmentPresentation.filledButtonStyle(context),
                      onPressed: _submitting ? null : _confirm,
                      child: const Text('Submit assessment'),
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
