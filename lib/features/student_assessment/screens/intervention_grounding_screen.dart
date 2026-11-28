import 'package:flutter/material.dart';

import '../models/intervention_models.dart';
import '../widgets/assessment_presentation.dart';

class InterventionGroundingScreen extends StatefulWidget {
  const InterventionGroundingScreen({
    super.key,
    this.includeFeelingPrompt = false,
  });

  /// When true (Student V4 Emotional Well-Being), adds an optional final step
  /// inviting the user to notice or name a feeling locally without saving it.
  final bool includeFeelingPrompt;

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

  static const _feelingOptions = [
    'Tense',
    'Tired',
    'Overwhelmed',
    'Unsure',
    'Calm',
    'Relieved',
  ];

  final _feelingController = TextEditingController();
  int _index = 0;
  String? _selectedFeeling;

  int get _totalSteps =>
      widget.includeFeelingPrompt ? _steps.length + 1 : _steps.length;

  bool get _isFeelingStep =>
      widget.includeFeelingPrompt && _index == _steps.length;

  @override
  void dispose() {
    _feelingController.dispose();
    super.dispose();
  }

  void _finish(InterventionOutcome value) => Navigator.pop(context, value);

  @override
  Widget build(BuildContext context) {
    final isLastStep = _index == _totalSteps - 1;
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
                          widget.includeFeelingPrompt
                              ? 'Ground and notice'
                              : 'Five senses reset',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      AssessmentStatusPill(
                        label: 'Step ${_index + 1} of $_totalSteps',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: (_index + 1) / _totalSteps,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(999),
                    color: AssessmentPresentation.accent,
                    backgroundColor: AssessmentPresentation.softAccent(context),
                  ),
                  const SizedBox(height: 24),
                  AssessmentSurfaceCard(
                    color: AssessmentPresentation.softAccent(context),
                    child: _isFeelingStep
                        ? _buildFeelingPromptBody(context)
                        : _buildSensoryStepBody(context),
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
                        onPressed: () => isLastStep
                            ? _finish(InterventionOutcome.completed)
                            : setState(() => _index++),
                        icon: Icon(
                          isLastStep
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(isLastStep ? 'Finish' : 'Next'),
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

  Widget _buildSensoryStepBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.spa_outlined,
          color: AssessmentPresentation.onSoftAccent(context),
          size: 30,
        ),
        const SizedBox(height: 18),
        Text(
          _steps[_index],
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
    );
  }

  Widget _buildFeelingPromptBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.spa_outlined,
          color: AssessmentPresentation.onSoftAccent(context),
          size: 30,
        ),
        const SizedBox(height: 16),
        Text(
          'Notice or name a feeling (optional)',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a word, type a few words for yourself, or leave this blank. Nothing here is saved.',
          style: TextStyle(
            color: AssessmentPresentation.muted(context),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final feeling in _feelingOptions)
              _FeelingChoiceChip(
                label: feeling,
                selected: _selectedFeeling == feeling,
                onTap: () => setState(() {
                  _selectedFeeling = _selectedFeeling == feeling
                      ? null
                      : feeling;
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('grounding-feeling-note'),
          controller: _feelingController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            filled: true,
            fillColor: scheme.surface,
            labelText: 'Put it into your own words (optional, not saved)',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _FeelingChoiceChip extends StatelessWidget {
  const _FeelingChoiceChip({
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
        color: selected
            ? AssessmentPresentation.softAccent(context)
            : scheme.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? AssessmentPresentation.onSoftAccent(context)
                    : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected
                    ? AssessmentPresentation.onSoftAccent(context)
                    : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
