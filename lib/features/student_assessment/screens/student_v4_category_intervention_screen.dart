import 'package:flutter/material.dart';

import '../models/intervention_models.dart';
import '../widgets/assessment_presentation.dart';

/// Ephemeral planning activity for Student Well-Being V4 Academic and Financial
/// categories. Choices and optional notes stay in local widget state and are
/// never saved, logged, or sent to any service.
class StudentV4CategoryInterventionScreen extends StatefulWidget {
  const StudentV4CategoryInterventionScreen({
    required this.intervention,
    super.key,
  }) : assert(
         intervention == InterventionType.academicPlanning ||
             intervention == InterventionType.financialPlanning,
         'StudentV4CategoryInterventionScreen only supports academicPlanning or financialPlanning.',
       );

  final InterventionType intervention;

  @override
  State<StudentV4CategoryInterventionScreen> createState() =>
      _StudentV4CategoryInterventionScreenState();
}

class _StudentV4CategoryInterventionScreenState
    extends State<StudentV4CategoryInterventionScreen> {
  static const _academicSteps = [
    'Open and skim the first section',
    'List 3 bullet points or questions',
    'Gather materials for one subject',
    'Write the smallest next step for a deadline',
  ];

  static const _academicCues = [
    'Right after this assessment',
    'After my next class or meal',
    'During a quiet moment tonight',
    'Tomorrow morning',
  ];

  static const _financialSteps = [
    'Check one upcoming due date or school fee deadline',
    'Find a student financial-aid or campus support contact',
    'Set a specific time to revisit the concern calmly',
    'Ask a trusted person or campus office where to check payment details',
  ];

  static const _financialTimes = [
    'Later today',
    'Tomorrow',
    'This weekend',
    'During a quiet 10-minute break',
  ];

  final _academicNoteController = TextEditingController();
  String? _selectedPrimary;
  String? _selectedTiming;

  bool get _isAcademic =>
      widget.intervention != InterventionType.financialPlanning;

  @override
  void dispose() {
    _academicNoteController.dispose();
    super.dispose();
  }

  void _togglePrimary(String option) {
    setState(() {
      _selectedPrimary = _selectedPrimary == option ? null : option;
    });
  }

  void _toggleTiming(String option) {
    setState(() {
      _selectedTiming = _selectedTiming == option ? null : option;
    });
  }

  void _finish(InterventionOutcome outcome) {
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final isAcademic = _isAcademic;
    final copy = studentV4ActivityCopyFor(
      isAcademic
          ? InterventionType.academicPlanning
          : InterventionType.financialPlanning,
    )!;
    final primaryOptions = isAcademic ? _academicSteps : _financialSteps;
    final timingOptions = isAcademic ? _academicCues : _financialTimes;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAcademic ? 'Academic check-in' : 'Financial check-in'),
      ),
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
                          copy.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const AssessmentStatusPill(label: '1–3 min'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AssessmentSurfaceCard(
                    color: AssessmentPresentation.softAccent(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isAcademic
                              ? Icons.menu_book_rounded
                              : Icons.savings_rounded,
                          color: AssessmentPresentation.onSoftAccent(context),
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isAcademic
                              ? 'You do not have to finish a whole task right now. Choosing one five-minute starting point can make it easier to begin.'
                              : 'You do not have to solve everything at once. Picking one small, practical action can give you a clearer place to pause.',
                          style: const TextStyle(height: 1.45),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isAcademic
                              ? 'Your choices and notes stay on this screen and are not saved.'
                              : 'This is a gentle planning prompt, not financial advice. No balances, income, or account details are asked, and nothing here is saved.',
                          style: TextStyle(
                            color: AssessmentPresentation.muted(context),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isAcademic
                        ? '1. Pick one five-minute first step (optional)'
                        : '1. Choose one manageable step (optional)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final option in primaryOptions) ...[
                    _PlanChoiceTile(
                      label: option,
                      selected: _selectedPrimary == option,
                      onTap: () => _togglePrimary(option),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    isAcademic
                        ? '2. Pair it with a practical time or cue (optional)'
                        : '2. Choose a calm time to revisit it (optional)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final option in timingOptions) ...[
                    _PlanChoiceTile(
                      label: option,
                      selected: _selectedTiming == option,
                      onTap: () => _toggleTiming(option),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (isAcademic) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('academic-note-field'),
                      controller: _academicNoteController,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Optional note for yourself (not saved)',
                        hintText: 'e.g., Skim Chapter 2 page 1 right after lunch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_selectedPrimary != null || _selectedTiming != null) ...[
                    const SizedBox(height: 16),
                    AssessmentSurfaceCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your on-screen plan',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          if (_selectedPrimary != null)
                            Text('Step: $_selectedPrimary'),
                          if (_selectedTiming != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('When: $_selectedTiming'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: AssessmentPresentation.filledButtonStyle(context),
                    onPressed: () => _finish(InterventionOutcome.completed),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Finish activity'),
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

class _PlanChoiceTile extends StatelessWidget {
  const _PlanChoiceTile({
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
        borderRadius: AssessmentPresentation.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AssessmentPresentation.cardRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: AssessmentPresentation.cardRadius,
              border: Border.all(
                color: selected
                    ? AssessmentPresentation.onSoftAccent(context)
                    : scheme.outlineVariant,
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
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle_rounded,
                    color: AssessmentPresentation.onSoftAccent(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
