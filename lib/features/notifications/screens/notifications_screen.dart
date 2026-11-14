import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_notification_model.dart';
import '../../../providers/appointment_provider.dart';
import '../../../repositories/notification_repository.dart';
import '../../counseling/widgets/appointment_details_sheet.dart';

// Feature-only colors, aligned with the Appointment V2 surfaces.
class _NotificationV2Palette {
  const _NotificationV2Palette._();
  static const background = Color(0xFFF7F8F4);
  static const ink = Color(0xFF1D343C);
  static const muted = Color(0xFF73878E);
  static const border = Color(0xFFE5EAE5);
  static const gold = Color(0xFFF8BF3C);
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({required this.userId, super.key, this.repository});

  final String userId;
  final NotificationRepository? repository;

  @override
  Widget build(BuildContext context) {
    final source = repository ?? NotificationRepository();
    return Scaffold(
      backgroundColor: _NotificationV2Palette.background,
      appBar: AppBar(
        toolbarHeight: 100,
        backgroundColor: _NotificationV2Palette.background,
        foregroundColor: _NotificationV2Palette.ink,
        surfaceTintColor: Colors.transparent,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PACC COUNSELING', style: TextStyle(color: Color(0xFFA17720), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('Notifications', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _NotificationV2Palette.ink)),
        ]),
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
                style: TextButton.styleFrom(
                  foregroundColor: _NotificationV2Palette.ink,
                  minimumSize: const Size(48, 48),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Unable to load notifications.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: _NotificationV2Palette.muted,
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) return const _NotificationEmptyState();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                key: ValueKey('notification-${item.id}'),
                margin: EdgeInsets.zero,
                elevation: 0,
                color: item.isRead ? Colors.white : const Color(0xFFFFFAEB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: _NotificationV2Palette.border),
                ),
                child: ListTile(
                  minVerticalPadding: 14,
                  contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                            color: _NotificationV2Palette.ink,
                            fontSize: 16,
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
                            color: _NotificationV2Palette.gold,
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
                          fontSize: 14,
                          height: 1.4,
                          color: _NotificationV2Palette.ink,
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
                          color: _NotificationV2Palette.muted,
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: _NotificationV2Palette.muted,
                  ),
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
          Icon(
            Icons.notifications_none,
            size: 52,
            color: _NotificationV2Palette.muted,
          ),
          SizedBox(height: 14),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              color: _NotificationV2Palette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Appointment confirmations, schedule changes,\nand reminders will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _NotificationV2Palette.muted,
              height: 1.4,
            ),
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
