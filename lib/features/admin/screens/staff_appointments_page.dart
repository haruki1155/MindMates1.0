import 'package:flutter/material.dart';

import '../../../models/appointment_queue_item.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/portal_appointment_metrics.dart';
import '../theme/admin_theme.dart';

/// Operational appointment workspace. It uses only the staff-safe queue
/// projection and deliberately has no clinical detail or mutation controls.
class StaffAppointmentsPage extends StatefulWidget {
  const StaffAppointmentsPage({super.key, required this.repository});

  final AdminPortalRepository repository;

  @override
  State<StaffAppointmentsPage> createState() => _StaffAppointmentsPageState();
}

class _StaffAppointmentsPageState extends State<StaffAppointmentsPage> {
  String _filter = 'Needs action';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'Appointments',
    subtitle: 'Operational PACC schedule. Clinical details are not shown.',
    child: StreamBuilder<List<AppointmentQueueItem>>(
      stream: widget.repository.watchPortalAppointmentQueue(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Message('Unable to load appointments.');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final records = snapshot.data!;
        final metrics = PortalAppointmentMetrics.fromQueue(records, now);
        final query = _search.text.trim().toLowerCase();
        final visible = records.where((item) {
          if (!_matches(item, now, _filter)) return false;
          return query.isEmpty ||
              item.studentDisplayName.toLowerCase().contains(query) ||
              (item.assignedCounselor ?? '').toLowerCase().contains(query);
        }).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in [
                  ('Needs action', metrics.needsAction),
                  ('Today', metrics.today),
                  ('Upcoming', metrics.upcoming),
                  ('Completed', metrics.completed),
                ])
                  ChoiceChip(
                    label: Text('${item.$1} ${item.$2}'),
                    selected: _filter == item.$1,
                    onSelected: (_) => setState(() => _filter = item.$1),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search student or counselor',
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (visible.isEmpty)
              const _Message('No appointments match this view.')
            else
              _Table(items: visible),
          ],
        );
      },
    ),
  );
}

bool _matches(AppointmentQueueItem item, DateTime now, String filter) {
  final status = item.status.trim().toLowerCase();
  final day = DateTime(
    item.scheduledAt.year,
    item.scheduledAt.month,
    item.scheduledAt.day,
  );
  final today = DateTime(now.year, now.month, now.day);
  return switch (filter) {
    'Completed' => status == 'completed',
    'Today' => !item.isArchived && status == 'confirmed' && day == today,
    'Upcoming' =>
      !item.isArchived && status == 'confirmed' && day.isAfter(today),
    _ =>
      !item.isArchived &&
          status != 'completed' &&
          !(status == 'confirmed' && (day == today || day.isAfter(today))),
  };
}

class _Table extends StatelessWidget {
  const _Table({required this.items});
  final List<AppointmentQueueItem> items;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Student',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: Text(
                  'Date & time',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: Text(
                  'Assigned counselor',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text('Status', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.studentDisplayName.isEmpty
                        ? 'Student'
                        : item.studentDisplayName,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${item.scheduledAt.year}-${item.scheduledAt.month.toString().padLeft(2, '0')}-${item.scheduledAt.day.toString().padLeft(2, '0')} ${item.scheduledTime}',
                  ),
                ),
                Expanded(child: Text(item.assignedCounselor ?? 'Unassigned')),
                Text(item.status.isEmpty ? 'Scheduled' : item.status),
              ],
            ),
          ),
      ],
    ),
  );
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: AdminColors.muted)),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: AdminColors.muted));
}
