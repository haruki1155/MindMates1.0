import 'package:flutter/material.dart';

import '../../../core/widgets/mindmate_terms_and_conditions.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About MindMate')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const Icon(Icons.spa_outlined, size: 48, color: Color(0xFF8A6C1E)),
        const SizedBox(height: 16),
        const Text(
          'MindMate supports mental health awareness, reflection, and access to counseling resources.',
          style: TextStyle(
            fontSize: 18,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'MindMate does not replace professional care. For urgent concerns, contact PACC Counseling Services.',
          style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF555555)),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const ValueKey('about-terms-button'),
          onPressed: () => showMindMateTermsAndConditions(context),
          icon: const Icon(Icons.gavel_outlined),
          label: const Text('Terms and Conditions'),
        ),
      ],
    ),
  );
}
