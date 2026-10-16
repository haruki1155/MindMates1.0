import 'package:flutter/material.dart';

import '../models/intervention_models.dart';
import '../widgets/assessment_presentation.dart';

class InterventionGroundingScreen extends StatefulWidget {
  const InterventionGroundingScreen({super.key});

  @override
  State<InterventionGroundingScreen> createState() =>
      _InterventionGroundingScreenState();
}

class _InterventionGroundingScreenState
    extends State<InterventionGroundingScreen> {
  static const _steps = [
    'Notice five things you can see.',
    'Notice four things you can feel.',
    'Notice three things you can hear.',
    'Notice two things you can smell.',
    'Notice one thing you can taste, or another comfortable sensory detail.',
  ];

  int _index = 0;

  void _finish(InterventionOutcome value) => Navigator.pop(context, value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grounding exercise')),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Five senses reset',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      AssessmentStatusPill(label: 'Step ${_index + 1} of 5'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: (_index + 1) / _steps.length,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(999),
                    color: AssessmentPresentation.accent,
                    backgroundColor: AssessmentPresentation.softAccent(context),
                  ),
                  const SizedBox(height: 24),
                  AssessmentSurfaceCard(
                    color: AssessmentPresentation.softAccent(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.spa_outlined,
                          color: AssessmentPresentation.accent,
                          size: 30,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _steps[_index],
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Take your time. There is no need to rush through this step.',
                          style: TextStyle(
                            color: AssessmentPresentation.muted(context),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 12,
                    spacing: 12,
                    children: [
                      OutlinedButton.icon(
                        style: AssessmentPresentation.outlinedButtonStyle(
                          context,
                        ),
                        onPressed: _index == 0
                            ? null
                            : () => setState(() => _index--),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Previous'),
                      ),
                      FilledButton.icon(
                        style: AssessmentPresentation.filledButtonStyle(
                          context,
                        ),
                        onPressed: () => _index == _steps.length - 1
                            ? _finish(InterventionOutcome.completed)
                            : setState(() => _index++),
                        icon: Icon(
                          _index == _steps.length - 1
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(
                          _index == _steps.length - 1 ? 'Finish' : 'Next',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: AssessmentPresentation.textButtonStyle(context),
                    onPressed: () => _finish(InterventionOutcome.skipped),
                    child: const Text('Skip activity'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
