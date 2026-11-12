import 'package:flutter/material.dart';

import '../data/quick_assessment_questions.dart';
import '../data/quick_indicator_copy.dart';
import '../models/quick_assessment_models.dart';
import '../../student_assessment/models/assessment_interpretation_models.dart';
import 'quick_result_visuals.dart';
import 'quick_assessment_widgets.dart';

class QuickResultExplanations extends StatelessWidget {
  const QuickResultExplanations({super.key, required this.result});

  final QuickAssessmentResult result;

  @override
  Widget build(BuildContext context) {
    final domains = result.interpretation.domainResults;
    final good = domains.where((d) => d.score <= 40).toList();
    final closer = domains.where((d) => d.score > 40).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (good.isNotEmpty) ...[
          const Text(
            "What's going well",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final domain in good)
            _IndicatorExplanation(result: result, domain: domain),
        ],
        if (closer.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Worth a closer look',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final domain in closer)
            _IndicatorExplanation(result: result, domain: domain),
        ],
      ],
    );
  }
}

class _IndicatorExplanation extends StatelessWidget {
  const _IndicatorExplanation({required this.result, required this.domain});

  final QuickAssessmentResult result;
  final AssessmentDomainResult domain;

  @override
  Widget build(BuildContext context) {
    final question = QuickAssessmentQuestions.questions
        .where(
          (q) => QuickIndicatorCopy.forQuestionId(q.id)?.name == domain.domain,
        )
        .firstOrNull;
    final response = result.responses
        .where((r) => r.questionId == question?.id)
        .firstOrNull;
    final copy = question == null
        ? null
        : QuickIndicatorCopy.forQuestionId(question.id);
    final option = question?.options
        .where((o) => o.id == response?.optionId)
        .firstOrNull;
    final answer =
        result.interpretation.questionSetVersion == 'quick_v3' && option != null
        ? option.label
        : 'Saved response';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: QuickAssessmentPalette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: QuickAssessmentPalette.softBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QuickIndicatorRow(
              key: ValueKey('quick-indicator-${domain.domain}'),
              indicator: domain,
            ),
            const SizedBox(height: 8),
            Text(
              'You answered: $answer',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            if (copy != null)
              Text(
                domain.score <= 40 ? copy.goingWell : copy.closerLook,
                style: const TextStyle(fontSize: 13),
              ),
            if (copy != null) ...[
              const SizedBox(height: 5),
              Text(
                'Why it matters: ${copy.purpose}',
                style: const TextStyle(
                  fontSize: 12,
                  color: QuickAssessmentPalette.secondaryText,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
