import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../routes/route_names.dart';
import '../../../routes/mindmate_back_navigation.dart';
import '../../home/widgets/home_dashboard_widgets.dart';
import '../widgets/counselor_unread_badges.dart';
import '../widgets/messaging_dashboard_theme.dart';

/// AI support and manual PACC counseling remain separate conversations.
class MessagesHubScreen extends StatelessWidget {
  const MessagesHubScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      MessagingDashboardTheme(child: Builder(builder: _buildMessages));

  Widget _buildMessages(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => MindMateBackNavigation.backToHome(context),
        ),
        title: const Text('Messages'),
      ),
      body: ListView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 360 ? 12 : 18,
        ),
        children: [
          Text(
            'Conversations',
            style: HomeTextStyles.sectionTitle.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            key: const Key('conversation_list'),
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _ConversationEntry(
                  itemKey: const Key('messages_counselor'),
                  icon: Icons.support_agent_outlined,
                  title: 'Guidance Assistant',
                  subtitle: 'PACC counselor',
                  preview: const _CounselorPreview(),
                  badge: const StudentCounselorUnreadBadge(
                    backgroundColor: HomePalette.sun,
                    foregroundColor: HomePalette.text,
                  ),
                  onTap: () =>
                      Navigator.of(context).pushNamed(RouteNames.counselorChat),
                ),
                Divider(
                  height: 1,
                  indent: HomeMetrics.cardPadding + 40 + 12,
                  endIndent: HomeMetrics.cardPadding,
                  color: theme.colorScheme.outlineVariant,
                ),
                _ConversationEntry(
                  itemKey: const Key('messages_mindaid'),
                  icon: Icons.smart_toy_outlined,
                  title: 'MindAid',
                  subtitle: 'AI companion for everyday support.',
                  onTap: () =>
                      Navigator.of(context).pushNamed(RouteNames.mindAid),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'MindAid is AI support. Guidance Assistant connects you with a human PACC counselor. Neither is a live emergency service.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
    this.preview,
    this.badge,
  });
  final Key itemKey;
  final IconData icon;
  final String title, subtitle;
  final Widget? preview;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: itemKey,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: Padding(
          padding: const EdgeInsets.all(HomeMetrics.cardPadding),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: HomePalette.sun,
                  borderRadius: BorderRadius.circular(HomeMetrics.radiusSmall),
                ),
                child: Icon(icon, size: 22, color: HomePalette.text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: HomeTextStyles.cardTitle.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: HomeTextStyles.bodyMuted.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: 6),
                      preview!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (badge != null) ...[badge!, const SizedBox(width: 4)],
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CounselorPreview extends StatelessWidget {
  const _CounselorPreview();
  @override
  Widget build(BuildContext context) {
    final style = HomeTextStyles.bodyMuted.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    const empty = 'Start a private conversation with PACC.';
    final uid = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Text(
        empty,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('counselor_threads')
          .doc(uid)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final text = snapshot.data?.docs.firstOrNull?.data()['text'];
        final preview = snapshot.hasError
            ? 'Preview unavailable. Tap to open your conversation.'
            : !snapshot.hasData
            ? 'Loading your conversation…'
            : text is String && text.isNotEmpty
            ? text
            : empty;
        return Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}
