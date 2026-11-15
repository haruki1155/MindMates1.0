import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/case_remarks_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/student_case_history_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';
import '../widgets/case_remarks_editor.dart';

/// Loads one page of a student's case history; `cursor` is null for the first.
typedef StudentCaseHistoryLoader =
    Future<StudentCaseHistoryResult> Function({String? cursor});

/// Counselors and the configured super-administrator may open a history; the
/// server still decides per student (college assignment or assigned case).
bool canOpenStudentCaseHistory(AdminPortalRepository repository) =>
    repository.currentAccessRole == AccessRole.counselor ||
    (repository.currentAccessRole == AccessRole.admin &&
        repository.isSuperAdmin);

/// Opens [StudentCaseHistoryPage] for the student with account [studentId].
class StudentCaseHistoryButton extends StatelessWidget {
  const StudentCaseHistoryButton({
    super.key,
    required this.repository,
    required this.studentId,
    required this.studentName,
  });

  final AdminPortalRepository repository;
  final String studentId;
  final String studentName;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudentCaseHistoryPage(
          studentId: studentId,
          studentName: studentName,
          loader: ({cursor}) => repository.fetchStudentCaseHistory(
            studentId: studentId,
            cursor: cursor,
          ),
          canEditRemarks: repository.currentAccessRole == AccessRole.counselor,
          remarksLoader: repository.fetchCaseRemarks,
          remarksSaver: (appointmentId, text, expectedRevision) =>
              repository.saveCaseRemarks(
                appointmentId: appointmentId,
                text: text,
                expectedRevision: expectedRevision,
              ),
        ),
      ),
    ),
    icon: const Icon(Icons.history, size: 18),
    label: const Text('Case history'),
  );
}

/// A student's appointments (current and archived), newest first, grouped by
/// year. Records are matched on the server by verified account ID only.
class StudentCaseHistoryPage extends StatefulWidget {
  const StudentCaseHistoryPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.loader,
    this.canEditRemarks = false,
    this.remarksLoader,
    this.remarksSaver,
  });

  final String studentId;
  final String studentName;
  final StudentCaseHistoryLoader loader;
  final bool canEditRemarks;
  final Future<CaseRemarks> Function(String appointmentId)? remarksLoader;
  final Future<CaseRemarks> Function(
    String appointmentId,
    String text,
    int expectedRevision,
  )?
  remarksSaver;

  @override
  State<StudentCaseHistoryPage> createState() => _StudentCaseHistoryPageState();
}

enum _LoadState { loading, ready, failed, denied }

class _StudentCaseHistoryPageState extends State<StudentCaseHistoryPage> {
  final _items = <StudentCaseHistoryEntry>[];
  var _state = _LoadState.loading;
  String? _nextCursor;
  String _displayName = '';
  bool _truncated = false;
  bool _loadingMore = false;
  String? _moreError;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  static const _notAuthorized =
      "You are not authorized to view this student's case history.";

  /// A message for errors that retrying cannot fix, or null.
  String? _finalMessage(Object error) {
    if (error is! FirebaseFunctionsException) return null;
    return switch (error.code) {
      'permission-denied' => _notAuthorized,
      'not-found' => 'This student account was not found.',
      'failed-precondition' => 'This account is not a student account.',
      'invalid-argument' => 'This case history link is not valid.',
      _ => null,
    };
  }

  String _deniedMessage = _notAuthorized;

  Future<void> _loadFirst() async {
    if (_state != _LoadState.loading) {
      setState(() => _state = _LoadState.loading);
    }
    try {
      final page = await widget.loader();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _displayName = page.displayName;
        _truncated = page.truncated;
        _state = _LoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      final message = _finalMessage(error);
      setState(() {
        _deniedMessage = message ?? _notAuthorized;
        _state = message != null ? _LoadState.denied : _LoadState.failed;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.loader(cursor: cursor);
      if (!mounted) return;
      setState(() {
        final known = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => known.add(item.id)));
        _nextCursor = page.nextCursor;
        _truncated = _truncated || page.truncated;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreError = _finalMessage(error) ?? 'We could not load more cases.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName.isNotEmpty
        ? _displayName
        : widget.studentName.trim().isNotEmpty
        ? widget.studentName.trim()
        : 'Student';
    return Scaffold(
      backgroundColor: AdminColors.canvas,
      appBar: AppBar(title: const Text('Case history')),
      body: SafeArea(
        child: switch (_state) {
          _LoadState.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          _LoadState.denied => _Message(
            title: 'Case history unavailable',
            body: _deniedMessage,
          ),
          _LoadState.failed => _Message(
            title: 'Case history unavailable',
            body: 'We could not load this case history.',
            action: FilledButton(
              onPressed: _loadFirst,
              child: const Text('Retry'),
            ),
          ),
          _LoadState.ready => _history(name),
        },
      ),
    );
  }

  Widget _history(String name) {
    final children = <Widget>[
      Text(
        name,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 6),
      const Text(
        'All recorded appointments for this student account, newest first, '
        'including archived cases.',
        style: TextStyle(color: AdminColors.muted),
      ),
      const SizedBox(height: 20),
    ];
    if (_items.isEmpty) {
      children.add(
        const _Message(
          title: 'No cases recorded',
          body: 'This student has no appointments on record.',
          inline: true,
        ),
      );
    } else {
      String? group;
      for (final item in _items) {
        final label = _groupLabel(item);
        if (label != group) {
          group = label;
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AdminColors.muted,
                ),
              ),
            ),
          );
        }
        children.add(
          _CaseCard(
            entry: item,
            canEditRemarks:
                widget.canEditRemarks &&
                widget.remarksLoader != null &&
                widget.remarksSaver != null,
            remarksLoader: widget.remarksLoader,
            remarksSaver: widget.remarksSaver,
          ),
        );
      }
    }
    if (_truncated) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Some records may not be shown because this history is very '
            'long. Contact the PACC administrator for the complete record.',
            style: TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
        ),
      );
    }
    if (_moreError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_moreError!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_nextCursor != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: _loadingMore
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    onPressed: _loadMore,
                    child: const Text('Load more'),
                  ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

String _groupLabel(StudentCaseHistoryEntry entry) {
  final date = entry.sortDate?.toLocal();
  return date == null ? 'Date not recorded' : '${date.year}';
}

String _statusLabel(String status) => switch (status) {
  'requested' => 'Requested',
  'confirmed' => 'Confirmed',
  'reschedule_proposed' => 'Reschedule proposed',
  'completed' => 'Completed',
  'no_show' || 'noshow' => 'No-show',
  'cancelled' || 'canceled' => 'Cancelled',
  'declined' => 'Declined',
  'expired' => 'Expired',
  '' => 'Unknown',
  _ => status[0].toUpperCase() + status.substring(1).replaceAll('_', ' '),
};

String _dateText(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class _CaseCard extends StatefulWidget {
  const _CaseCard({
    required this.entry,
    required this.canEditRemarks,
    this.remarksLoader,
    this.remarksSaver,
  });
  final StudentCaseHistoryEntry entry;
  final bool canEditRemarks;
  final Future<CaseRemarks> Function(String appointmentId)? remarksLoader;
  final Future<CaseRemarks> Function(
    String appointmentId,
    String text,
    int expectedRevision,
  )?
  remarksSaver;

  @override
  State<_CaseCard> createState() => _CaseCardState();
}

class _CaseCardState extends State<_CaseCard> {
  bool _showRemarks = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final scheduled = entry.scheduledAt;
    final when = scheduled != null
        ? '${_dateText(scheduled)}'
              '${entry.scheduledTime.isEmpty ? '' : ' · ${entry.scheduledTime}'}'
        : entry.createdAt != null
        ? 'Requested ${_dateText(entry.createdAt!)} · no schedule recorded'
        : 'No date recorded';
    final details = <String>[
      if (entry.counselorName.isNotEmpty) 'Counselor: ${entry.counselorName}',
      if (entry.location.isNotEmpty) 'Location: ${entry.location}',
      if (entry.completedAt != null)
        'Completed ${_dateText(entry.completedAt!)}',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(label: _statusLabel(entry.status)),
              if (entry.archived) const _Chip(label: 'Archived', muted: true),
              Text(when, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              details.join(' · '),
              style: const TextStyle(color: AdminColors.muted),
            ),
          ],
          if (entry.concern.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Concern: ${entry.concern}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (widget.canEditRemarks) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _showRemarks = !_showRemarks),
              icon: Icon(
                _showRemarks ? Icons.expand_less : Icons.notes_outlined,
                size: 18,
              ),
              label: Text(
                _showRemarks
                    ? 'Hide Transcript / Remarks'
                    : 'Transcript / Remarks',
              ),
            ),
            if (_showRemarks) ...[
              const SizedBox(height: 8),
              CaseRemarksEditor(
                key: ValueKey('remarks-${entry.id}'),
                load: () => widget.remarksLoader!(entry.id),
                save: (text, expectedRevision) =>
                    widget.remarksSaver!(entry.id, text, expectedRevision),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.muted = false});
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: muted ? AdminColors.border : AdminColors.accentSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    this.action,
    this.inline = false,
  });
  final String title;
  final String body;
  final Widget? action;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 600),
      margin: inline ? EdgeInsets.zero : const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: AdminColors.muted)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
    return inline ? content : Center(child: content);
  }
}
