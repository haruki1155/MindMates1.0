import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../models/quick_assessment_models.dart';
import '../widgets/quick_assessment_widgets.dart';

class QuickAssessmentQuestionScreen extends StatelessWidget {
  const QuickAssessmentQuestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AssessmentProvider>(
      builder: (context, provider, _) {
        final question = provider.currentQuestion;

        return QuickAssessmentScaffold(
          topClusters: const [
            BubbleCluster(top: 66, left: -18),
            BubbleCluster(top: 270, right: -24, mirrored: true),
          ],
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutQuart,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutQuart,
                reverseCurve: Curves.easeInCubic,
              );

              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0.01),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                ),
              );
            },
            child: _QuestionPage(
              key: ValueKey(question.id),
              provider: provider,
              question: question,
            ),
          ),
        );
      },
    );
  }
}

class _QuestionPage extends StatelessWidget {
  const _QuestionPage({
    super.key,
    required this.provider,
    required this.question,
  });

  final AssessmentProvider provider;
  final QuickAssessmentQuestion question;

  @override
  Widget build(BuildContext context) {
    final selectedOption = provider.selectedOptionFor(question.id);
    final topPadding = _questionTopPadding(provider.currentQuestionIndex);

    return Column(
      children: [
        QuickProgressHeader(
          step: provider.currentQuestionStep,
          label: provider.questionProgressLabel,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              25,
              topPadding,
              21,
              116 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    question.prompt,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: QuickAssessmentPalette.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.28,
                    ),
                  ),
                ),
                SizedBox(height: provider.currentQuestionIndex == 4 ? 30 : 28),
                for (final option in question.options) ...[
                  _OptionTile(
                    option: option,
                    selected: selectedOption?.id == option.id,
                    onTap: () => provider.selectAnswer(option),
                  ),
                  const SizedBox(height: 15),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: 48 + MediaQuery.paddingOf(context).bottom,
          ),
          child: QuickNextButton(
            onPressed: provider.isSavingQuickAssessment
                ? null
                : () => _goNext(context),
            isLoading: provider.isSavingQuickAssessment,
          ),
        ),
      ],
    );
  }

  double _questionTopPadding(int index) {
    switch (index) {
      case 1:
        return 47;
      case 3:
      case 4:
        return 43;
      default:
        return 58;
    }
  }

  Future<void> _goNext(BuildContext context) async {
    if (!provider.hasSelectedAnswer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an answer to continue.')),
      );
      return;
    }

    final completed = provider.isLastQuestion;
    provider.moveToNextQuestion();

    if (completed) {
      final saved = await _saveQuickAssessment(context);
      if (!context.mounted) return;
      if (!saved) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        RouteNames.quickAssessmentCategory,
        (route) => false,
      );
    }
  }

  Future<bool> _saveQuickAssessment(BuildContext context) async {
    final userId = _currentUserId(context);
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to save your assessment.'),
        ),
      );
      return false;
    }

    try {
      final payload = await provider.saveQuickAssessmentForUser(userId);
      if (!context.mounted) return false;

      final userProvider = context.read<UserProvider>();
      if (payload != null) {
        await userProvider.markQuickAssessment(userId);
        await userProvider.loadProfile(userId);
        if (context.mounted) {
          try {
            await context.read<ReportProvider>().refreshWeeklyReport(userId);
          } on ProviderNotFoundException {
            // Lightweight previews and focused tests may omit ReportProvider.
          } catch (error) {
            // The assessment is already saved; a delayed report refresh must
            // not make the completed submission look unsuccessful.
            debugPrint('Quick assessment summary refresh failed: $error');
          }
        }
      }
      await _persistSelectedRole(userProvider);
      return payload != null;
    } catch (error) {
      debugPrint('Quick assessment sync failed: $error');
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save your quick assessment. Please try again.',
            ),
          ),
        );
      return false;
    }
  }

  String? _currentUserId(BuildContext context) {
    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.userId ?? authProvider.hydrateCurrentUser();
      if (userId != null && userId.isNotEmpty) return userId;
    } on ProviderNotFoundException {
      // Some previews/tests may only provide UserProvider.
    }

    try {
      return context.read<UserProvider>().user?.id;
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _persistSelectedRole(UserProvider userProvider) async {
    final role = provider.selectedRole;
    final user = userProvider.user;
    if (role == null || user == null || user.role == role.name) return;

    await userProvider.updateProfile(user.copyWith(role: role.name));
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final QuickAssessmentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.01 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? QuickAssessmentPalette.selectedFill
              : QuickAssessmentPalette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? QuickAssessmentPalette.border
                : QuickAssessmentPalette.softBorder,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: QuickAssessmentPalette.shadow.withValues(
                alpha: selected ? 0.08 : 0.12,
              ),
              blurRadius: selected ? 12 : 8,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            splashColor: QuickAssessmentPalette.primary.withValues(alpha: 0.16),
            highlightColor: QuickAssessmentPalette.primary.withValues(
              alpha: 0.08,
            ),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Image.asset(
                    option.iconAssetPath,
                    width: 25,
                    height: 25,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.circle, size: 18);
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: QuickAssessmentPalette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: QuickAssessmentPalette.text,
                    ),
                  ],
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
