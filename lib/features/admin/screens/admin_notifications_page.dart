import 'package:flutter/material.dart';

import '../../../models/app_notification_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';

enum _NotificationFilter { all, appointments, inquiries }

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({
    super.key,
    required this.repository,
    this.notifications,
    required this.onOpenAppointments,
    required this.onOpenInquiries,
  });

  final AdminPortalRepository repository;
  final Stream<List<AppNotificationModel>>? notifications;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenInquiries;

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  late Stream<List<AppNotificationModel>> _notifications;
  _NotificationFilter _filter = _NotificationFilter.all;
  bool _unreadOnly = false;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _notifications =
        widget.notifications ?? widget.repository.watchPortalNotifications();
  }

  @override
  void didUpdateWidget(covariant AdminNotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifications != widget.notifications ||
        oldWidget.repository != widget.repository) {
      _notifications =
          widget.notifications ?? widget.repository.watchPortalNotifications();
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
      28,
      MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
      40,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'New counseling appointments and inquiries requiring attention.',
              style: TextStyle(color: AdminColors.muted),
            ),
            const SizedBox(height: 22),
            StreamBuilder<List<AppNotificationModel>>(
              stream: _notifications,
              initialData: const <AppNotificationModel>[],
              builder: (context, snapshot) {
                if (snapshot.hasError) return const _NotificationError();
                final all = snapshot.requireData;
                final unread = all.where((item) => !item.isRead).toList();
                final visible = all
                    .where((item) {
                      if (_unreadOnly && item.isRead) return false;
                      return switch (_filter) {
                        _NotificationFilter.all => true,
                        _NotificationFilter.appointments =>
                          item.type == 'appointment',
                        _NotificationFilter.inquiries => item.type == 'inquiry',
                      };
                    })
                    .toList(growable: false);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NotificationSummary(
                      all: all.length,
                      unread: unread.length,
                      appointments: all
                          .where((item) => item.type == 'appointment')
                          .length,
                      inquiries: all
                          .where((item) => item.type == 'inquiry')
                          .length,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: _box,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SegmentedButton<_NotificationFilter>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: _NotificationFilter.all,
                                label: Text('All'),
                              ),
                              ButtonSegment(
                                value: _NotificationFilter.appointments,
                                icon: Icon(Icons.calendar_month_outlined),
                                label: Text('Appointments'),
                              ),
                              ButtonSegment(
                                value: _NotificationFilter.inquiries,
                                icon: Icon(Icons.chat_bubble_outline),
                                label: Text('Inquiries'),
                              ),
                            ],
                            selected: {_filter},
                            onSelectionChanged: (value) =>
                                setState(() => _filter = value.first),
                          ),
                          FilterChip(
                            selected: _unreadOnly,
                            label: const Text('Unread only'),
                            avatar: const Icon(
                              Icons.mark_email_unread_outlined,
                              size: 17,
                            ),
                            onSelected: (value) =>
                                setState(() => _unreadOnly = value),
                          ),
                          if (unread.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: _markingAll
                                  ? null
                                  : () => _markAllRead(unread),
                              icon: const Icon(Icons.done_all, size: 18),
                              label: Text(
                                _markingAll ? 'Updating...' : 'Mark all read',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (visible.isEmpty)
                      const _EmptyNotifications()
                    else
                      Container(
                        decoration: _box,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var index = 0; index < visible.length; index++)
                              _NotificationTile(
                                notification: visible[index],
                                showDivider: index < visible.length - 1,
                                onTap: () => _open(visible[index]),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _open(AppNotificationModel notification) async {
    if (!notification.isRead) {
      await widget.repository.markPortalNotificationRead(notification.id);
    }
    if (!mounted) return;
    if (notification.type == 'appointment') {
      widget.onOpenAppointments();
    } else {
      widget.onOpenInquiries();
    }
  }

  Future<void> _markAllRead(List<AppNotificationModel> notifications) async {
    setState(() => _markingAll = true);
    try {
      await Future.wait(
        notifications.map(
          (item) => widget.repository.markPortalNotificationRead(item.id),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to update notifications.')),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }
}

class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({
    required this.all,
    required this.unread,
    required this.appointments,
    required this.inquiries,
  });
  final int all;
  final int unread;
  final int appointments;
  final int inquiries;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 820 ? 4 : 2;
      final width = (constraints.maxWidth - (12 * (columns - 1))) / columns;
      final items = [
        ('All notifications', all, Icons.notifications_none),
        ('Unread', unread, Icons.mark_email_unread_outlined),
        ('Appointments', appointments, Icons.calendar_month_outlined),
        ('Inquiries', inquiries, Icons.chat_bubble_outline),
      ];
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in items)
            Container(
              width: width,
              padding: const EdgeInsets.all(16),
              decoration: _box,
              child: Row(
                children: [
                  Icon(item.$3, color: AdminColors.accentStrong, size: 21),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.$2}',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          item.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.showDivider,
    required this.onTap,
  });
  final AppNotificationModel notification;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: notification.isRead
            ? AdminColors.surface
            : AdminColors.accentFaint,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: notification.type == 'appointment'
                        ? AdminColors.accentSoft
                        : AdminColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    notification.type == 'appointment'
                        ? Icons.calendar_month_outlined
                        : Icons.chat_bubble_outline,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: notification.isRead
                                    ? FontWeight.w700
                                    : FontWeight.w900,
                              ),
                            ),
                          ),
                          if (!notification.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AdminColors.accentStrong,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: const TextStyle(
                          color: AdminColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _relativeTime(notification.createdAt),
                        style: const TextStyle(
                          color: AdminColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AdminColors.muted),
              ],
            ),
          ),
        ),
      ),
      if (showDivider) const Divider(height: 1),
    ],
  );
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
    decoration: _box,
    child: const Column(
      children: [
        Icon(Icons.notifications_none, size: 42, color: AdminColors.muted),
        SizedBox(height: 12),
        Text(
          'No notifications match this filter.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _NotificationError extends StatelessWidget {
  const _NotificationError();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(30),
    decoration: _box,
    child: const Text(
      'Notifications could not be loaded. Check access and try again.',
      textAlign: TextAlign.center,
    ),
  );
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

final _box = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: AdminColors.border),
);
