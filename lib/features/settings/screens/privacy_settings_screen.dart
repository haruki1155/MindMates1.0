import 'package:flutter/material.dart';

import '../../../routes/route_names.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy settings')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text(
          'Manage the optional data choices available in MindMate.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 8),
        const Text(
          'These controls do not turn off assessment or appointment records.',
          style: TextStyle(color: Color(0xFF686868), height: 1.4),
        ),
        const SizedBox(height: 20),
        _PrivacyOption(
          icon: Icons.psychology_outlined,
          title: 'MindAid AI privacy settings',
          description:
              'Review whether MindAid uses the local assistant or personalized AI.',
          onTap: () => Navigator.of(context).pushNamed(RouteNames.mindAid),
        ),
        const SizedBox(height: 12),
        _PrivacyOption(
          icon: Icons.bedtime_outlined,
          title: 'Sleep diary storage',
          description:
              'Choose whether sleep entries stay on this device or sync across devices.',
          onTap: () => Navigator.of(context).pushNamed(RouteNames.sleepQuality),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F4EF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'MindMate currently provides these feature-specific controls. It does not provide an in-app data export or deletion request here.',
            style: TextStyle(height: 1.45, color: Color(0xFF4A4A4A)),
          ),
        ),
      ],
    ),
  );
}

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE8E4DC)),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, color: const Color(0xFF5E4A16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(description, style: const TextStyle(height: 1.35)),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
