import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef HelpEmailLauncher = Future<bool> Function(Uri uri);

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, this.launchEmail});

  final HelpEmailLauncher? launchEmail;

  static const _topics = <(String, String)>[
    (
      'Account and profile',
      'Update the profile details available from your Profile screen. If you cannot sign in, use the recovery options on the sign-in screen.',
    ),
    (
      'Assessments',
      'Use the assessment screens to review instructions and submit your responses. Assessment results are available from your Profile when they have loaded.',
    ),
    (
      'Mood and Sleep',
      'Log a Mood check-in from the Mood screen. Sleep entries can stay on your device or sync to your account according to the choice in Sleep Quality settings.',
    ),
    (
      'Appointments and inquiries',
      'Use Services to send an inquiry or request an appointment. Review replies and appointment updates from their existing screens and your notifications.',
    ),
    (
      'MindAid',
      'MindAid is an automated, non-clinical wellness assistant. It is not monitored in real time and does not replace professional care or emergency services.',
    ),
    (
      'Notifications and reminders',
      'Appointment reminders are on by default. Daily Mood and breathing reminders are optional. If device notifications are off, reminders can still appear in the in-app inbox.',
    ),
    (
      'Privacy',
      'Privacy Settings links to the existing MindAid AI and Sleep diary choices. These controls do not turn off assessment or appointment records.',
    ),
  ];

  Future<void> _contact(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: 'pacc@ucu.edu.ph');
    try {
      final launch = launchEmail;
      final opened = launch == null
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : await launch(uri);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app is available.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open your email app.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text(
          'Quick answers for common MindMate features.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 16),
        for (final (title, answer) in _topics)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE8E4DC)),
            ),
            child: ExpansionTile(
              key: ValueKey(
                'help-faq-${title.toLowerCase().replaceAll(' ', '-')}',
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(answer, style: const TextStyle(height: 1.45))],
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _contact(context),
            icon: const Icon(Icons.email_outlined),
            label: const Text('Email PACC Counseling Services'),
          ),
        ),
      ],
    ),
  );
}
