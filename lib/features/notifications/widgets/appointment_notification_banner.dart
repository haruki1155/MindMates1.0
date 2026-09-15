import 'package:flutter/material.dart';

void showAppointmentNotificationBanner(
  BuildContext context, {
  required String title,
  required String message,
  String? appointmentId,
  VoidCallback? onView,
}) {
  final style = _styleFor('$title $message');
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.white,
      elevation: 8,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: style.color.withValues(alpha: .35)),
      ),
      duration: Duration(seconds: style.actionRequired ? 6 : 5),
      content: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(style.icon, color: style.color),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF201A17),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF5F5952),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (appointmentId != null && onView != null)
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                onView();
              },
              child: const Text('View'),
            ),
        ],
      ),
    ),
  );
}

({IconData icon, Color color, bool actionRequired}) _styleFor(String text) {
  final value = text.toLowerCase();
  if (value.contains('reschedule') || value.contains('schedule change')) {
    return (
      icon: Icons.event_repeat_outlined,
      color: const Color(0xFFAD6700),
      actionRequired: true,
    );
  }
  if (value.contains('cancel')) {
    return (
      icon: Icons.event_busy_outlined,
      color: const Color(0xFFB3261E),
      actionRequired: false,
    );
  }
  if (value.contains('remind')) {
    return (
      icon: Icons.alarm_outlined,
      color: const Color(0xFF496A9B),
      actionRequired: false,
    );
  }
  return (
    icon: Icons.event_available_outlined,
    color: const Color(0xFF287953),
    actionRequired: false,
  );
}
