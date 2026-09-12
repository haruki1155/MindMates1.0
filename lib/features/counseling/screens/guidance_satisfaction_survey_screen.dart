import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../data/guidance_satisfaction_survey.dart';
import '../../../repositories/inquiry_repository.dart';

class GuidanceSatisfactionSurveyScreen extends StatefulWidget {
  const GuidanceSatisfactionSurveyScreen({super.key});

  @override
  State<GuidanceSatisfactionSurveyScreen> createState() =>
      _GuidanceSatisfactionSurveyScreenState();
}

class _GuidanceSatisfactionSurveyScreenState
    extends State<GuidanceSatisfactionSurveyScreen> {
  final _scrollController = ScrollController();
  final _answers = List<List<int?>>.generate(
    guidanceSurveySections.length,
    (section) => List<int?>.filled(
      guidanceSurveySections[section].questions.length,
      null,
    ),
  );
  int _sectionIndex = 0;
  bool _submitting = false;

  GuidanceSurveySection get _section => guidanceSurveySections[_sectionIndex];

  int get _answeredCount => _answers
      .expand((section) => section)
      .where((answer) => answer != null)
      .length;

  int get _questionCount => guidanceSurveySections.fold(
    0,
    (total, section) => total + section.questions.length,
  );

  void _selectAnswer(int questionIndex, int rating) {
    setState(() => _answers[_sectionIndex][questionIndex] = rating);
  }

  void _previousSection() {
    if (_sectionIndex == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _sectionIndex--);
    _scrollToTop();
  }

  Future<void> _continue() async {
    final unanswered = _answers[_sectionIndex].indexWhere(
      (answer) => answer == null,
    );
    if (unanswered != -1) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Please answer question ${unanswered + 1} before continuing.',
            ),
          ),
        );
      return;
    }
    if (_sectionIndex < guidanceSurveySections.length - 1) {
      setState(() => _sectionIndex++);
      _scrollToTop();
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final answers = <String, dynamic>{};
      for (
        var section = 0;
        section < guidanceSurveySections.length;
        section++
      ) {
        for (
          var question = 0;
          question < guidanceSurveySections[section].questions.length;
          question++
        ) {
          answers[guidanceSurveySections[section].questions[question]] =
              _answers[section][question];
        }
      }
      if (Firebase.apps.isNotEmpty) {
        await InquiryRepository().submitForm(
          formType: 'guidance_satisfaction_survey',
          subject: 'Student Satisfaction Survey',
          email: '',
          name: '',
          formData: answers,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const GuidanceSurveyConfirmationScreen(),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_sectionIndex + 1) / guidanceSurveySections.length;
    return Scaffold(
      backgroundColor: _SurveyColors.background,
      appBar: AppBar(
        backgroundColor: _SurveyColors.sun,
        foregroundColor: _SurveyColors.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _previousSection,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 0,
        title: const Text(
          'Student Satisfaction Survey',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
      body: Column(
        children: [
          _SurveyProgressHeader(
            sectionIndex: _sectionIndex,
            progress: progress,
            answeredCount: _answeredCount,
            questionCount: _questionCount,
          ),
          Expanded(
            child: ListView(
              key: PageStorageKey('guidance-survey-$_sectionIndex'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                _SectionIntroduction(section: _section),
                const SizedBox(height: 16),
                for (var index = 0; index < _section.questions.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SurveyQuestionCard(
                      number: index + 1,
                      question: _section.questions[index],
                      selectedRating: _answers[_sectionIndex][index],
                      onSelected: (rating) => _selectAnswer(index, rating),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SurveyNavigationBar(
        isFirst: _sectionIndex == 0,
        isLast: _sectionIndex == guidanceSurveySections.length - 1,
        onBack: _previousSection,
        onContinue: _submitting ? null : _continue,
      ),
    );
  }
}

class _SurveyProgressHeader extends StatelessWidget {
  const _SurveyProgressHeader({
    required this.sectionIndex,
    required this.progress,
    required this.answeredCount,
    required this.questionCount,
  });

  final int sectionIndex;
  final double progress;
  final int answeredCount;
  final int questionCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _SurveyColors.sun,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SECTION ${sectionIndex + 1} OF ${guidanceSurveySections.length}',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '$answeredCount of $questionCount answered',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              color: _SurveyColors.green,
              backgroundColor: Colors.white.withAlpha(150),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionIntroduction extends StatelessWidget {
  const _SectionIntroduction({required this.section});

  final GuidanceSurveySection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _SurveyColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _SurveyColors.sunSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text(
              'A.Y. 2025–2026',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            section.title,
            style: const TextStyle(
              color: _SurveyColors.ink,
              fontSize: 22,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'How satisfied are you with each service? Select one response per statement.',
            style: TextStyle(
              color: _SurveyColors.muted,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          const _RatingLegend(),
        ],
      ),
    );
  }
}

class _RatingLegend extends StatelessWidget {
  const _RatingLegend();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        initiallyExpanded: false,
        title: const Text(
          'View rating guide',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        children: [
          for (final entry in guidanceSurveyRatingLabels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  _RatingBadge(value: entry.key, selected: entry.key == 3),
                  const SizedBox(width: 9),
                  Text(
                    entry.value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SurveyQuestionCard extends StatelessWidget {
  const _SurveyQuestionCard({
    required this.number,
    required this.question,
    required this.selectedRating,
    required this.onSelected,
  });

  final int number;
  final String question;
  final int? selectedRating;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Question $number. $question',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selectedRating == null
                ? _SurveyColors.border
                : _SurveyColors.green.withAlpha(100),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: _SurveyColors.sunSoft,
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(
                      color: _SurveyColors.ink,
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                for (var rating = 1; rating <= 5; rating++) ...[
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: selectedRating == rating,
                      label: '$rating, ${guidanceSurveyRatingLabels[rating]}',
                      child: InkWell(
                        key: ValueKey('question-$number-rating-$rating'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onSelected(rating),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: _RatingBadge(
                            value: rating,
                            selected: selectedRating == rating,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (rating != 5) const SizedBox(width: 5),
                ],
              ],
            ),
            const SizedBox(height: 5),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Not satisfied',
                    style: TextStyle(fontSize: 9, color: _SurveyColors.muted),
                  ),
                ),
                Text(
                  'Very much satisfied',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 9, color: _SurveyColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.value, required this.selected});

  final int value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _SurveyColors.sun : _SurveyColors.choice,
        border: Border.all(
          color: selected ? _SurveyColors.sunDark : Colors.transparent,
          width: 2,
        ),
      ),
      child: Text(
        '$value',
        style: TextStyle(
          color: selected ? _SurveyColors.ink : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SurveyNavigationBar extends StatelessWidget {
  const _SurveyNavigationBar({
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onContinue,
  });

  final bool isFirst;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _SurveyColors.border)),
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(isFirst ? 'Exit' : 'Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _SurveyColors.ink,
                side: const BorderSide(color: _SurveyColors.border),
                minimumSize: const Size(105, 50),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onContinue,
                iconAlignment: IconAlignment.end,
                icon: Icon(
                  isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  size: 19,
                ),
                label: Text(isLast ? 'Finish survey' : 'Next section'),
                style: FilledButton.styleFrom(
                  backgroundColor: _SurveyColors.sun,
                  foregroundColor: _SurveyColors.ink,
                  minimumSize: const Size.fromHeight(50),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GuidanceSurveyConfirmationScreen extends StatelessWidget {
  const GuidanceSurveyConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SurveyColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 45,
              right: -24,
              child: _DecorCircle(size: 90),
            ),
            const Positioned(
              bottom: 70,
              left: -30,
              child: _DecorCircle(size: 110),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(28, 38, 28, 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _SurveyColors.sun,
                          ),
                          child: const Icon(Icons.check_rounded, size: 54),
                        ),
                        const SizedBox(height: 26),
                        const Text(
                          'Survey complete',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _SurveyColors.ink,
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 9),
                        const Text(
                          'Guidance Services Student Satisfaction Survey\nA.Y. 2025–2026',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _SurveyColors.ink,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Your responses are complete. Secure submission to the administration will be enabled when the backend connection is added.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _SurveyColors.muted,
                            fontSize: 13,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: _SurveyColors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: const Text(
                              'Return to services',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  const _DecorCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _SurveyColors.sun.withAlpha(55),
      ),
    );
  }
}

class _SurveyColors {
  const _SurveyColors._();

  static const background = Color(0xFFFFFAEC);
  static const sun = Color(0xFFFFCD3A);
  static const sunDark = Color(0xFFE6A900);
  static const sunSoft = Color(0xFFFFF0B8);
  static const green = Color(0xFF3F8A70);
  static const ink = Color(0xFF191712);
  static const muted = Color(0xFF6E6A60);
  static const choice = Color(0xFF777267);
  static const border = Color(0xFFE9DFC7);
}
