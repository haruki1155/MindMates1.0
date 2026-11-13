import 'package:flutter/material.dart';

IconData assessmentDomainIcon(String? domainId) => switch (domainId) {
  'academic' => Icons.menu_book_rounded,
  'financial' => Icons.savings_rounded,
  'socialAdjustment' => Icons.groups_rounded,
  'sleepRest' => Icons.bedtime_rounded,
  'emotionalWellbeing' => Icons.favorite_rounded,
  'teachingWorkloadDemands' ||
  'nonTeachingWorkloadDemands' => Icons.work_outline_rounded,
  'teachingSupport' || 'nonTeachingSupport' => Icons.diversity_3_rounded,
  'teachingEngagementMeaning' ||
  'nonTeachingEngagementMeaning' => Icons.emoji_objects_rounded,
  _ => Icons.insights_rounded,
};

Color assessmentStatusColor(String? status) => switch (status) {
  'supported' => const Color(0xFF2F7D6D),
  'mostlySupported' => const Color(0xFF5E95BC),
  'someStrain' => const Color(0xFFE09B2D),
  'supportMayHelp' => const Color(0xFFC0603A),
  _ => const Color(0xFF6C665B),
};

class AssessmentDomainIllustration extends StatelessWidget {
  const AssessmentDomainIllustration({
    required this.domainId,
    required this.status,
    super.key,
  });

  final String? domainId;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = assessmentStatusColor(status);
    return ExcludeSemantics(
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
        ),
        child: Icon(assessmentDomainIcon(domainId), size: 26, color: color),
      ),
    );
  }
}
