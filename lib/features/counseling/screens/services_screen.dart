import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/widgets/mindmate_bottom_navigation.dart';
import '../../../routes/route_names.dart';
import 'pacc_counseling_screen.dart';
import 'service_detail_screen.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  static const List<ServiceDetailData> _services = [
    ServiceDetailData(
      title: 'Information Service',
      summary:
          'Guidance and information that help students adjust, feel secure, and belong in the school community.',
      description:
          'This service provides adequate and substantial information related to personal, psychological, social, educational, and vocational fields and benefits new students by helping them acquire the necessary knowledge about the new school, its rules and regulations. Accordingly, this helps students make adjustments and feel a sense of security and belongingness.',
      iconAsset: '📚.png',
      headerColor: Color(0xFFFFCE3C),
      guides: [
        ServiceGuideData(
          title: 'How to Avail This Service',
          eligibleClients:
              'Students, faculty, staff, alumni, parents, and walk-in clients',
          availability: 'Monday-Saturday, 8:00 AM - 5:00 PM',
          personResponsible: 'Guidance Counselor / Counselor-Associate',
          fee: 'None',
          forms: ['General Logsheet'],
          steps: [
            ServiceGuideStep(
              number: 1,
              title: 'Make an Inquiry',
              clientAction:
                  'Visit the PACC office or official Facebook page for your inquiry.',
              providerAction:
                  'Provide the necessary information or refer you to the appropriate office.',
              duration: '2-3 minutes',
            ),
          ],
          completionMessage: 'Transaction Complete',
        ),
      ],
    ),
    ServiceDetailData(
      title: 'Individual Inventory Service',
      summary:
          'Student records and personal information that support self-understanding, decisions, and placement.',
      description:
          'It involves the collection of reliable and intensive information and records of students to facilitate students\' understanding of their own self and help them use such information in decision-making and placement.',
      iconAsset: '📋.png',
      headerColor: Color(0xFFB9C1D3),
      guides: [
        ServiceGuideData(
          title: 'How to Avail This Service',
          eligibleClients: 'Freshmen and Transferees',
          availability: 'Monday-Saturday, 8:00 AM - 5:00 PM',
          personResponsible: 'Guidance Counselor / Counselor-Associate',
          fee: 'None',
          forms: ['Interview Questionnaire', 'Consent to Release Information'],
          requirements: [
            '1 original copy of admission requirements',
            '2 photocopies of admission requirements',
          ],
          steps: [
            ServiceGuideStep(
              number: 1,
              title: 'Complete the Required Forms',
              clientAction:
                  'Fill out the Interview Questionnaire and Consent to Release Information.',
              providerAction:
                  'Provide the Interview Questionnaire and Consent to Release Information.',
              duration: '5-10 minutes',
            ),
            ServiceGuideStep(
              number: 2,
              title: 'Submit Your Requirements',
              clientAction:
                  'Submit completed forms with the required original and photocopies of admission requirements.',
              providerAction:
                  'Check the forms, organize documents, and endorse appropriate copies to the Registrar and College Dean.',
              duration: '3-5 minutes',
            ),
            ServiceGuideStep(
              number: 3,
              title: 'Counselor Interview',
              clientAction:
                  'Answer interview or follow-up questions from the counselor-in-charge.',
              providerAction:
                  'Clarify information on the interview sheet or Consent to Release Information.',
              duration: '3-5 minutes',
            ),
            ServiceGuideStep(
              number: 4,
              title: 'Proceed to the Registrar',
              clientAction:
                  'Proceed to the Registrar for the next enrollment step.',
              providerAction: 'Complete document arrangement and endorsement.',
              duration: '1-2 minutes',
            ),
          ],
          nextOffice: "Registrar's Office",
        ),
      ],
    ),
    ServiceDetailData(
      title: 'Testing Service',
      summary:
          'Psychological and non-psychometric assessment of abilities, aptitude, interests, and personality.',
      description:
          'Using psychological tests and non-psychometric devices, this service is designed to secure accurate information about each student\'s abilities, aptitude, interest, and personality in order to assist students in gaining increasing self-knowledge and understanding of their capacity in as many aspects of their life and career as possible.',
      iconData: Icons.fact_check_outlined,
      headerColor: Color(0xFFA9D8B8),
      guides: [
        ServiceGuideData(
          title: 'How to Avail This Service',
          eligibleClients: 'UCU Employees / Students for OJT',
          availability: 'Monday-Saturday, 8:00 AM - 5:00 PM',
          personResponsible: 'Psychometrician-in-charge',
          fee: 'PHP 250.00',
          forms: [
            'Personal Data Sheet',
            'Informed Consent',
            'Test Battery',
            'Test Report',
          ],
          requirements: [
            'Endorsement Letter',
            'Official receipt of testing fee',
          ],
          steps: [
            ServiceGuideStep(
              number: 1,
              title: 'Submit Testing Requirements',
              clientAction:
                  'Submit the Endorsement Letter from the appropriate UCU office and official receipt of the testing fee.',
              providerAction:
                  'Verify the documents and provide the testing schedule through SMS.',
              duration: '2-5 minutes',
            ),
          ],
        ),
      ],
    ),
    ServiceDetailData(
      title: 'Counseling Service',
      summary:
          'Professional support for personal-social, educational, and psychological concerns.',
      description:
          'This service is considered as the "heart" of the guidance program. Through a dynamic relationship between students and a professionally trained counselor, it is designed to facilitate students in their personal-social, educational, and psychological issues to enhance their intrapersonal and interpersonal development and competencies.',
      iconAsset: '👥.png',
      headerColor: Color(0xFFF2A6A1),
      isCounseling: true,
    ),
    ServiceDetailData(
      title: 'Follow-up Service',
      summary:
          'Continued contact and evaluation after students receive guidance assistance.',
      description:
          'This service helps determine the status of students who received assistance and maintains contact with graduates. It also determines the adequacy and sufficiency of the programs and services extended in meeting the needs of its clientele.',
      iconAsset: '🎯-1.png',
      headerColor: Color(0xFFD9AEAA),
      guides: [
        ServiceGuideData(
          title: 'Adding, Changing & Dropping Subjects',
          eligibleClients: 'Officially Enrolled Students',
          availability: 'Monday-Saturday, 8:00 AM - 5:00 PM',
          personResponsible: 'Guidance Counselor / Counselor-Associate',
          fee: 'None',
          forms: [
            'Adding, Changing or Dropping Form',
            'Student Dropping Record Form when applicable',
          ],
          steps: [
            ServiceGuideStep(
              number: 1,
              title: 'Present Your Form',
              clientAction:
                  'Present the Adding, Changing, or Dropping Form. When dropping all subjects, complete the Student Dropping Record Form.',
              providerAction:
                  'Determine the validity of the reasons on the form and sign it.',
              duration: '1-2 minutes',
            ),
            ServiceGuideStep(
              number: 2,
              title: 'Submit to the Counselor',
              clientAction:
                  'Submit a copy of the form and applicable dropping record to the counselor-in-charge.',
              providerAction:
                  'Receive and sign the form and conduct an interview if necessary.',
              duration: '2-5 minutes',
            ),
          ],
          completionMessage: 'Transaction Complete',
        ),
        ServiceGuideData(
          title: 'Shifting of Course',
          eligibleClients: 'Students',
          availability: 'Monday-Saturday, 8:00 AM - 5:00 PM',
          personResponsible: 'Guidance Counselor / Counselor-Associate',
          fee: 'None',
          steps: [
            ServiceGuideStep(
              number: 1,
              title: 'Complete the Shifting Form',
              clientAction:
                  'Fill out the Shifting Form and be ready to answer questions from the College Dean and counselor.',
              providerAction: 'Provide the Shifting Form.',
              duration: '1-3 minutes',
            ),
            ServiceGuideStep(
              number: 2,
              title: 'Submit Your Documents',
              clientAction:
                  'Submit a copy of the form and applicable dropping record to the counselor-in-charge.',
              providerAction:
                  'Direct you to the next signatories, including PACC and Registrar.',
              duration: '2-5 minutes',
            ),
            ServiceGuideStep(
              number: 3,
              title: 'Return to PACC',
              clientAction:
                  'Return to the counselor-in-charge for the required signature and remarks.',
              providerAction: 'Sign and return the form.',
              duration: '1-2 minutes',
            ),
            ServiceGuideStep(
              number: 4,
              title: 'Complete Document Distribution',
              clientAction:
                  'After the Registrar signs the form, submit required copies to PACC, Registrar, and Accounting.',
              providerAction: 'Receive the PACC copy for proper filing.',
              duration: '1-2 minutes',
            ),
          ],
          completionMessage: 'Process Complete',
        ),
      ],
    ),
    ServiceDetailData(
      title: 'Career Guidance and Placement Service',
      summary:
          'Support in choosing appropriate educational, occupational, or employment paths.',
      description:
          'It offers facilitation of students\' movement to the appropriate educational or occupational level or program in pursuit of further education or other employment upon leaving the organization.',
      iconAsset: '🎯.png',
      headerColor: Color(0xFF8FB8DE),
      guides: [
        ServiceGuideData(
          title: 'Signing of Clearance for Graduation',
          eligibleClients: 'Graduating Students',
          availability: 'Monday-Saturday, 8:00 AM - 5:00 PM',
          personResponsible: 'Guidance Counselor / Counselor-Associate',
          fee: 'None',
          forms: [
            'Graduate Profile Form',
            'Feedback Form',
            'Student Satisfaction Survey',
          ],
          requirements: ['Clearance', 'Resume', 'Application Letter'],
          steps: [
            ServiceGuideStep(
              number: 1,
              title: 'Submit Requirements',
              clientAction:
                  'Present your clearance, resume, and application letter. Complete the Graduate Profile, Feedback Form, and Student Satisfaction Survey through the provided Google Forms.',
              providerAction:
                  'Accept documents for filing, verify your record, and provide Google Form access.',
            ),
            ServiceGuideStep(
              number: 2,
              title: 'Confirm Form Completion',
              clientAction:
                  'Inform the counselor-in-charge after completing the Google Forms.',
              providerAction:
                  'Verify the forms and facilitate the Graduate Profile interview.',
            ),
            ServiceGuideStep(
              number: 3,
              title: 'Clearance Signing',
              clientAction: 'Give the clearance to the counselor for signing.',
              providerAction:
                  'Verify OPE and Jobs Fair requirements and sign the clearance when satisfied.',
            ),
          ],
          completionMessage: 'Clearance Process Complete',
        ),
      ],
      hasSatisfactionSurvey: true,
      hasClientFeedbackForm: true,
    ),
    ServiceDetailData(
      title: 'Referral Service',
      summary:
          'Appropriate action and support for referrals from students, families, faculty, and staff.',
      description:
          'It involves responding and providing appropriate actions to referrals made by parents, faculty, other personnel, and students.',
      iconAsset: '🤝.png',
      headerColor: Color(0xFF83B797),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ServicesColors.background,
      bottomNavigationBar: const MindMateBottomNavigation(
        active: MindMateNavDestination.services,
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _ServicesHeader(
                onBackTap: () => _goBack(context),
                onNotificationTap: () =>
                    _openBlankPage(context, 'Notifications'),
              ),
            ),
            const SliverToBoxAdapter(child: _ServicesIntroCard()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 42),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const _AnimatedServicesSection(
                    delay: 0,
                    child: Text('All Services', style: _ServicesText.heading),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < _services.length; index++) ...[
                    _AnimatedServicesSection(
                      delay: 70 + (index * 45),
                      child: _ServiceCard(
                        service: _services[index],
                        onTap: () =>
                            _openServiceDetail(context, _services[index]),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  _AnimatedServicesSection(
                    delay: 420,
                    child: _SupportServicesCard(
                      onSetAppointment: () => _openPaccCounseling(context),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _openServiceDetail(
    BuildContext context,
    ServiceDetailData service,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: service)),
    );
  }

  static void _openBlankPage(BuildContext context, String title) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _BlankServicesPage(title: title)));
  }

  static void _goBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil(RouteNames.home, (route) => false);
  }

  static void _openPaccCounseling(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PaccCounselingScreen()));
  }
}

class _ServicesHeader extends StatelessWidget {
  const _ServicesHeader({
    required this.onBackTap,
    required this.onNotificationTap,
  });

  final VoidCallback onBackTap;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: _ServicesColors.sun,
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
            onPressed: onBackTap,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          ),
          const _ServicesAssetImage(
            assetName: 'creativity_15557951 1.png',
            width: 32,
            height: 32,
          ),
          const SizedBox(width: 8),
          const _ServicesAssetImage(
            assetName: 'MindMate.png',
            width: 106,
            height: 26,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Notifications',
            onPressed: onNotificationTap,
            icon: const _ServicesAssetImage(
              assetName: 'Notification.png',
              width: 24,
              height: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicesIntroCard extends StatelessWidget {
  const _ServicesIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ServicesAssetImage(
            assetName: 'Love Circled.png',
            width: 41,
            height: 41,
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PACC Services', style: _ServicesText.introTitle),
                SizedBox(height: 4),
                Text(
                  'Psychological Assessment & Counseling Center',
                  style: _ServicesText.introSubtitle,
                ),
                SizedBox(height: 14),
                Text(
                  'Comprehensive mental health support services for the UCU community',
                  style: _ServicesText.introBody,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});

  final ServiceDetailData service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${service.title}. ${service.summary}. Opens service details.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            decoration: _ServicesDecor.card(radius: 8),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: service.headerColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: service.iconData != null
                      ? Icon(service.iconData, size: 24, color: Colors.black87)
                      : _ServicesAssetImage(
                          assetName: service.iconAsset!,
                          width: 24,
                          height: 24,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.title, style: _ServicesText.cardTitle),
                      const SizedBox(height: 4),
                      Text(service.summary, style: _ServicesText.cardSummary),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black45,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportServicesCard extends StatelessWidget {
  const _SupportServicesCard({required this.onSetAppointment});

  final VoidCallback onSetAppointment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(top: 22, right: -28, child: _SupportBubble(size: 54)),
        const Positioned(
          bottom: -25,
          left: -30,
          child: _SupportBubble(size: 44),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PACC Support Service',
              style: _ServicesText.supportTitle,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _ServicesColors.sun, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      _ServicesAssetImage(
                        assetName: 'Yellow Heart.png',
                        width: 42,
                        height: 32,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Need Immediate Help?',
                          style: _ServicesText.helpTitle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'PACC counselors are available to support you. Contact us for appointments or urgent assistance.',
                    style: _ServicesText.helpBody,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: _RoundedYellowButton(
                      label: 'Set Appointment',
                      onTap: onSetAppointment,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SupportBubble extends StatelessWidget {
  const _SupportBubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFFFF4D8),
      ),
    );
  }
}

class _RoundedYellowButton extends StatelessWidget {
  const _RoundedYellowButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _ServicesColors.sun,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: _ServicesText.contactButton,
          ),
        ),
      ),
    );
  }
}

class _ServicesAssetImage extends StatelessWidget {
  const _ServicesAssetImage({
    required this.assetName,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  final String assetName;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      '${AppAssets.servicesImages}/$assetName',
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) {
        return SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.image_not_supported_outlined),
        );
      },
    );
  }
}

class _AnimatedServicesSection extends StatelessWidget {
  const _AnimatedServicesSection({required this.child, required this.delay});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _BlankServicesPage extends StatelessWidget {
  const _BlankServicesPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ServicesColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _ServicesColors.sun,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SizedBox.expand(),
    );
  }
}

class _ServicesColors {
  const _ServicesColors._();

  static const background = Colors.white;
  static const sun = Color(0xFFFFCD3A);
}

class _ServicesText {
  const _ServicesText._();

  static const heading = TextStyle(
    color: _ServicesColors.sun,
    fontSize: 20,
    fontWeight: FontWeight.w900,
  );

  static const introTitle = TextStyle(
    color: _ServicesColors.sun,
    fontSize: 20,
    fontWeight: FontWeight.w900,
  );

  static const introSubtitle = TextStyle(
    color: _ServicesColors.sun,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const introBody = TextStyle(
    color: _ServicesColors.sun,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  static const cardTitle = TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  );

  static const cardSummary = TextStyle(
    color: Colors.black54,
    fontSize: 11,
    height: 1.25,
    fontWeight: FontWeight.w500,
  );

  static const supportTitle = TextStyle(
    color: Colors.black,
    fontSize: 16,
    fontWeight: FontWeight.w900,
  );

  static const helpTitle = TextStyle(
    color: Colors.black,
    fontSize: 16,
    fontWeight: FontWeight.w900,
  );

  static const helpBody = TextStyle(
    color: Colors.black,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static const contactButton = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w900,
  );
}

class _ServicesDecor {
  const _ServicesDecor._();

  static BoxDecoration card({double radius = 10}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 10,
          offset: Offset(0, 5),
        ),
      ],
    );
  }
}
