import 'package:flutter/material.dart';
import '../../../routes/route_names.dart';
import '../../../routes/mindmate_back_navigation.dart';
import '../widgets/counselor_unread_badges.dart';

/// Keeps AI support and human counseling in separate conversations.
/// Colors, typography and surfaces are inherited from the active MindMate theme.
class MessagesHubScreen extends StatelessWidget {
  const MessagesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => MindMateBackNavigation.backToHome(context),
        ),
        title: const Text('Messages'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _ConversationEntry(
            itemKey: const Key('messages_mindaid'),
            icon: Icons.smart_toy_outlined,
            title: 'Chat Bot (MindAid)',
            subtitle: 'Mental health support and MindMate guidance',
            onTap: () => Navigator.of(context).pushNamed(RouteNames.mindAid),
          ),
          Divider(height: 1, color: theme.dividerColor),
          _ConversationEntry(
            itemKey: const Key('messages_counselor'),
            icon: Icons.support_agent_outlined,
            title: 'Guidance Assistant',
            badge: const StudentCounselorUnreadBadge(),
            subtitle: 'Private conversation with PACC',
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.counselorChat),
          ),
          const SizedBox(height: 16),
          Text(
            'AI and counselor conversations are separate. MindAid does not replace professional counseling.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ConversationEntry extends StatelessWidget {
  const _ConversationEntry({
    required this.itemKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final Key itemKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: itemKey,
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) badge!,
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
