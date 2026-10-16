import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../repositories/assessment_repository.dart';
import '../../../routes/route_names.dart';
import '../../counseling/screens/pacc_counseling_screen.dart';
import '../../student_assessment/models/assessment_interpretation_models.dart';
import '../models/quick_assessment_models.dart';
import '../services/quick_assessment_action_policy.dart';
import '../widgets/quick_assessment_widgets.dart';

class QuickAssessmentCategoryScreen extends StatefulWidget {
  const QuickAssessmentCategoryScreen({super.key});

  @override
  State<QuickAssessmentCategoryScreen> createState() =>
      _QuickAssessmentCategoryScreenState();
}

class _QuickAssessmentCategoryScreenState
    extends State<QuickAssessmentCategoryScreen> {
  AssessmentProvider? _assessmentProvider;
  String? _promptedResultKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AssessmentProvider>();
    if (identical(_assessmentProvider, provider)) return;
    _assessmentProvider?.removeListener(_queueAppointmentPrompt);
    _assessmentProvider = provider;
    provider.addListener(_queueAppointmentPrompt);
    _queueAppointmentPrompt();
  }

  @override
  void dispose() {
    _assessmentProvider?.removeListener(_queueAppointmentPrompt);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssessmentProvider>(
      builder: (context, provider, _) {
        final role = provider.selectedRole ?? AssessmentRole.student;

        return QuickAssessmentScaffold(
          topClusters: const [
            BubbleCluster(top: 28, left: -26),
            BubbleCluster(top: 28, right: -28, mirrored: true),
          ],
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bottomInset = MediaQuery.paddingOf(context).bottom;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(28, 68, 28, 32 + bottomInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 100 - bottomInset,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: _DecisionContent(provider: provider, role: role),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _queueAppointmentPrompt() {
    final result = _assessmentProvider?.quickResult;
    if (result == null ||
        !QuickAssessmentActionPolicy.forLevel(
          result.overallLevel,
        ).promptsForAppointment) {
      return;
    }
    final resultKey =
        '${result.createdAt.toUtc().toIso8601String()}:${result.overallLevel.name}';
    if (_promptedResultKey == resultKey) return;
    _promptedResultKey = resultKey;
    if (!_assessmentProvider!.claimQuickAppointmentPrompt(resultKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final wantsAppointment = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.calendar_month_outlined, size: 34),
          title: const Text('Would you like to talk with a PACC counselor?'),
          content: const Text(
            'Your quick check-in suggests that additional support may be helpful. Would you like to request a confidential counseling appointment with PACC?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No, Continue'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes, Book Appointment'),
            ),
          ],
        ),
      );
      if (!mounted || wantsAppointment != true) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PaccCounselingScreen(startBooking: true),
        ),
      );
    });
  }

  static String iconFor(AssessmentRole role) {
    switch (role) {
      case AssessmentRole.student:
        return 'ST';
      case AssessmentRole.faculty:
        return 'FC';
      case AssessmentRole.staff:
        return 'SF';
    }
  }
}

class _DecisionContent extends StatelessWidget {
  const _DecisionContent({required this.provider, required this.role});

  final AssessmentProvider provider;
  final AssessmentRole role;

  @override
  Widget build(BuildContext context) {
    final actionPolicy = provider.quickResult == null
        ? null
        : QuickAssessmentActionPolicy.forLevel(
            provider.quickResult!.overallLevel,
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: QuickAssessmentPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuickAssessmentPalette.softBorder),
        boxShadow: [
          BoxShadow(
            color: QuickAssessmentPalette.shadow.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QuickPlaceholderIcon(
            icon: _QuickAssessmentCategoryScreenState.iconFor(role),
            size: 20,
          ),
          if (provider.quickResult != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Your quick well-being profile',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 7),
            Text(
              provider.quickResult!.responsePatternLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: QuickAssessmentPalette.text,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              provider.quickResult!.interpretation.userSummary,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: QuickAssessmentPalette.secondaryText,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Support option: ${provider.quickResult!.interpretation.supportPriority.label}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your strengths',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            for (final strength
                in provider.quickResult!.interpretation.strengthInsights)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('• $strength'),
              ),
            if (provider
                .quickResult!
                .interpretation
                .focusInsights
                .isNotEmpty) ...[
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Areas to explore',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              for (final focus
                  in provider.quickResult!.interpretation.focusInsights)
                Align(alignment: Alignment.centerLeft, child: Text('• $focus')),
            ],
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Brief response indicators',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Each indicator is based on one answer and is not a complete category assessment.',
                style: TextStyle(
                  color: QuickAssessmentPalette.secondaryText,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final indicator
                in provider.quickResult!.interpretation.domainResults)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        indicator.domain,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        indicator.responsePatternLabel,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 28),
          ],
          const SizedBox(height: 20),
          Text(
            actionPolicy?.heading ?? 'Full Assessment Optional',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: QuickAssessmentPalette.text,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            actionPolicy?.guidance ?? _messageFor(provider, role),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: QuickAssessmentPalette.secondaryText,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.42,
            ),
          ),
          const SizedBox(height: 18),
          if (actionPolicy?.showsFullAssessmentAction ?? true)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: QuickAssessmentPalette.cream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: QuickAssessmentPalette.softBorder),
              ),
              child: Text(
                'You can answer the full ${role.label.toLowerCase()} assessment now for deeper insights, or take it later from your dashboard.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: QuickAssessmentPalette.mutedText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.36,
                ),
              ),
            ),
          const SizedBox(height: 26),
          if (actionPolicy?.showsFullAssessmentAction ?? true) ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => _openFullAssessment(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: QuickAssessmentPalette.primary,
                  foregroundColor: QuickAssessmentPalette.text,
                  elevation: 4,
                  shadowColor: QuickAssessmentPalette.shadow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Take Full Assessment'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (actionPolicy?.showsAppointmentAction ?? false) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => _openPaccBooking(context),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Book a PACC appointment'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(RouteNames.home, (route) => false);
              },
              style: TextButton.styleFrom(
                foregroundColor: QuickAssessmentPalette.secondaryText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: const Text('Continue to Home'),
            ),
          ),
        ],
      ),
    );
  }

  static String _messageFor(AssessmentProvider provider, AssessmentRole role) {
    final name = provider.name.trim();
    final prefix = name.isEmpty ? 'Your' : '$name, your';

    return '$prefix quick assessment is saved. Your ${role.label.toLowerCase()} answers will choose the right full assessment question set.';
  }

  void _openPaccBooking(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PaccCounselingScreen(startBooking: true),
      ),
    );
  }

  Future<void> _openFullAssessment(BuildContext context) async {
    final userId = _currentUserId(context);
    if (userId == null || userId.isEmpty) {
      Navigator.of(context).pushNamed(RouteNames.studentAssessment);
      return;
    }

    FullAssessmentEligibility eligibility;
    try {
      eligibility = await context
          .read<AssessmentProvider>()
          .fullAssessmentEligibility(userId);
    } catch (error, stackTrace) {
      debugPrint(
        'Full assessment eligibility check failed: $error\n$stackTrace',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to verify assessment limit. You can continue for now.',
            ),
          ),
        );
      Navigator.of(context).pushNamed(RouteNames.studentAssessment);
      return;
    }
    if (!context.mounted) return;

    if (!eligibility.canStart) {
      await _showAssessmentLimitDialog(context, eligibility);
      return;
    }

    Navigator.of(context).pushNamed(RouteNames.studentAssessment);
  }

  String? _currentUserId(BuildContext context) {
    try {
      final authProvider = context.read<AuthProvider>();
      return authProvider.userId ?? authProvider.hydrateCurrentUser();
    } on ProviderNotFoundException {
      try {
        return context.read<UserProvider>().user?.id;
      } on ProviderNotFoundException {
        return null;
      }
    }
  }

  Future<void> _showAssessmentLimitDialog(
    BuildContext context,
    FullAssessmentEligibility eligibility,
  ) {
    final nextEligibleAt = eligibility.nextEligibleAt;
    final nextEligibleText = nextEligibleAt == null
        ? 'Please try again later.'
        : 'Try again on ${_formatEligibilityDate(nextEligibleAt)}.';

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: QuickAssessmentPalette.card,
        title: const Text('Assessment limit reached'),
        content: Text(
          'You can take the full assessment up to 2 times in 7 days, with 2 days between attempts. $nextEligibleText',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  String _formatEligibilityDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '${weekdays[local.weekday - 1]}, ${months[local.month - 1]} ${local.day}, ${local.year} at $hour:$minute $period';
  }
}
