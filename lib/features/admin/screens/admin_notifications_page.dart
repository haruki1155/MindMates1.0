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
  bool _showArchived = false;
  String? _busyId;
  final Set<String> _selectedIds = <String>{};

  Stream<List<AppNotificationModel>> _source() =>
      !_showArchived && widget.notifications != null
      ? widget.notifications!
      : _showArchived
      ? widget.repository.watchArchivedPortalNotifications()
      : widget.repository.watchPortalNotifications();

  @override
  void initState() {
    super.initState();
    _notifications = _source();
  }

  @override
  void didUpdateWidget(covariant AdminNotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifications != widget.notifications ||
        oldWidget.repository != widget.repository) {
      _notifications = _source();
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
                      if (!_showArchived && _unreadOnly && item.isRead) return false;
                      return switch (_filter) {
                        _NotificationFilter.all => true,
                        _NotificationFilter.appointments =>
                          item.type == 'appointment',
                        _NotificationFilter.inquiries => item.type == 'inquiry',
                      };
                    })
                    .toList(growable: false);
                _selectedIds.removeWhere(
                  (id) => !visible.any((item) => item.id == id),
                );
                final selectable = visible
                    .where((item) => _canBulkManage(item))
                    .toList(growable: false);
                final allSelected = selectable.isNotEmpty &&
                    selectable.every((item) => _selectedIds.contains(item.id));
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
                            onSelected: _showArchived
                                ? null
                                : (value) => setState(() => _unreadOnly = value),
                          ),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: false, label: Text('Active')),
                              ButtonSegment(value: true, label: Text('Archived')),
                            ],
                            selected: {_showArchived},
                            onSelectionChanged: (value) {
                              setState(() {
                                _showArchived = value.first;
                                _unreadOnly = false;
                                _notifications = _source();
                              });
                            },
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: allSelected,
                                tristate: _selectedIds.isNotEmpty && !allSelected,
                                onChanged: selectable.isEmpty
                                    ? null
                                    : (_) => setState(() {
                                        if (allSelected) {
                                          _selectedIds.removeAll(
                                            selectable.map((item) => item.id),
                                          );
                                        } else {
                                          _selectedIds.addAll(
                                            selectable.map((item) => item.id),
                                          );
                                        }
                                      }),
                              ),
                              Text('Select all${selectable.isEmpty ? '' : ' (${selectable.length})'}'),
                            ],
                          ),
                          if (_selectedIds.isNotEmpty) ...[
                            if (_showArchived)
                              OutlinedButton.icon(
                                onPressed: _busyId == null
                                    ? () => _bulkManage('restore')
                                    : null,
                                icon: const Icon(Icons.unarchive_outlined, size: 18),
                                label: const Text('Restore selected'),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: _busyId == null
                                    ? () => _bulkManage('archive')
                                    : null,
                                icon: const Icon(Icons.archive_outlined, size: 18),
                                label: const Text('Archive selected'),
                              ),
                            OutlinedButton.icon(
                              onPressed: _busyId == null
                                  ? () => _bulkManage('delete')
                                  : null,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete selected'),
                            ),
                          ],
                          if (!_showArchived && unread.isNotEmpty)
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
                                busy: _busyId == visible[index].id,
                                actionsEnabled: _busyId == null,
                                onArchive: visible[index].isRead ||
                                        visible[index].resolvedAt != null
                                    ? () => _manage(visible[index], 'archive')
                                    : null,
                                onRestore: () => _manage(visible[index], 'restore'),
                                onDelete: visible[index].isRead ||
                                        visible[index].resolvedAt != null
                                    ? () => _manage(visible[index], 'delete')
                                    : null,
                                selected: _selectedIds.contains(visible[index].id),
                                selectable: _canBulkManage(visible[index]),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _selectedIds.add(visible[index].id);
                                  } else {
                                    _selectedIds.remove(visible[index].id);
                                  }
                                }),
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

  Future<void> _manage(AppNotificationModel notification, String action) async {
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete notification?'),
          content: const Text('This notification will be permanently removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busyId = notification.id);
    try {
      await widget.repository.managePortalNotification(
        notification.id,
        action: action,
      );
      if (!mounted) return;
      final message = switch (action) {
        'archive' => 'Notification archived.',
        'restore' => 'Notification restored.',
        _ => 'Notification deleted.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the notification. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  bool _canBulkManage(AppNotificationModel notification) =>
      _showArchived || notification.isRead || notification.resolvedAt != null;

  Future<void> _bulkManage(String action) async {
    final ids = _selectedIds.toList(growable: false);
    if (ids.isEmpty) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Delete ${ids.length} notifications?'),
          content: const Text('The selected notifications will be permanently removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busyId = 'bulk');
    try {
      await widget.repository.managePortalNotifications(ids, action: action);
      if (!mounted) return;
      setState(() => _selectedIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(switch (action) {
          'archive' => '${ids.length} notifications archived.',
          'restore' => '${ids.length} notifications restored.',
          _ => '${ids.length} notifications deleted.',
        })),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the selected notifications. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
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
    required this.busy,
    required this.actionsEnabled,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.selected,
    required this.selectable,
    required this.onSelected,
  });
  final AppNotificationModel notification;
  final bool showDivider;
  final VoidCallback onTap;
  final bool busy;
  final bool actionsEnabled;
  final VoidCallback? onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDelete;
  final bool selected;
  final bool selectable;
  final ValueChanged<bool> onSelected;

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
                Checkbox(
                  value: selected,
                  onChanged: selectable
                      ? (value) => onSelected(value ?? false)
                      : null,
                ),
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
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: 'Notification actions',
                    enabled: actionsEnabled,
                    onSelected: (action) {
                      switch (action) {
                        case 'archive':
                          onArchive?.call();
                        case 'restore':
                          onRestore();
                        case 'delete':
                          onDelete?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      if (notification.isArchived)
                        const PopupMenuItem(value: 'restore', child: Text('Restore'))
                      else if (onArchive != null)
                        const PopupMenuItem(value: 'archive', child: Text('Archive')),
                      if (onDelete != null)
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
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
