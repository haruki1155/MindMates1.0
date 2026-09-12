import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/assessment_provider.dart';
import '../../../routes/route_names.dart';
import '../../quick_assessment/widgets/quick_assessment_widgets.dart';
import '../models/student_assessment_models.dart';

/// Main assessment screen: presents one question at a time with a clear
/// progress header, a focused question card, and a secure footer.
class StudentAssessmentScreen extends StatefulWidget {
  const StudentAssessmentScreen({super.key});

  @override
  State<StudentAssessmentScreen> createState() =>
      _StudentAssessmentScreenState();
}

class _StudentAssessmentScreenState extends State<StudentAssessmentScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AssessmentProvider>().startStudentAssessment();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssessmentProvider>(
      builder: (context, provider, _) {
        final question = provider.currentStudentQuestion;
        if (question == null) {
          return const Scaffold(
            backgroundColor: _StudentPalette.background,
            body: Center(
              child: CircularProgressIndicator(color: _StudentPalette.primary),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _StudentPalette.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AssessmentHeader(
                  progress: provider.studentProgress,
                  category: question.section.label,
                  title: provider.activeAssessmentTitle,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOutQuart,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutQuart,
                        reverseCurve: Curves.easeInCubic,
                      );
                      final slide = Tween<Offset>(
                        begin: const Offset(0.04, 0.01),
                        end: Offset.zero,
                      ).animate(curved);

                      return FadeTransition(
                        opacity: curved,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: _QuestionBody(
                      key: ValueKey(question.id),
                      question: question,
                      selectedAnswer: provider.currentStudentAnswer,
                      canGoBack: provider.canGoBackStudentQuestion,
                      onAnswer: (answer) {
                        final wasLast = provider.isLastStudentQuestion;
                        provider.answerCurrentStudentQuestion(answer);
                        if (wasLast && context.mounted) {
                          Navigator.of(context).pushReplacementNamed(
                            RouteNames.studentAssessmentComplete,
                          );
                        }
                      },
                      onBack: provider.goBackStudentQuestion,
                    ),
                  ),
                ),
                const _SecureFooter(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sticky top header showing one overall completion gauge and the current
/// topic name.
class _AssessmentHeader extends StatelessWidget {
  const _AssessmentHeader({
    required this.progress,
    required this.category,
    required this.title,
  });

  final double progress;
  final String category;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        color: _StudentPalette.card,
        border: Border(
          bottom: BorderSide(color: _StudentPalette.softBorder, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _StudentPalette.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TweenAnimationBuilder<int>(
                tween: IntTween(
                  begin: 0,
                  end: (progress.clamp(0, 1) * 100).round(),
                ),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _StudentPalette.cream,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$value%',
                      style: const TextStyle(
                        color: _StudentPalette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProgressBar(value: progress, height: 7),
          const SizedBox(height: 14),
          Text(
            category,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _StudentPalette.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The animated overall assessment progress gauge.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.height});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _StudentPalette.trackBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, child) {
              return FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: animatedValue,
                heightFactor: 1,
                child: child,
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: _StudentPalette.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The scrollable body of a single question: category pill, back action,
/// context copy, the question text, and the Likert-scale answer options.
class _QuestionBody extends StatelessWidget {
  const _QuestionBody({
    super.key,
    required this.question,
    required this.selectedAnswer,
    required this.canGoBack,
    required this.onAnswer,
    required this.onBack,
  });

  final StudentAssessmentQuestion question;
  final LikertAnswer? selectedAnswer;
  final bool canGoBack;
  final ValueChanged<LikertAnswer> onAnswer;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _SectionPill(label: question.section.label)),
              const SizedBox(width: 8),
              _BackButton(enabled: canGoBack, onTap: onBack),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _StudentPalette.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _StudentPalette.softBorder),
              boxShadow: [
                BoxShadow(
                  color: QuickAssessmentPalette.shadow.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _categoryPurpose(question.section),
                  style: const TextStyle(
                    color: _StudentPalette.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                if (question.isConditional) ...[
                  const SizedBox(height: 10),
                  const _ConditionalNotice(),
                ],
                const SizedBox(height: 18),
                Text(
                  question.text,
                  style: const TextStyle(
                    color: _StudentPalette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final answer in LikertAnswer.values) ...[
            _LikertOption(
              answer: answer,
              selected: selectedAnswer == answer,
              onTap: () => onAnswer(answer),
            ),
            if (answer != LikertAnswer.values.last) const SizedBox(height: 10),
          ],
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Tap your answer to continue to the next question',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _StudentPalette.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionalNotice extends StatelessWidget {
  const _ConditionalNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _StudentPalette.cream,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: _StudentPalette.secondaryText,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This optional follow-up helps explain your earlier answers. '
              'It provides context and does not change your category status.',
              style: TextStyle(
                color: _StudentPalette.secondaryText,
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: _StudentPalette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _StudentPalette.softBorder),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: _StudentPalette.text,
                ),
                SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    color: _StudentPalette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _categoryPurpose(AssessmentSection section) => switch (section) {
  AssessmentSection.academicCore || AssessmentSection.academicDeeper =>
    'Explores how academic demands may be affecting your daily well-being.',
  AssessmentSection.financialConcern =>
    'Explores how financial concerns may be affecting study and well-being.',
  AssessmentSection.socialAdjustment =>
    'Explores connection, belonging, and access to social support.',
  AssessmentSection.workplaceStressCore ||
  AssessmentSection.workplaceStressDeeper ||
  AssessmentSection.workplaceResponsibilityCore ||
  AssessmentSection.workplaceResponsibilityDeeper =>
    'Explores how workplace demands may be affecting daily well-being.',
  AssessmentSection.professionalSupport || AssessmentSection.workplaceSupport =>
    'Explores support, communication, and respect in the workplace.',
  AssessmentSection.professionalWellBeing ||
  AssessmentSection.workplaceWellBeing =>
    'Explores coping, motivation, and well-being at work.',
  AssessmentSection.sleepRest =>
    'Explores sleep quality, rest, and daytime effects.',
  AssessmentSection.emotionalWellBeing =>
    'Explores emotional balance, coping, hope, and current strain.',
};

class _SectionPill extends StatelessWidget {
  const _SectionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _StudentPalette.cream,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _StudentPalette.softBorder),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _StudentPalette.text,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// A single Likert-scale answer row with press feedback and a clear
/// selected state, avoiding double taps while a selection is in flight.
class _LikertOption extends StatefulWidget {
  const _LikertOption({
    required this.answer,
    required this.selected,
    required this.onTap,
  });

  final LikertAnswer answer;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LikertOption> createState() => _LikertOptionState();
}

class _LikertOptionState extends State<_LikertOption> {
  bool _pressed = false;

  void _handleTap() {
    if (_pressed) return;

    setState(() => _pressed = true);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _pressed || widget.selected;
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOutCubic,
      child: Material(
        color: highlighted
            ? QuickAssessmentPalette.selectedFill
            : _StudentPalette.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: _StudentPalette.primary.withValues(alpha: 0.18),
          highlightColor: _StudentPalette.primary.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlighted
                    ? _StudentPalette.border
                    : _StudentPalette.softBorder,
                width: highlighted ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: QuickAssessmentPalette.shadow.withValues(
                    alpha: _pressed ? 0.1 : 0.05,
                  ),
                  blurRadius: _pressed ? 12 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                _NumberBadge(answer: widget.answer),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.answer.label,
                    style: const TextStyle(
                      color: _StudentPalette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (highlighted)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: _StudentPalette.border,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.answer});

  final LikertAnswer answer;

  @override
  Widget build(BuildContext context) {
    const scaleColors = [
      Color(0xFFE74C3C),
      Color(0xFFF39C12),
      Color(0xFFF1C40F),
      Color(0xFF8BC34A),
      Color(0xFF27AE60),
    ];

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: scaleColors[answer.index],
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '${answer.value}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SecureFooter extends StatelessWidget {
  const _SecureFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: _StudentPalette.card,
        border: Border(top: BorderSide(color: _StudentPalette.softBorder)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: _StudentPalette.secondaryText,
          ),
          SizedBox(width: 6),
          Text(
            'Your responses are confidential and secure',
            style: TextStyle(
              color: _StudentPalette.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentPalette {
  const _StudentPalette._();

  static const background = QuickAssessmentPalette.background;
  static const primary = QuickAssessmentPalette.primary;
  static const card = QuickAssessmentPalette.card;
  static const border = QuickAssessmentPalette.border;
  static const softBorder = QuickAssessmentPalette.softBorder;
  static const text = QuickAssessmentPalette.text;
  static const secondaryText = QuickAssessmentPalette.secondaryText;
  static const mutedText = QuickAssessmentPalette.mutedText;
  static const cream = QuickAssessmentPalette.cream;
  static const trackBackground = Colors.white;
}
