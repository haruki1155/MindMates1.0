import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../../../repositories/admin_status_repository.dart';
import '../domain/admin_assessment_presentation.dart';
import '../theme/admin_theme.dart';
import 'admin_assessment_detail_screen.dart';

/// Assessment review for authorized clinical portal roles. No direct profile
/// reads, no assessment writes, and no destructive actions occur here.
class AdminAssessmentResultsPage extends StatefulWidget {
  const AdminAssessmentResultsPage({
    super.key,
    required this.repository,
    this.loadParticipants,
    this.onAssessmentOpen,
  });
  final AdminPortalRepository repository;
  final Future<Map<String, AssessmentParticipantInfo>> Function(
    List<String> ids,
  )?
  loadParticipants;
  final void Function(AdminAssessmentRecord record, String name)?
  onAssessmentOpen;

  @override
  State<AdminAssessmentResultsPage> createState() =>
      _AdminAssessmentResultsPageState();
}

class _AdminAssessmentResultsPageState
    extends State<AdminAssessmentResultsPage> {
  AssessmentView _view = AssessmentView.quick;
  String _year = 'All Years';
  String _status = 'All Statuses';
  String _role = 'All Roles';
  bool _showArchived = false;

  String _directoryKey = '';
  Future<Map<String, AssessmentParticipantInfo>>? _directoryFuture;

  Future<Map<String, AssessmentParticipantInfo>> _directoryFor(
    List<AdminAssessmentRecord> records,
  ) {
    final ids =
        records
            .map((record) => record.userId.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final signature = ids.join('|');
    if (_directoryKey == signature && _directoryFuture != null) {
      return _directoryFuture!;
    }
    _directoryKey = signature;
    _directoryFuture =
        widget.loadParticipants?.call(ids) ?? _loadDirectory(ids);
    return _directoryFuture!;
  }

  Future<Map<String, AssessmentParticipantInfo>> _loadDirectory(
    List<String> ids,
  ) async {
    final people = <String, AssessmentParticipantInfo>{};
    for (var offset = 0; offset < ids.length; offset += 80) {
      final end = offset + 80 < ids.length ? offset + 80 : ids.length;
      final response = await FirebaseFunctions.instance
          .httpsCallable('getAssessmentParticipantDirectory')
          .call<Map<String, dynamic>>({'userIds': ids.sublist(offset, end)});
      final entries = response.data['participants'];
      if (entries is! List) throw StateError('Invalid participant response.');
      for (final item in entries) {
        if (item is! Map) continue;
        final participant = AssessmentParticipantInfo.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (ids.contains(participant.userId)) {
          people[participant.userId] = participant;
        }
      }
    }
    return people;
  }

  void _openAssessment(AdminAssessmentRecord record, String displayName) {
    if (widget.onAssessmentOpen != null) {
      widget.onAssessmentOpen!(record, displayName);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminAssessmentDetailScreen(
          userId: record.userId,
          userLabel: displayName,
          assessmentId: record.id,
          repository: AdminStatusRepository(),
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<AdminAssessmentRecord>>(
    stream: widget.repository.watchAssessments(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const _Message(
          'Unable to load assessment records. Check clinical access.',
        );
      }
      if (!snapshot.hasData) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      }
      final all = snapshot.data!;
      final scoped = all
          .where((record) => matchesAssessmentView(record, _view))
          .toList();
      final years = scoped.map((r) => '${r.createdAt.year}').toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      final statuses = scoped.map((r) => r.displayStatus).toSet().toList()
        ..sort();
      final roles = scoped.map((r) => r.role ?? 'Unknown').toSet().toList()
        ..sort();
      final filtered = scoped
          .where(
            (record) =>
                record.isArchived == _showArchived &&
                (_year == 'All Years' || '${record.createdAt.year}' == _year) &&
                (_status == 'All Statuses' ||
                    record.displayStatus == _status) &&
                (_role == 'All Roles' || (record.role ?? 'Unknown') == _role),
          )
          .toList();
      return FutureBuilder<Map<String, AssessmentParticipantInfo>>(
        future: _directoryFor(all),
        builder: (context, peopleSnapshot) {
          final directoryAvailable = peopleSnapshot.hasData;
          final people =
              peopleSnapshot.data ??
              const <String, AssessmentParticipantInfo>{};
          final counts = AssessmentParticipantCounts.fromRecords(
            filtered,
            people,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SectionTab(
                    label: 'Quick Assessment',
                    selected: _view == AssessmentView.quick,
                    onPressed: () =>
                        setState(() => _view = AssessmentView.quick),
                  ),
                  _SectionTab(
                    label: 'Full Assessment',
                    selected: _view == AssessmentView.full,
                    onPressed: () =>
                        setState(() => _view = AssessmentView.full),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Surface(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Selector(
                      label: 'Year',
                      value: years.contains(_year) ? _year : 'All Years',
                      choices: ['All Years', ...years],
                      onChanged: (s) => setState(() => _year = s),
                    ),
                    _Selector(
                      label: 'Status',
                      value: statuses.contains(_status)
                          ? _status
                          : 'All Statuses',
                      choices: ['All Statuses', ...statuses],
                      onChanged: (s) => setState(() => _status = s),
                    ),
                    _Selector(
                      label: 'Role',
                      value: roles.contains(_role) ? _role : 'All Roles',
                      choices: ['All Roles', ...roles],
                      onChanged: (s) => setState(() => _role = s),
                    ),
                    _Selector(
                      label: 'Record state',
                      value: _showArchived ? 'Archived' : 'Active',
                      choices: const ['Active', 'Archived'],
                      onChanged: (s) =>
                          setState(() => _showArchived = s == 'Archived'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${filtered.length} assessment records',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              if (peopleSnapshot.hasError)
                const _Message(
                  'Participant names and college breakdown are unavailable. '
                  'The secure directory function may not be deployed to staging yet.',
                ),
              if (peopleSnapshot.connectionState == ConnectionState.waiting)
                const _Message('Loading authorized participant details...'),
              if (directoryAvailable) ...[
                _Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assessed participants',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Unique people in the selected records (not submissions). '
                        'Small groups are suppressed for privacy.',
                        style: TextStyle(
                          color: AdminColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _CategoryBars(
                        title: 'Students by college',
                        values: counts.studentsByCollege,
                      ),
                      const SizedBox(height: 18),
                      _CategoryBars(
                        title: 'Employees by role',
                        values: counts.personnelByRole,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (filtered.isEmpty)
                const _Message('No assessment records match your filters.')
              else
                _AssessmentTable(
                  assessments: filtered,
                  names: people,
                  onOpen: _openAssessment,
                ),
            ],
          );
        },
      );
    },
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class _Message extends StatelessWidget {
  const _Message(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => _Surface(
    child: Text(message, style: const TextStyle(color: AdminColors.muted)),
  );
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      backgroundColor: selected ? AdminColors.accentSoft : AdminColors.surface,
      foregroundColor: AdminColors.ink,
      side: BorderSide(
        color: selected ? AdminColors.accentStrong : AdminColors.border,
      ),
      minimumSize: const Size(165, 48),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected) ...[
          const Icon(Icons.check_circle_outline, size: 17),
          const SizedBox(width: 8),
        ],
        Text(label),
      ],
    ),
  );
}

class _Selector extends StatelessWidget {
  const _Selector({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> choices;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: choices
          .map(
            (s) => DropdownMenuItem<String>(
              value: s,
              child: Text(s, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (s) {
        if (s != null) onChanged(s);
      },
    ),
  );
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.title, required this.values});
  final String title;
  final Map<String, int> values;
  static const minPrivacyGroup = 5;

  @override
  Widget build(BuildContext context) {
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maximum = sorted.isEmpty ? 1 : sorted.first.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (sorted.isEmpty)
          const Text(
            'No participants in this group.',
            style: TextStyle(color: AdminColors.muted),
          )
        else
          for (final group in sorted) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    group.key,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: group.value < minPrivacyGroup
                      ? const Text(
                          'Suppressed (<5)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.muted,
                          ),
                        )
                      : Tooltip(
                          message: '${group.value} assessed participants',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: group.value / maximum,
                              minHeight: 16,
                              backgroundColor: AdminColors.surfaceMuted,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AdminColors.accentStrong,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 42,
                  child: Text(
                    group.value < minPrivacyGroup ? '<5' : '${group.value}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _AssessmentTable extends StatelessWidget {
  const _AssessmentTable({
    required this.assessments,
    required this.names,
    required this.onOpen,
  });
  final List<AdminAssessmentRecord> assessments;
  final Map<String, AssessmentParticipantInfo> names;
  final void Function(AdminAssessmentRecord record, String name) onOpen;

  @override
  Widget build(BuildContext context) => _Surface(
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            showCheckboxColumn: false,
            columnSpacing: 24,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 70,
            headingRowColor: const WidgetStatePropertyAll(
              AdminColors.accentFaint,
            ),
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Assessment Type')),
            ],
            rows: assessments.map((assessment) {
              final name = names[assessment.userId]?.name ?? 'Name unavailable';
              final style = AssessmentStatusStyle.fromStored(
                assessment.displayStatus,
              );
              return DataRow(
                key: ValueKey('assessment-${assessment.id}'),
                onSelectChanged: (_) => onOpen(assessment, name),
                mouseCursor: const WidgetStatePropertyAll(
                  SystemMouseCursors.click,
                ),
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 210),
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  DataCell(Text(_date(assessment.createdAt))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: style.background,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        style.label,
                        style: TextStyle(
                          color: style.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(assessment.role ?? 'Unknown')),
                  DataCell(
                    Text(
                      assessment.isQuickAssessment
                          ? 'Quick Assessment'
                          : 'Full Assessment',
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
