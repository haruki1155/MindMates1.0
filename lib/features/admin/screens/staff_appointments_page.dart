import 'package:flutter/material.dart';

import '../../../models/appointment_queue_item.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';
import '../domain/portal_appointment_metrics.dart';
import '../theme/admin_theme.dart';
import '../widgets/staff_queue_refresh_button.dart';

/// Staff-only operational projection. No direct clinical appointment reads.
class StaffAppointmentsPage extends StatefulWidget {
  const StaffAppointmentsPage({super.key, required this.repository});

  final AdminPortalRepository repository;

  @override
  State<StaffAppointmentsPage> createState() => _StaffAppointmentsPageState();
}

class _StaffAppointmentsPageState extends State<StaffAppointmentsPage> {
  String _filter = 'All';
  String _college = 'all';
  final _search = TextEditingController();
  late Stream<List<AppointmentQueueItem>> _queue;
  late Stream<List<College>> _colleges;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    // Do not re-run the refreshPortalAppointmentQueue callable on every
    // keystroke or filter change.
    _queue = widget.repository.watchPortalAppointmentQueue();
    _colleges = widget.repository.watchColleges();
  }

  @override
  void didUpdateWidget(covariant StaffAppointmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.repository, oldWidget.repository)) _bind();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'Appointments',
    subtitle: 'Staff-safe counseling appointment details, filterable by college.',
    child: StreamBuilder<List<AppointmentQueueItem>>(
      stream: _queue,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        // Keep the operational table and filters visible even when the
        // private-safe queue is temporarily unavailable. Never show stale
        // or fabricated appointments as confirmed data.
        final records = snapshot.hasError
            ? const <AppointmentQueueItem>[]
            : snapshot.data ?? const <AppointmentQueueItem>[];
        return StreamBuilder<List<College>>(
          stream: _colleges,
          builder: (context, collegeSnapshot) {
            // College catalog is public, but the queue remains the only
            // source of actual appointment/college associations.
            final catalog = collegeSnapshot.data ?? const <College>[];
            final known = {
              for (final college in catalog) college.id: college.name,
            };
            // Offer every active college, including those with zero bookings,
            // and preserve historical appointment IDs missing from the catalog.
            final ids = <String>{
              for (final college in catalog)
                if (college.active) college.id,
              for (final item in records)
                if (item.collegeId.trim().isNotEmpty)
                  item.collegeId.trim(),
            }.toList()..sort((a, b) => (known[a] ?? a).compareTo(known[b] ?? b));
            final knownSelection = _college == 'all' ||
                _college == 'unassigned' || ids.contains(_college);
            final selectedCollege = knownSelection ? _college : 'all';
            final query = _search.text.trim().toLowerCase();
            final now = DateTime.now();
            final visible = records.where((item) {
              if (!_matches(item, now, _filter)) {
                return false;
              }
              if (selectedCollege == 'unassigned' &&
                  item.collegeId.trim().isNotEmpty) {
                return false;
              }
              if (selectedCollege != 'all' &&
                  selectedCollege != 'unassigned' &&
                  item.collegeId != selectedCollege) {
                return false;
              }
              return query.isEmpty ||
                  item.studentDisplayName.toLowerCase().contains(query) ||
                  (item.assignedCounselor ?? '').toLowerCase().contains(query);
            }).toList()..sort(
              (a, b) => a.scheduledAt.compareTo(b.scheduledAt),
            );
            final metrics = PortalAppointmentMetrics.fromQueue(records, now);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: StaffQueueRefreshButton(repository: widget.repository),
                ),
                const SizedBox(height: 12),
                if (snapshot.hasError) ...[
                  const _Message(
                    'Live appointments could not be loaded. '
                    'Check Staff access, Firestore rules, or network connectivity.',
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in [
                      ('All', records.where((r) => !r.isArchived).length),
                      ('Needs action', metrics.needsAction),
                      ('Today', metrics.today),
                      ('Upcoming', metrics.upcoming),
                      ('Completed', metrics.completed),
                    ])
                      ChoiceChip(
                        label: Text('${option.$1} ${option.$2}'),
                        selected: _filter == option.$1,
                        onSelected: (_) => setState(() => _filter = option.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) => Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: constraints.maxWidth < 320 ? constraints.maxWidth : 320,
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search student or counselor',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth < 320 ? constraints.maxWidth : 320,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('college-$selectedCollege'),
                        initialValue: selectedCollege,
                        decoration: const InputDecoration(
                          labelText: 'Filter by college',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All colleges'),
                          ),
                          for (final id in ids)
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                known[id] ?? id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const DropdownMenuItem(
                            value: 'unassigned',
                            child: Text('Unassigned college'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _college = value ?? 'all',
                        ),
                      ),
                    ),
                  ],
                )),
                const SizedBox(height: 12),
                Text(
                  '${visible.length} ${visible.length == 1 ? 'appointment' : 'appointments'} shown',
                  style: const TextStyle(color: AdminColors.muted),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  _Message(snapshot.hasError
                      ? 'Appointment data is unavailable, not an empty schedule.'
                      : 'No appointments match these filters.'),
                StaffAppointmentTable(items: visible, collegeNames: known),
              ],
            );
          },
        );
      },
    ),
  );
}

bool _matches(AppointmentQueueItem item, DateTime now, String filter) {
  final status = item.status.trim().toLowerCase();
  final day = DateTime(
    item.scheduledAt.year, item.scheduledAt.month, item.scheduledAt.day,
  );
  final today = DateTime(now.year, now.month, now.day);
  return switch (filter) {
    'All' => !item.isArchived,
    'Completed' => status == 'completed' || status == 'complete',
    'Today' => !item.isArchived && status == 'confirmed' && day == today,
    'Upcoming' => !item.isArchived &&
        status == 'confirmed' && day.isAfter(today),
    _ => !item.isArchived && status != 'completed' &&
        !(status == 'confirmed' && (day == today || day.isAfter(today))),
  };
}

class StaffAppointmentTable extends StatelessWidget {
  const StaffAppointmentTable({
    super.key,
    required this.items,
    required this.collegeNames,
  });

  final List<AppointmentQueueItem> items;
  final Map<String, String> collegeNames;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 52,
        dataRowMinHeight: 50,
        dataRowMaxHeight: 64,
        columns: const [
          DataColumn(label: Text('Student')),
          DataColumn(label: Text('College')),
          DataColumn(label: Text('Service')),
          DataColumn(label: Text('Date & time')),
          DataColumn(label: Text('Assigned counselor')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final item in items)
            DataRow(cells: [
              DataCell(Text(item.studentDisplayName.isEmpty
                  ? 'Student' : item.studentDisplayName)),
              DataCell(Text(item.collegeId.isEmpty
                  ? 'Unassigned' : (collegeNames[item.collegeId] ?? item.collegeId))),
              const DataCell(Text('Counseling')),
              DataCell(Text(_dateAndTime(context, item))),
              DataCell(Text(item.assignedCounselor ?? 'Unassigned')),
              DataCell(Text(item.status.isEmpty
                  ? 'Requested' : item.status)),
            ]),
        ],
      ),
    ),
  );

  String _dateAndTime(BuildContext context, AppointmentQueueItem item) {
    final day = item.scheduledAt;
    final date = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final time = item.scheduledTime.trim().isNotEmpty
        ? item.scheduledTime.trim()
        : TimeOfDay.fromDateTime(day).format(context);
    return '$date $time';
  }
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
            Text(title, style: const TextStyle(
              fontSize: 30, fontWeight: FontWeight.w900,
            )),
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
