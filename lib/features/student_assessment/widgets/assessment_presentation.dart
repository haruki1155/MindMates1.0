import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Screen-local presentation primitives shared by the Assessment wellness
/// activities and saved V4 result. They deliberately carry no flow state.
class AssessmentPresentation {
  const AssessmentPresentation._();

  static const cardRadius = BorderRadius.all(Radius.circular(20));

  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.darkTextSecondary
      : AppColors.textMuted;

  static Color softPrimary(BuildContext context) =>
      Theme.of(context).colorScheme.primaryContainer;

  static Color softSecondary(BuildContext context) =>
      Theme.of(context).colorScheme.secondaryContainer;
}

class AssessmentSurfaceCard extends StatelessWidget {
  const AssessmentSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: AssessmentPresentation.cardRadius,
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: AssessmentPresentation.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AssessmentStatusPill extends StatelessWidget {
  const AssessmentStatusPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
