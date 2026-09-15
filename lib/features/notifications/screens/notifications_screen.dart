import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_notification_model.dart';
import '../../../providers/appointment_provider.dart';
import '../../../repositories/notification_repository.dart';
import '../../counseling/widgets/appointment_details_sheet.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({required this.userId, super.key, this.repository});

  final String userId;
  final NotificationRepository? repository;

  @override
  Widget build(BuildContext context) {
    final source = repository ?? NotificationRepository();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          StreamBuilder<List<AppNotificationModel>>(
            stream: source.watchNotifications(userId),
            builder: (context, snapshot) {
              final unread =
                  snapshot.data?.where((item) => !item.isRead).toList() ??
                  const [];
              if (unread.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => source.markAllRead(unread),
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotificationModel>>(
        stream: source.watchNotifications(userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load notifications.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) return const _NotificationEmptyState();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                color: item.isRead ? Colors.white : const Color(0xFFFFF8E5),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: CircleAvatar(
                    backgroundColor: _notificationColor(
                      item,
                    ).withValues(alpha: .14),
                    child: Icon(
                      _notificationIcon(item),
                      color: _notificationColor(item),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: item.isRead
                                ? FontWeight.w600
                                : FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!item.isRead)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.circle,
                            size: 9,
                            color: Color(0xFFFFB800),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: item.isRead
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_relativeTime(item.createdAt)} · ${item.isRead ? 'Read' : 'Unread'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (!item.isRead) await source.markRead(item.id);
                    final appointmentId = item.appointmentId;
                    if (!context.mounted || appointmentId == null) return;
                    final appointment = context
                        .read<AppointmentProvider>()
                        .appointments
                        .where((entry) => entry.id == appointmentId)
                        .firstOrNull;
                    if (appointment == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'This appointment is no longer available.',
                          ),
                        ),
                      );
                      return;
                    }
                    showAppointmentDetailsSheet(context, appointment);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 52, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'No notifications yet',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            'Appointment confirmations, schedule changes,\nand reminders will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

IconData _notificationIcon(AppNotificationModel item) {
  final type = item.type.toLowerCase();
  if (type.contains('reschedule')) return Icons.event_repeat_outlined;
  if (type.contains('cancel')) return Icons.event_busy_outlined;
  if (type.contains('reminder')) return Icons.alarm_outlined;
  if (type.contains('confirm')) return Icons.event_available_outlined;
  return Icons.notifications_outlined;
}

Color _notificationColor(AppNotificationModel item) {
  final type = item.type.toLowerCase();
  if (type.contains('reschedule')) return const Color(0xFFAD6700);
  if (type.contains('cancel')) return const Color(0xFFB3261E);
  if (type.contains('reminder')) return const Color(0xFF496A9B);
  if (type.contains('confirm')) return const Color(0xFF287953);
  return const Color(0xFF606B78);
}

String _relativeTime(DateTime value) {
  final age = DateTime.now().difference(value);
  if (age.inMinutes < 1) return 'Just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return 'Today, ${_clock(value)}';
  if (age.inDays == 1) return 'Yesterday, ${_clock(value)}';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _clock(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour < 12 ? 'AM' : 'PM'}';
}
