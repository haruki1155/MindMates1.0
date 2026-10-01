import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import 'client_feedback_form_screen.dart';
import 'guidance_satisfaction_survey_screen.dart';
import 'pacc_counseling_screen.dart';

class ServiceGuideData {
  const ServiceGuideData({
    required this.title,
    required this.eligibleClients,
    required this.availability,
    required this.personResponsible,
    required this.fee,
    required this.steps,
    this.description,
    this.forms = const [],
    this.requirements = const [],
    this.completionMessage,
    this.nextOffice,
  });

  final String title;
  final String? description;
  final String eligibleClients;
  final String availability;
  final String personResponsible;
  final String fee;
  final List<String> forms;
  final List<String> requirements;
  final List<ServiceGuideStep> steps;
  final String? completionMessage;
  final String? nextOffice;
}

class ServiceGuideStep {
  const ServiceGuideStep({
    required this.number,
    required this.title,
    required this.clientAction,
    required this.providerAction,
    this.duration,
    this.note,
  });

  final int number;
  final String title;
  final String clientAction;
  final String providerAction;
  final String? duration;
  final String? note;
}

class ServiceDetailData {
  const ServiceDetailData({
    required this.title,
    required this.summary,
    required this.description,
    this.iconAsset,
    this.iconData,
    this.headerColor = const Color(0xFFFFCE3C),
    this.isCounseling = false,
    this.hasReactivationProcedure = false,
    this.hasShiftingProcedure = false,
    this.hasSatisfactionSurvey = false,
    this.hasClientFeedbackForm = false,
    this.guides = const [],
  });

  final String title;
  final String summary;
  final String description;
  final String? iconAsset;
  final IconData? iconData;
  final Color headerColor;
  final bool isCounseling;
  final bool hasReactivationProcedure;
  final bool hasShiftingProcedure;
  final bool hasSatisfactionSurvey;
  final bool hasClientFeedbackForm;
  final List<ServiceGuideData> guides;
}

class ServiceDetailScreen extends StatelessWidget {
  const ServiceDetailScreen({super.key, required this.service});

  final ServiceDetailData service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DetailColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _DetailHeader(
              title: service.title,
              headerColor: service.headerColor,
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _DetailIcon(service: service),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(service.title, style: _DetailText.title),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(service.description, style: _DetailText.body),
                    if (service.guides.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      _ServiceGuideSection(guides: service.guides),
                    ],
                    if (service.isCounseling) ...[
                      const SizedBox(height: 32),
                      const _DetailSectionHeading(
                        title: 'Appointment Support',
                        subtitle:
                            'Choose this option when you would like to speak privately with a counselor.',
                      ),
                      const SizedBox(height: 14),
                      _ServiceActionCard(
                        icon: Icons.event_available_rounded,
                        purpose: 'CONFIDENTIAL COUNSELING',
                        title: 'Schedule a Counseling Session',
                        description:
                            'Set a preferred date and time to discuss personal, academic, social, or emotional concerns with a PACC counselor.',
                        buttonLabel: 'Set Appointment',
                        onTap: () => _openPaccCounseling(context),
                      ),
                    ],
                    if (service.hasSatisfactionSurvey ||
                        service.hasClientFeedbackForm) ...[
                      const SizedBox(height: 32),
                      const _DetailSectionHeading(
                        title: 'Available Forms',
                        subtitle:
                            'Select the form that matches your request. Your information will help PACC review and guide your next steps.',
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (service.hasSatisfactionSurvey) ...[
                      _ServiceActionCard(
                        icon: Icons.rate_review_outlined,
                        purpose: 'SERVICE EVALUATION',
                        title: 'Guidance Services Student Satisfaction',
                        description:
                            'Rate your experience with the university guidance services. Your responses help PACC evaluate service quality and identify areas for improvement.',
                        buttonLabel: 'Open Satisfaction Survey',
                        onTap: () => _openSatisfactionSurvey(context),
                      ),
                    ],
                    if (service.hasClientFeedbackForm) ...[
                      const SizedBox(height: 16),
                      _ServiceActionCard(
                        icon: Icons.feedback_outlined,
                        purpose: 'CLIENT EXPERIENCE',
                        title: 'Client Feedback Form',
                        description:
                            'Share feedback about the assistance you received, including service ratings and additional comments that can help improve future support.',
                        buttonLabel: 'Open Client Feedback Form',
                        onTap: () => _openClientFeedbackForm(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _openPaccCounseling(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PaccCounselingScreen()));
  }

  static void _openSatisfactionSurvey(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GuidanceSatisfactionSurveyScreen(),
      ),
    );
  }

  static void _openClientFeedbackForm(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ClientFeedbackFormScreen()));
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.title, required this.headerColor});

  final String title;
  final Color headerColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: _DetailColors.sun,
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _DetailText.headerTitle,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _DetailIcon extends StatelessWidget {
  const _DetailIcon({required this.service});

  final ServiceDetailData service;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: service.headerColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: service.iconData != null
          ? Icon(service.iconData, size: 26, color: Colors.black87)
          : Image.asset(
              '${AppAssets.servicesImages}/${service.iconAsset}',
              width: 26,
              height: 26,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.image_not_supported_outlined, size: 26),
            ),
    );
  }
}

class _DetailSectionHeading extends StatelessWidget {
  const _DetailSectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _DetailText.sectionTitle),
        const SizedBox(height: 5),
        Text(subtitle, style: _DetailText.sectionSubtitle),
      ],
    );
  }
}

class _ServiceGuideSection extends StatelessWidget {
  const _ServiceGuideSection({required this.guides});

  final List<ServiceGuideData> guides;

  @override
  Widget build(BuildContext context) {
    final hasChoices = guides.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DetailSectionHeading(
          title: 'HOW TO AVAIL THIS SERVICE',
          subtitle:
              'Follow the steps below before and during your transaction with PACC.',
        ),
        const SizedBox(height: 14),
        for (final guide in guides) ...[
          if (hasChoices)
            _ExpandableServiceGuide(guide: guide)
          else
            _GuideContent(guide: guide),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _ExpandableServiceGuide extends StatelessWidget {
  const _ExpandableServiceGuide({required this.guide});

  final ServiceGuideData guide;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(guide.title, style: _DetailText.actionTitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [_GuideContent(guide: guide)],
      ),
    );
  }
}

class _GuideContent extends StatelessWidget {
  const _GuideContent({required this.guide});

  final ServiceGuideData guide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (guide.description != null) ...[
          Text(guide.description!, style: _DetailText.sectionSubtitle),
          const SizedBox(height: 12),
        ],
        _ServiceInformationCard(guide: guide),
        if (guide.forms.isNotEmpty || guide.requirements.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ServiceRequirementsCard(guide: guide),
        ],
        for (final step in guide.steps) ...[
          const SizedBox(height: 12),
          _ServiceGuideStepCard(step: step, totalSteps: guide.steps.length),
        ],
        if (guide.completionMessage != null || guide.nextOffice != null) ...[
          const SizedBox(height: 12),
          _ServiceGuideCompletionCard(guide: guide),
        ],
      ],
    );
  }
}

class _ServiceInformationCard extends StatelessWidget {
  const _ServiceInformationCard({required this.guide});
  final ServiceGuideData guide;

  @override
  Widget build(BuildContext context) => _GuideCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SERVICE INFORMATION', style: _DetailText.purposeLabel),
        const SizedBox(height: 10),
        _GuideField(label: 'Who may avail', value: guide.eligibleClients),
        _GuideField(label: 'Availability', value: guide.availability),
        _GuideField(
          label: 'Person Responsible',
          value: guide.personResponsible,
        ),
        _GuideField(label: 'Fee', value: guide.fee),
      ],
    ),
  );
}

class _ServiceRequirementsCard extends StatelessWidget {
  const _ServiceRequirementsCard({required this.guide});
  final ServiceGuideData guide;

  @override
  Widget build(BuildContext context) => _GuideCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('BEFORE YOU START', style: _DetailText.purposeLabel),
        if (guide.forms.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Required Forms', style: _DetailText.guideLabel),
          ...guide.forms.map((item) => _GuideBullet(text: item)),
        ],
        if (guide.requirements.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Required Documents', style: _DetailText.guideLabel),
          ...guide.requirements.map((item) => _GuideBullet(text: item)),
        ],
      ],
    ),
  );
}

class _ServiceGuideStepCard extends StatelessWidget {
  const _ServiceGuideStepCard({required this.step, required this.totalSteps});
  final ServiceGuideStep step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Step ${step.number} of $totalSteps. ${step.title}.${step.duration == null ? '' : ' Estimated time ${step.duration}.'}',
    child: _GuideCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP ${step.number} OF $totalSteps',
            style: _DetailText.purposeLabel,
          ),
          const SizedBox(height: 5),
          Text(step.title, style: _DetailText.actionTitle),
          const SizedBox(height: 12),
          const Text('WHAT YOU NEED TO DO', style: _DetailText.guideLabel),
          Text(step.clientAction, style: _DetailText.actionDescription),
          const SizedBox(height: 10),
          const Text('WHAT PACC WILL DO', style: _DetailText.guideLabel),
          Text(step.providerAction, style: _DetailText.actionDescription),
          if (step.duration != null) ...[
            const SizedBox(height: 10),
            Text(
              'Estimated time: ${step.duration}',
              style: _DetailText.guideLabel,
            ),
          ],
          if (step.note != null)
            Text(step.note!, style: _DetailText.actionDescription),
        ],
      ),
    ),
  );
}

class _ServiceGuideCompletionCard extends StatelessWidget {
  const _ServiceGuideCompletionCard({required this.guide});
  final ServiceGuideData guide;

  @override
  Widget build(BuildContext context) => _GuideCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (guide.completionMessage != null)
          Text(guide.completionMessage!, style: _DetailText.actionTitle),
        if (guide.nextOffice != null) ...[
          const SizedBox(height: 8),
          const Text('NEXT OFFICE', style: _DetailText.purposeLabel),
          Text(guide.nextOffice!, style: _DetailText.actionDescription),
        ],
      ],
    ),
  );
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _DetailColors.cardBorder),
    ),
    child: child,
  );
}

class _GuideField extends StatelessWidget {
  const _GuideField({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _DetailText.guideLabel),
        Text(value, style: _DetailText.actionDescription),
      ],
    ),
  );
}

class _GuideBullet extends StatelessWidget {
  const _GuideBullet({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text('• $text', style: _DetailText.actionDescription),
  );
}

class _ServiceActionCard extends StatelessWidget {
  const _ServiceActionCard({
    required this.icon,
    required this.purpose,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String purpose;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _DetailColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _DetailColors.sunSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _DetailColors.text, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(purpose, style: _DetailText.purposeLabel),
                    const SizedBox(height: 4),
                    Text(title, style: _DetailText.actionTitle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(description, style: _DetailText.actionDescription),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: _DetailColors.sun,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          buttonLabel,
                          textAlign: TextAlign.center,
                          style: _DetailText.actionButton,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: _DetailColors.text,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailColors {
  const _DetailColors._();

  static const background = Colors.white;
  static const sun = Color(0xFFFFCD3A);
  static const sunSoft = Color(0xFFFFF5D8);
  static const cardBorder = Color(0xFFF0E5C4);
  static const text = Color(0xFF17120D);
}

class _DetailText {
  const _DetailText._();

  static const headerTitle = TextStyle(
    color: Colors.black,
    fontSize: 17,
    fontWeight: FontWeight.w900,
  );

  static const title = TextStyle(
    color: _DetailColors.text,
    fontSize: 18,
    fontWeight: FontWeight.w900,
  );

  static const body = TextStyle(
    color: _DetailColors.text,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  static const sectionTitle = TextStyle(
    color: _DetailColors.text,
    fontSize: 18,
    fontWeight: FontWeight.w900,
  );

  static const sectionSubtitle = TextStyle(
    color: Color(0xFF6C655D),
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  static const purposeLabel = TextStyle(
    color: Color(0xFF8A6810),
    fontSize: 10,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w800,
  );

  static const guideLabel = TextStyle(
    color: _DetailColors.text,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  static const actionTitle = TextStyle(
    color: _DetailColors.text,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w900,
  );

  static const actionDescription = TextStyle(
    color: Color(0xFF5F5952),
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  static const actionButton = TextStyle(
    color: _DetailColors.text,
    fontSize: 14,
    fontWeight: FontWeight.w800,
  );
}
