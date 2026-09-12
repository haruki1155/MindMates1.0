import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import 'client_feedback_form_screen.dart';
import 'guidance_satisfaction_survey_screen.dart';
import 'pacc_counseling_screen.dart';

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
                            'Set a preferred date and time to discuss personal, academic, social, or emotional concerns with a PAACC counselor.',
                        buttonLabel: 'Set Appointment',
                        onTap: () => _openPaccCounseling(context),
                      ),
                    ],
                    if (service.hasReactivationProcedure) ...[
                      const SizedBox(height: 32),
                      const _DetailSectionHeading(
                        title: 'Reactivation of Enrollment',
                        subtitle:
                            'The reactivation process helps returning students resume their enrollment after a leave or period of inactivity. Detailed requirements and procedures will be added here soon.',
                      ),
                      const SizedBox(height: 18),
                      const _ProcedureStepsPlaceholder(
                        stepsKey: ValueKey('reactivation-procedure-steps'),
                        semanticLabel: 'Three-step reactivation procedure',
                      ),
                    ],
                    if (service.hasShiftingProcedure) ...[
                      const SizedBox(height: 32),
                      const _DetailSectionHeading(
                        title: 'Student Shifting',
                        subtitle:
                            'The shifting process helps students request a transfer from their current academic program to another program. Detailed requirements and procedures will be added here soon.',
                      ),
                      const SizedBox(height: 18),
                      const _ProcedureStepsPlaceholder(
                        stepsKey: ValueKey('shifting-procedure-steps'),
                        semanticLabel: 'Three-step shifting procedure',
                      ),
                    ],
                    if (service.hasSatisfactionSurvey ||
                        service.hasClientFeedbackForm) ...[
                      const SizedBox(height: 32),
                      const _DetailSectionHeading(
                        title: 'Available Forms',
                        subtitle:
                            'Select the form that matches your request. Your information will help PAACC review and guide your next steps.',
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (service.hasSatisfactionSurvey) ...[
                      _ServiceActionCard(
                        icon: Icons.rate_review_outlined,
                        purpose: 'SERVICE EVALUATION',
                        title: 'Guidance Services Student Satisfaction',
                        description:
                            'Rate your experience with the university guidance services. Your responses help PAACC evaluate service quality and identify areas for improvement.',
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

class _ProcedureStepsPlaceholder extends StatelessWidget {
  const _ProcedureStepsPlaceholder({
    required this.stepsKey,
    required this.semanticLabel,
  });

  final Key stepsKey;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: stepsKey,
      label: semanticLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: _DetailColors.sunSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _DetailColors.cardBorder),
        ),
        child: Row(
          children: [
            for (var step = 1; step <= 3; step++) ...[
              _ProcedureStepNumber(step: step),
              if (step < 3)
                const Expanded(
                  child: Divider(
                    color: _DetailColors.sun,
                    thickness: 2,
                    height: 2,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcedureStepNumber extends StatelessWidget {
  const _ProcedureStepNumber({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _DetailColors.sun,
        shape: BoxShape.circle,
      ),
      child: Text('$step', style: _DetailText.stepNumber),
    );
  }
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

  static const stepNumber = TextStyle(
    color: _DetailColors.text,
    fontSize: 16,
    fontWeight: FontWeight.w900,
  );

  static const actionButton = TextStyle(
    color: _DetailColors.text,
    fontSize: 14,
    fontWeight: FontWeight.w800,
  );
}
