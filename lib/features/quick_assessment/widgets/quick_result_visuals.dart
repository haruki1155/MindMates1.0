import 'package:flutter/material.dart';

import '../../student_assessment/models/assessment_interpretation_models.dart';
import 'quick_assessment_widgets.dart';

/// Icon, color and label used to show one response pattern on the
/// Quick Assessment result.
class QuickPatternVisual {
  const QuickPatternVisual({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  /// Pattern codes shown in the legend, from most to least supported.
  static const List<String> legendCodes = [
    'wellBeingSupported',
    'generallySteady',
    'someStrain',
    'supportMayHelp',
  ];

  static QuickPatternVisual forCode(String code) {
    final label = AssessmentResponsePattern.labelForCode(code);
    final (icon, color) = switch (code) {
      'wellBeingSupported' => (
        Icons.sentiment_very_satisfied_rounded,
        const Color(0xFF2E7D32),
      ),
      'generallySteady' => (
        Icons.sentiment_satisfied_rounded,
        const Color(0xFF00897B),
      ),
      'someStrain' => (
        Icons.sentiment_neutral_rounded,
        const Color(0xFFB26A00),
      ),
      'supportMayHelp' => (
        Icons.volunteer_activism_rounded,
        const Color(0xFFC62828),
      ),
      _ => (Icons.help_outline_rounded, const Color(0xFF757575)),
    };
    return QuickPatternVisual(icon: icon, color: color, label: label);
  }
}

/// Icon for a quick-assessment indicator (concern area).
IconData quickDomainIcon(String domain) => switch (domain) {
  'Emotional calm' => Icons.spa_rounded,
  'Stress load' => Icons.monitor_heart_rounded,
  'Social connection' => Icons.groups_rounded,
  'Motivation and interest' => Icons.emoji_objects_rounded,
  'Daily coping' => Icons.self_improvement_rounded,
  _ => Icons.insights_rounded,
};

/// Large circular illustration for the overall result pattern.
class QuickResultIllustration extends StatelessWidget {
  const QuickResultIllustration({super.key, required this.patternCode});

  final String patternCode;

  @override
  Widget build(BuildContext context) {
    final visual = QuickPatternVisual.forCode(patternCode);
    return Semantics(
      label: visual.label,
      child: Container(
        key: const Key('quick-result-illustration'),
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: visual.color.withValues(alpha: 0.12),
          border: Border.all(color: visual.color, width: 2),
        ),
        alignment: Alignment.center,
        child: Icon(visual.icon, size: 52, color: visual.color),
      ),
    );
  }
}

/// One indicator row: domain icon, domain name and a colored pattern chip.
class QuickIndicatorRow extends StatelessWidget {
  const QuickIndicatorRow({super.key, required this.indicator});

  final AssessmentDomainResult indicator;

  @override
  Widget build(BuildContext context) {
    final visual = QuickPatternVisual.forCode(indicator.responsePatternCode);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          quickDomainIcon(indicator.domain),
          size: 20,
          color: QuickAssessmentPalette.text,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            indicator.domain,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(visual.icon, size: 16, color: visual.color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    indicator.responsePatternLabel,
                    style: TextStyle(
                      color: visual.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Legend explaining each indicator pattern's icon and color.
class QuickPatternLegend extends StatelessWidget {
  const QuickPatternLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('quick-pattern-legend'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Legend', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final code in QuickPatternVisual.legendCodes)
              _LegendEntry(visual: QuickPatternVisual.forCode(code)),
          ],
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.visual});

  final QuickPatternVisual visual;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(visual.icon, size: 16, color: visual.color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            visual.label,
            style: TextStyle(
              color: visual.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
