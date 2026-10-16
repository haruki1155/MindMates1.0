import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/assessment_provider.dart';
import '../models/student_assessment_models.dart';
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
  Widget build(BuildContext context) {
    AssessmentProvider? provider;
    try {
      provider = context.watch<AssessmentProvider>();
    } on ProviderNotFoundException {
      // A lightweight fallback keeps isolated presentation tests independent
      // while production always obtains counts from the active session.
    }
    final questions =
        provider?.studentQuestions ?? const <StudentAssessmentQuestion>[];
    final answers =
        provider?.studentAnswers ?? const <StudentAssessmentAnswer>[];
    final domains = <String, List<StudentAssessmentQuestion>>{};
    for (final question in questions) {
      final domainId = question.v4DomainId;
      if (domainId != null) {
        domains.putIfAbsent(domainId, () => []).add(question);
      }
    }
    final answeredIds = answers.map((answer) => answer.questionId).toSet();
    final completedDomains = domains.values
        .where(
          (questionsInDomain) =>
              questionsInDomain.length == 10 &&
              questionsInDomain.every(
                (question) => answeredIds.contains(question.id),
              ),
        )
        .length;
    final readyToSubmit =
        questions.isNotEmpty &&
        answers.length == questions.length &&
        completedDomains == domains.length;
    return PopScope(
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
                              'Completion summary',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              provider == null
                                  ? 'Your final summary will appear only after you choose Submit assessment.'
                                  : '${provider.activeAssessmentTitle} • ${answers.length} of ${questions.length} answers recorded • $completedDomains of ${domains.length} categories complete • ${readyToSubmit ? 'Ready for final submission' : 'Not ready for final submission'}.',
                              style: const TextStyle(height: 1.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (domains.isNotEmpty) ...[
                        Text(
                          'Category overview',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        for (final entry in domains.entries) ...[
                          AssessmentSurfaceCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.checklist_rounded,
                                  color: AssessmentPresentation.accent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _domainLabel(entry.value.first),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${entry.value.where((question) => answeredIds.contains(question.id)).length}/10',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                      AssessmentSurfaceCard(
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text(
                            'About this assessment',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'This MindMate V4 well-being reflection contains 50 questions across five areas. Your answers are evaluated using the configured V4 process, with each completed area reviewed by the server before any optional activity is suggested. This supports reflection and is not a diagnosis. Responses are saved only after you choose Submit assessment.',
                                style: TextStyle(height: 1.5),
                              ),
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
                        style: AssessmentPresentation.filledButtonStyle(
                          context,
                        ),
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

  String _domainLabel(StudentAssessmentQuestion question) =>
      switch (question.v4DomainId) {
        'academic' => 'Academic',
        'financial' => 'Financial',
        'socialAdjustment' => 'Social Adjustment',
        'sleepRest' => 'Sleep and Rest',
        'emotionalWellBeing' => 'Emotional Well-Being',
        _ => question.section.label,
      };
}
