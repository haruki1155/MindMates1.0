import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../repositories/inquiry_repository.dart';

class ClientFeedbackFormScreen extends StatefulWidget {
  const ClientFeedbackFormScreen({super.key});

  @override
  State<ClientFeedbackFormScreen> createState() =>
      _ClientFeedbackFormScreenState();
}

class _ClientFeedbackFormScreenState extends State<ClientFeedbackFormScreen> {
  final _emailKey = GlobalKey<FormState>();
  final _informationKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _courseController = TextEditingController();
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  final _ratings = List<int?>.filled(_feedbackQuestions.length, null);

  int _step = 0;
  bool _consented = false;
  bool _submitting = false;
  String? _clientType;
  String? _sex;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _courseController.dispose();
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step--);
    _scrollToTop();
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      final valid = _informationKey.currentState?.validate() ?? false;
      if (_clientType == null || _sex == null || !valid) {
        _showMessage('Please complete all required client information.');
        return;
      }
    } else if (_step == 1) {
      if (!(_emailKey.currentState?.validate() ?? false)) return;
      if (!_consented) {
        _showMessage('Please read and accept the Data Privacy Consent.');
        return;
      }
    } else {
      final unanswered = _ratings.indexWhere((rating) => rating == null);
      if (unanswered != -1) {
        _showMessage(
          'Please answer evaluation question ${unanswered + 1} before continuing.',
        );
        return;
      }
      if (_submitting) return;
      setState(() => _submitting = true);
      try {
        if (Firebase.apps.isNotEmpty) {
          await InquiryRepository().submitForm(
            formType: 'client_feedback',
            subject: 'Client Feedback Form',
            email: _emailController.text,
            name: _nameController.text,
            formData: {
              'Client type': _clientType,
              'Sex': _sex,
              'Course / Office': _courseController.text.trim(),
              for (var index = 0; index < _feedbackQuestions.length; index++)
                _feedbackQuestions[index]: _ratings[index],
              'Comments': _commentController.text.trim(),
              'Data privacy consent': _consented,
            },
          );
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ClientFeedbackConfirmationScreen(),
          ),
        );
      } catch (error) {
        if (mounted) {
          _showMessage(error.toString().replaceFirst('Bad state: ', ''));
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }

    setState(() => _step++);
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _FeedbackColors.background,
      appBar: AppBar(
        backgroundColor: _FeedbackColors.sun,
        foregroundColor: _FeedbackColors.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 0,
        title: const Text(
          'Client Feedback Form',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
      body: Column(
        children: [
          _FeedbackProgress(step: _step),
          Expanded(
            child: ListView(
              key: PageStorageKey('client-feedback-step-$_step'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                if (_step == 0)
                  _ClientInformationStep(
                    formKey: _informationKey,
                    nameController: _nameController,
                    courseController: _courseController,
                    clientType: _clientType,
                    sex: _sex,
                    onClientTypeChanged: (value) =>
                        setState(() => _clientType = value),
                    onSexChanged: (value) => setState(() => _sex = value),
                    requiredValidator: _required,
                  )
                else if (_step == 1)
                  _ConsentStep(
                    formKey: _emailKey,
                    emailController: _emailController,
                    consented: _consented,
                    onConsentChanged: (value) =>
                        setState(() => _consented = value),
                    emailValidator: (value) {
                      final required = _required(value, 'Email address');
                      if (required != null) return required;
                      if (!RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(value!.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  )
                else
                  _EvaluationStep(
                    ratings: _ratings,
                    commentController: _commentController,
                    onRatingChanged: (index, value) {
                      setState(() => _ratings[index] = value);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _FeedbackNavigation(
        isFirst: _step == 0,
        isLast: _step == 2,
        onBack: _back,
        onNext: _submitting ? null : _next,
      ),
    );
  }
}

class _FeedbackProgress extends StatelessWidget {
  const _FeedbackProgress({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const names = ['Student information', 'Consent', 'Evaluation'];
    return Container(
      color: _FeedbackColors.sun,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'STEP ${step + 1} OF 3',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                names[step],
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (step + 1) / 3,
              minHeight: 7,
              backgroundColor: Colors.white.withAlpha(150),
              color: _FeedbackColors.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentStep extends StatelessWidget {
  const _ConsentStep({
    required this.formKey,
    required this.emailController,
    required this.consented,
    required this.onConsentChanged,
    required this.emailValidator,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final bool consented;
  final ValueChanged<bool> onConsentChanged;
  final FormFieldValidator<String> emailValidator;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        children: [
          _FeedbackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeading(
                  icon: Icons.mail_outline_rounded,
                  title: 'Your contact email',
                  subtitle: 'Survey A.Y. 2025–2026',
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const ValueKey('client-feedback-email'),
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  validator: emailValidator,
                  decoration: const InputDecoration(
                    labelText: 'Email address *',
                    hintText: 'name@example.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _FeedbackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeading(
                  icon: Icons.rate_review_outlined,
                  title: 'Evaluation',
                  subtitle: 'Your experience helps us improve',
                ),
                SizedBox(height: 14),
                Text(
                  'Please answer honestly and to the best of your ability. Your feedback will be used to improve our services, programs, and events.',
                  style: _FeedbackText.body,
                ),
                SizedBox(height: 16),
                _CompactRatingGuide(),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _FeedbackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeading(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Data Privacy Consent',
                  subtitle: 'How your information will be handled',
                ),
                const SizedBox(height: 14),
                const Text(
                  'UCU–PACC will collect your email address, full name, sex, course, client type, ratings, and optional comments for service evaluation. Your information will be kept confidential, securely stored, and accessed only by authorized PACC personnel in accordance with the Data Privacy Act of 2012. It will not be shared without consent unless required by law.\n\nYou may request access, correction, deletion, or withdrawal of consent, subject to applicable requirements. Withdrawing consent may prevent completion of this evaluation.',
                  style: _FeedbackText.body,
                ),
                const SizedBox(height: 16),
                Material(
                  color: consented
                      ? _FeedbackColors.greenSoft
                      : _FeedbackColors.sunSoft,
                  borderRadius: BorderRadius.circular(14),
                  child: CheckboxListTile(
                    key: const ValueKey('client-feedback-consent'),
                    value: consented,
                    onChanged: (value) => onConsentChanged(value ?? false),
                    activeColor: _FeedbackColors.green,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I have read the notice and consent to the collection and use of my personal data as described above.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

class _EvaluationStep extends StatelessWidget {
  const _EvaluationStep({
    required this.ratings,
    required this.commentController,
    required this.onRatingChanged,
  });

  final List<int?> ratings;
  final TextEditingController commentController;
  final void Function(int index, int value) onRatingChanged;

  @override
  Widget build(BuildContext context) {
    var questionOffset = 0;
    return Column(
      children: [
        const _FeedbackCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeading(
                icon: Icons.stars_outlined,
                title: 'Rate your experience',
                subtitle: 'Select one rating for every statement',
              ),
              SizedBox(height: 14),
              _CompactRatingGuide(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final group in _feedbackQuestionGroups) ...[
          Builder(
            builder: (context) {
              final start = questionOffset;
              questionOffset += group.questions.length;
              return _FeedbackCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CardHeading(
                      icon: group.icon,
                      title: group.title,
                      subtitle: group.subtitle,
                    ),
                    const SizedBox(height: 10),
                    for (var local = 0; local < group.questions.length; local++)
                      _FeedbackRatingQuestion(
                        index: start + local,
                        number: start + local + 1,
                        question: group.questions[local],
                        value: ratings[start + local],
                        onChanged: (rating) =>
                            onRatingChanged(start + local, rating),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
        ],
        _FeedbackCard(
          child: TextField(
            key: const ValueKey('client-feedback-comment'),
            controller: commentController,
            minLines: 4,
            maxLines: 7,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Additional comments (optional)',
              hintText: 'Tell us what went well or what we can improve…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackRatingQuestion extends StatelessWidget {
  const _FeedbackRatingQuestion({
    required this.index,
    required this.number,
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final int index;
  final int number;
  final String question;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. $question',
            style: const TextStyle(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var rating = 1; rating <= 5; rating++) ...[
                Expanded(
                  child: InkWell(
                    key: ValueKey('feedback-question-$index-rating-$rating'),
                    onTap: () => onChanged(rating),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _FeedbackRatingBadge(
                        rating: rating,
                        selected: value == rating,
                      ),
                    ),
                  ),
                ),
                if (rating != 5) const SizedBox(width: 5),
              ],
            ],
          ),
          const Row(
            children: [
              Expanded(
                child: Text('Needs improvement', style: _FeedbackText.scaleEnd),
              ),
              Text('Excellent', style: _FeedbackText.scaleEnd),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientInformationStep extends StatelessWidget {
  const _ClientInformationStep({
    required this.formKey,
    required this.nameController,
    required this.courseController,
    required this.clientType,
    required this.sex,
    required this.onClientTypeChanged,
    required this.onSexChanged,
    required this.requiredValidator,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController courseController;
  final String? clientType;
  final String? sex;
  final ValueChanged<String?> onClientTypeChanged;
  final ValueChanged<String?> onSexChanged;
  final String? Function(String?, String) requiredValidator;

  @override
  Widget build(BuildContext context) {
    const clientTypes = [
      'Student',
      'Alumni',
      'Parent',
      'UCU / City Hall Employee',
      'Walk-in visitor',
    ];
    return Form(
      key: formKey,
      child: Column(
        children: [
          _FeedbackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeading(
                  icon: Icons.person_outline_rounded,
                  title: 'Client information',
                  subtitle: 'Tell us which client group you belong to',
                ),
                const SizedBox(height: 14),
                Material(
                  color: Colors.transparent,
                  child: RadioGroup<String>(
                    groupValue: clientType,
                    onChanged: onClientTypeChanged,
                    child: Column(
                      children: [
                        for (final type in clientTypes)
                          RadioListTile<String>(
                            key: ValueKey('client-type-$type'),
                            value: type,
                            activeColor: _FeedbackColors.green,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              type,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _FeedbackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('client-feedback-name'),
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (value) => requiredValidator(value, 'Full name'),
                  decoration: const InputDecoration(
                    labelText: 'Full name *',
                    hintText: 'Last name, First name, M.I.',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('client-feedback-course'),
                  controller: courseController,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => requiredValidator(value, 'Course'),
                  decoration: const InputDecoration(
                    labelText: 'Course *',
                    hintText: 'e.g. BS Psychology',
                    prefixIcon: Icon(Icons.school_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Sex *',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Female', label: Text('Female')),
                    ButtonSegment(value: 'Male', label: Text('Male')),
                  ],
                  selected: sex == null ? const {} : {sex!},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (selection) =>
                      onSexChanged(selection.firstOrNull),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.comfortable,
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? _FeedbackColors.sun
                          : Colors.white,
                    ),
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

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _FeedbackColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _FeedbackColors.sunSoft,
          ),
          child: Icon(icon, color: _FeedbackColors.ink, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _FeedbackColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactRatingGuide extends StatelessWidget {
  const _CompactRatingGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _FeedbackColors.sunSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          _GuideRow(rating: 5, label: 'Excellent'),
          _GuideRow(rating: 4, label: 'Very satisfactory'),
          _GuideRow(rating: 3, label: 'Neutral'),
          _GuideRow(rating: 2, label: 'Poor'),
          _GuideRow(rating: 1, label: 'Needs improvement'),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.rating, required this.label});

  final int rating;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rating',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackRatingBadge extends StatelessWidget {
  const _FeedbackRatingBadge({required this.rating, required this.selected});

  final int rating;
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
        color: selected ? _FeedbackColors.sun : _FeedbackColors.choice,
        border: Border.all(
          color: selected ? _FeedbackColors.sunDark : Colors.transparent,
          width: 2,
        ),
      ),
      child: Text(
        '$rating',
        style: TextStyle(
          color: selected ? _FeedbackColors.ink : Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FeedbackNavigation extends StatelessWidget {
  const _FeedbackNavigation({
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onNext,
  });

  final bool isFirst;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _FeedbackColors.border)),
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(isFirst ? 'Exit' : 'Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _FeedbackColors.ink,
                minimumSize: const Size(105, 50),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onNext,
                iconAlignment: IconAlignment.end,
                icon: Icon(
                  isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                ),
                label: Text(isLast ? 'Submit' : 'Next'),
                style: FilledButton.styleFrom(
                  foregroundColor: _FeedbackColors.ink,
                  backgroundColor: _FeedbackColors.sun,
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

class ClientFeedbackConfirmationScreen extends StatelessWidget {
  const ClientFeedbackConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _FeedbackColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _FeedbackCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _FeedbackColors.sun,
                        ),
                        child: const Icon(Icons.check_rounded, size: 54),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Client Feedback Form',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your response has been recorded.',
                        textAlign: TextAlign.center,
                        style: _FeedbackText.body,
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: _FeedbackColors.green,
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
        ),
      ),
    );
  }
}

class _FeedbackQuestionGroup {
  const _FeedbackQuestionGroup({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.questions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> questions;
}

const _feedbackQuestionGroups = [
  _FeedbackQuestionGroup(
    title: 'Service experience',
    subtitle: 'Promptness and courtesy',
    icon: Icons.support_agent_rounded,
    questions: ['Provides prompt service', 'Delivers courteous service'],
  ),
  _FeedbackQuestionGroup(
    title: 'Information and output',
    subtitle: 'Clarity, accuracy, and timeliness',
    icon: Icons.description_outlined,
    questions: [
      'Gives clear information',
      'Prepares accurate output',
      'Releases documents on the scheduled date',
    ],
  ),
  _FeedbackQuestionGroup(
    title: 'Waiting area',
    subtitle: 'Cleanliness, comfort, and wayfinding',
    icon: Icons.chair_outlined,
    questions: [
      'The waiting area is clean',
      'The waiting area is comfortable',
      'Signs are clearly displayed',
    ],
  ),
];

final _feedbackQuestions = _feedbackQuestionGroups
    .expand((group) => group.questions)
    .toList(growable: false);

class _FeedbackColors {
  const _FeedbackColors._();

  static const background = Color(0xFFFFFAEC);
  static const sun = Color(0xFFFFCD3A);
  static const sunDark = Color(0xFFE6A900);
  static const sunSoft = Color(0xFFFFF0B8);
  static const green = Color(0xFF3F8A70);
  static const greenSoft = Color(0xFFE8F5EF);
  static const ink = Color(0xFF191712);
  static const muted = Color(0xFF6E6A60);
  static const choice = Color(0xFF777267);
  static const border = Color(0xFFE9DFC7);
}

class _FeedbackText {
  const _FeedbackText._();

  static const body = TextStyle(
    color: _FeedbackColors.ink,
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w600,
  );
  static const scaleEnd = TextStyle(color: _FeedbackColors.muted, fontSize: 9);
}
