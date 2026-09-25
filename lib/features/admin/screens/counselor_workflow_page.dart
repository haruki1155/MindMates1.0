import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';

enum CounselorWorkflowMode { cases, followUps }

class CounselorWorkflowPage extends StatelessWidget {
  const CounselorWorkflowPage({
    super.key,
    required this.repository,
    required this.mode,
    required this.onOpenAppointments,
  });

  final AdminPortalRepository repository;
  final CounselorWorkflowMode mode;
  final VoidCallback onOpenAppointments;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppointmentModel>>(
    stream: repository.watchAppointments(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('We could not load your assigned counseling work.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = mode == CounselorWorkflowMode.cases
          ? _cases(snapshot.data!)
          : _followUps(snapshot.data!);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode == CounselorWorkflowMode.cases
                      ? 'My Cases'
                      : 'Follow-ups',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mode == CounselorWorkflowMode.cases
                      ? 'Continue assigned counseling work with privacy-safe student identifiers.'
                      : 'Review actual post-session follow-up offers and bookings.',
                  style: const TextStyle(color: AdminColors.muted),
                ),
                const SizedBox(height: 24),
                _Summary(
                  items: items,
                  followUps: mode == CounselorWorkflowMode.followUps,
                ),
                const SizedBox(height: 18),
                if (items.isEmpty)
                  _EmptyState(
                    followUps: mode == CounselorWorkflowMode.followUps,
                    onOpenAppointments: onOpenAppointments,
                  )
                else
                  ...items.map(
                    (appointment) => _WorkCard(
                      appointment: appointment,
                      followUp: mode == CounselorWorkflowMode.followUps,
                      onOpenAppointments: onOpenAppointments,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  static List<AppointmentModel> _cases(List<AppointmentModel> values) {
    final seen = <String>{};
    return values
        .where((item) => item.userId.isNotEmpty && seen.add(item.userId))
        .toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
  }

  static List<AppointmentModel> _followUps(List<AppointmentModel> values) =>
      values
          .where(
            (item) =>
                item.followUpRecommended &&
                const {
                  'offered',
                  'booked',
                }.contains(item.followUpStatus.toLowerCase().trim()),
          )
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
}

class _Summary extends StatelessWidget {
  const _Summary({required this.items, required this.followUps});
  final List<AppointmentModel> items;
  final bool followUps;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _Metric(
          label: followUps ? 'Needs action' : 'Assigned cases',
          value: '${items.length}',
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _Metric(label: 'Privacy scope', value: 'Assigned only'),
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AdminColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    required this.appointment,
    required this.followUp,
    required this.onOpenAppointments,
  });
  final AppointmentModel appointment;
  final bool followUp;
  final VoidCallback onOpenAppointments;
  @override
  Widget build(BuildContext context) {
    final id = appointment.userId;
    final suffix = id.length > 4 ? id.substring(id.length - 4) : id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AdminColors.accentSoft,
            child: Text(
              '••••$suffix',
              style: const TextStyle(fontSize: 10, color: AdminColors.ink),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Student ••••$suffix',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_date(appointment.scheduledAt)} · ${appointment.scheduledTime.isEmpty ? _time(appointment.scheduledAt) : appointment.scheduledTime}',
                  style: const TextStyle(color: AdminColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  followUp
                      ? appointment.followUpStatus.toLowerCase().trim() ==
                                'booked'
                            ? 'Follow-up booked'
                            : 'Follow-up offered - waiting for client'
                      : 'Assigned counseling case',
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onOpenAppointments,
            child: const Text('Open appointment'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.followUps,
    required this.onOpenAppointments,
  });
  final bool followUps;
  final VoidCallback onOpenAppointments;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          followUps ? 'No follow-ups due' : 'No active cases',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          followUps
              ? "You're up to date with your assigned follow-up work."
              : 'No counseling cases are currently assigned to you.',
          style: const TextStyle(color: AdminColors.muted),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: onOpenAppointments,
          child: const Text('View appointments'),
        ),
      ],
    ),
  );
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _time(DateTime value) =>
    '${value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour}:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
