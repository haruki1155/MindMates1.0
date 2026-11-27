import 'package:flutter/material.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/testing_service_schedule.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../domain/inquiry_scope.dart';
import '../theme/admin_theme.dart';
import '../widgets/testing_service_schedule_panel.dart';

enum _TestingClientFilter {
  all,
  studentOjt,
  teaching,
  nonTeaching;

  String get label => switch (this) {
    _TestingClientFilter.all => 'All clients',
    _TestingClientFilter.studentOjt => 'Student (OJT)',
    _TestingClientFilter.teaching => 'Teaching',
    _TestingClientFilter.nonTeaching => 'Non-Teaching',
  };
}

String _formatManilaDate(DateTime wallClock) {
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
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[wallClock.weekday - 1]}, ${months[wallClock.month - 1]} ${wallClock.day}, ${wallClock.year}';
}

String _formatSlotHour(int hour) {
  final display = hour % 12 == 0 ? 12 : hour % 12;
  final period = hour < 12 ? 'AM' : 'PM';
  return '$display:00 $period';
}

/// Dedicated Testing Service dashboard & queue inside Inquiries, powered
/// exclusively by `inquiries` with `formType == 'testing_service'` —
/// completely separate from Counseling `appointments`.
class AdminTestingServicePage extends StatefulWidget {
  const AdminTestingServicePage({
    super.key,
    required this.repository,
    required this.onOpenInquiry,
    this.embedded = false,
  });

  final AdminPortalRepository repository;
  final ValueChanged<AdminInquiryModel> onOpenInquiry;
  final bool embedded;

  @override
  State<AdminTestingServicePage> createState() =>
      _AdminTestingServicePageState();
}

class _AdminTestingServicePageState extends State<AdminTestingServicePage> {
  TestingScheduleStatus? _statusFilter;
  _TestingClientFilter _clientFilter = _TestingClientFilter.all;
  final TextEditingController _search = TextEditingController();
  int _streamEpoch = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Stream<List<AdminInquiryModel>> _watchForRole() {
    if (widget.repository.isSuperAdmin ||
        widget.repository.currentAccessRole == AccessRole.counselor) {
      return widget.repository.watchInquiries();
    }
    if (widget.repository.currentAccessRole == AccessRole.portalStaff) {
      return widget.repository.watchInquiryStatuses();
    }
    return Stream.error(
      StateError('Testing Service access is limited to authorized PACC staff.'),
    );
  }

  bool get _isAdminReadOnly =>
      widget.repository.isSuperAdmin ||
      widget.repository.currentAccessRole == AccessRole.admin;

  bool get _canDecideTesting =>
      !_isAdminReadOnly &&
      widget.repository.currentAccessRole == AccessRole.counselor;

  TestingScheduleStatus _effectiveStatus(AdminInquiryModel item) =>
      item.testingSchedule?.status ?? TestingScheduleStatus.awaitingSchedule;

  int _priorityOrder(AdminInquiryModel item) => switch (_effectiveStatus(
    item,
  )) {
    TestingScheduleStatus.rescheduleRequested => 0,
    TestingScheduleStatus.awaitingSchedule => 1,
    TestingScheduleStatus.proposed => 2,
    TestingScheduleStatus.confirmed => 3,
    TestingScheduleStatus.completed => 4,
    TestingScheduleStatus.cancelled => 5,
  };

  bool _matchesClientFilter(AdminInquiryModel item) {
    final roleText =
        '${item.role ?? ''} ${item.formData['Client type'] ?? ''} ${item.formData['Client Type'] ?? ''} ${item.formData['clientType'] ?? ''}'
            .toLowerCase();
    return switch (_clientFilter) {
      _TestingClientFilter.all => true,
      _TestingClientFilter.studentOjt => roleText.contains('student'),
      _TestingClientFilter.teaching =>
        roleText.contains('teaching') && !roleText.contains('non-teaching'),
      _TestingClientFilter.nonTeaching => roleText.contains('non-teaching'),
    };
  }

  String _clientTypeLabel(AdminInquiryModel item) {
    final fromForm =
        item.formData['Client type']?.toString().trim() ??
        item.formData['Client Type']?.toString().trim() ??
        item.formData['clientType']?.toString().trim() ??
        '';
    if (fromForm.isNotEmpty) return fromForm;
    final rawRole = item.role?.trim() ?? '';
    return rawRole.isNotEmpty ? rawRole : 'Applicant';
  }

  String? _processingCounselorLabel(AdminInquiryModel item) {
    final completed = item.testingSchedule?.completedByName?.trim() ?? '';
    if (completed.isNotEmpty) return completed;
    final proposed = item.testingSchedule?.proposedByName?.trim() ?? '';
    if (proposed.isNotEmpty) return proposed;
    final cancelled = item.testingSchedule?.cancelledByName?.trim() ?? '';
    if (cancelled.isNotEmpty) return cancelled;
    final takeover = item.takeoverByName?.trim() ?? '';
    if (takeover.isNotEmpty) return takeover;
    final ownerKey = item.ownerId?.trim() ?? '';
    if (ownerKey.isNotEmpty) {
      final ownerLabel = item.assigneeLabels[ownerKey]?.trim() ?? '';
      if (ownerLabel.isNotEmpty) return ownerLabel;
    }
    for (final uid in item.assigneeIds) {
      final label = item.assigneeLabels[uid]?.trim() ?? '';
      if (label.isNotEmpty) return label;
    }
    for (final label in item.assigneeLabels.values) {
      final trimmed = label.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return item.lastResponseByName?.trim().isNotEmpty == true
        ? item.lastResponseByName!.trim()
        : null;
  }

  Future<void> _openDecisionDialog(AdminInquiryModel item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: ValueKey('testing-decision-dialog-${item.id}'),
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.ink,
                            ),
                          ),
                          Text(
                            '${_clientTypeLabel(item)} · ${item.studentIdentityLabel}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AdminColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        widget.onOpenInquiry(item);
                      },
                      child: const Text('Full Details'),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: TestingServiceSchedulePanel(
                    inquiry: item,
                    repository: widget.repository,
                    onDecisionSent: () {
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(
      key: ValueKey('testing-service-stream-$_streamEpoch'),
      child: StreamBuilder<List<AdminInquiryModel>>(
        stream: _watchForRole(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AdminColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Testing Service requests could not be loaded',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    FirebaseErrorMessage.describe(
                      snapshot.error!,
                      fallback: 'Unable to load Testing Service inquiries.',
                    ),
                    style: const TextStyle(color: AdminColors.muted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _streamEpoch++),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final rawAll = snapshot.data ?? const <AdminInquiryModel>[];
          final scoped = widget.repository.isSuperAdmin
              ? rawAll.where(isAdminVisibleInquiry)
              : rawAll;
          final allTesting = scoped.where((i) => i.isTestingService).toList();

          final awaitingCount = allTesting
              .where(
                (i) =>
                    _effectiveStatus(i) ==
                    TestingScheduleStatus.awaitingSchedule,
              )
              .length;
          final proposedCount = allTesting
              .where(
                (i) => _effectiveStatus(i) == TestingScheduleStatus.proposed,
              )
              .length;
          final rescheduleCount = allTesting
              .where(
                (i) =>
                    _effectiveStatus(i) ==
                    TestingScheduleStatus.rescheduleRequested,
              )
              .length;
          final confirmedCount = allTesting
              .where(
                (i) => _effectiveStatus(i) == TestingScheduleStatus.confirmed,
              )
              .length;
          final completedCount = allTesting
              .where(
                (i) => _effectiveStatus(i) == TestingScheduleStatus.completed,
              )
              .length;
          final cancelledCount = allTesting
              .where(
                (i) => _effectiveStatus(i) == TestingScheduleStatus.cancelled,
              )
              .length;

          final query = _search.text.trim().toLowerCase();
          final filtered =
              allTesting.where((item) {
                if (_statusFilter != null &&
                    _effectiveStatus(item) != _statusFilter) {
                  return false;
                }
                if (!_matchesClientFilter(item)) return false;
                if (query.isEmpty) return true;
                return item.displayName.toLowerCase().contains(query) ||
                    item.studentIdentityLabel.toLowerCase().contains(query) ||
                    (item.contactNumber ?? '').toLowerCase().contains(query) ||
                    item.subject.toLowerCase().contains(query);
              }).toList()..sort((a, b) {
                final priority = _priorityOrder(
                  a,
                ).compareTo(_priorityOrder(b));
                if (priority != 0) return priority;
                return b.createdAt.compareTo(a.createdAt);
              });

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isAdminReadOnly) ...[
                  Container(
                    key: const ValueKey('testing-admin-readonly-banner'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AdminColors.blueBg.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminColors.blueBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          size: 18,
                          color: AdminColors.blueFg,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Supervising & monitoring view — Admin access is read-only. Only assigned counselors can approve, reschedule, cancel, or complete Testing Service schedules.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.blueFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('testing-filter-all'),
                      label: Text('All (${allTesting.length})'),
                      selected: _statusFilter == null,
                      onSelected: (_) => setState(() => _statusFilter = null),
                    ),
                    ChoiceChip(
                      key: const ValueKey('testing-filter-awaiting'),
                      label: Text('Awaiting Schedule ($awaitingCount)'),
                      selected:
                          _statusFilter ==
                          TestingScheduleStatus.awaitingSchedule,
                      onSelected: (_) => setState(
                        () => _statusFilter =
                            TestingScheduleStatus.awaitingSchedule,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('testing-filter-proposed'),
                      label: Text('Proposed ($proposedCount)'),
                      selected:
                          _statusFilter == TestingScheduleStatus.proposed,
                      onSelected: (_) => setState(
                        () => _statusFilter = TestingScheduleStatus.proposed,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('testing-filter-reschedule'),
                      label: Text('Reschedule Requested ($rescheduleCount)'),
                      selected:
                          _statusFilter ==
                          TestingScheduleStatus.rescheduleRequested,
                      onSelected: (_) => setState(
                        () => _statusFilter =
                            TestingScheduleStatus.rescheduleRequested,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('testing-filter-confirmed'),
                      label: Text('Confirmed ($confirmedCount)'),
                      selected:
                          _statusFilter == TestingScheduleStatus.confirmed,
                      onSelected: (_) => setState(
                        () => _statusFilter = TestingScheduleStatus.confirmed,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('testing-filter-completed'),
                      label: Text('Completed ($completedCount)'),
                      selected:
                          _statusFilter == TestingScheduleStatus.completed,
                      onSelected: (_) => setState(
                        () => _statusFilter = TestingScheduleStatus.completed,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('testing-filter-cancelled'),
                      label: Text('Cancelled ($cancelledCount)'),
                      selected:
                          _statusFilter == TestingScheduleStatus.cancelled,
                      onSelected: (_) => setState(
                        () => _statusFilter = TestingScheduleStatus.cancelled,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: TextField(
                        key: const ValueKey('testing-service-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: AdminColors.canvas,
                          hintText: 'Search name, Student No., mobile…',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ),
                    for (final filter in _TestingClientFilter.values)
                      ChoiceChip(
                        label: Text(filter.label),
                        selected: _clientFilter == filter,
                        onSelected: (_) =>
                            setState(() => _clientFilter = filter),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (filtered.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AdminColors.canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: Text(
                      allTesting.isEmpty
                          ? 'No Testing Service inquiries have been submitted yet.'
                          : 'No Testing Service requests match the selected filters.',
                      style: const TextStyle(color: AdminColors.muted),
                    ),
                  )
                else
                  for (var i = 0; i < filtered.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _buildQueueCard(filtered[i]),
                  ],
              ],
            ),
          );
        },
      ),
    );

    if (widget.embedded) return content;

    final narrow = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 28, 28, narrow ? 16 : 28, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Track Testing Service requests, verify uploaded documents, and manage testing schedules separately from Counseling Appointments.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueCard(AdminInquiryModel item) {
    final status = _effectiveStatus(item);
    final (badgeBg, badgeFg) = switch (status) {
      TestingScheduleStatus.confirmed ||
      TestingScheduleStatus.completed => (
        AdminColors.greenBg,
        AdminColors.greenFg,
      ),
      TestingScheduleStatus.proposed => (
        AdminColors.blueBg,
        AdminColors.blueFg,
      ),
      TestingScheduleStatus.rescheduleRequested => (
        const Color(0xFFFFEDD5),
        const Color(0xFF9A3412),
      ),
      TestingScheduleStatus.cancelled => (
        AdminColors.redBg,
        AdminColors.redFg,
      ),
      TestingScheduleStatus.awaitingSchedule => (
        AdminColors.amberBg,
        AdminColors.amberFg,
      ),
    };
    final preferredWall = item.preferredScheduleAt?.toUtc().add(
      const Duration(hours: 8),
    );
    final scheduledWall = item.testingSchedule?.scheduledAt?.toUtc().add(
      const Duration(hours: 8),
    );
    final docCount = item.testingDocuments?.all.length ?? 0;
    final counselorName = _processingCounselorLabel(item);
    final initials = item.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final requestedText = preferredWall != null
        ? '${_formatManilaDate(preferredWall)} · ${item.preferredScheduleTime ?? _formatSlotHour(preferredWall.hour)} (PHT)'
        : 'Not specified';
    final scheduledText =
        scheduledWall != null && status != TestingScheduleStatus.cancelled
        ? '${status == TestingScheduleStatus.completed
              ? 'Completed'
              : status == TestingScheduleStatus.confirmed
              ? 'Confirmed'
              : 'Proposed'}: ${_formatManilaDate(scheduledWall)} · ${item.testingSchedule?.scheduledTime ?? _formatSlotHour(scheduledWall.hour)} (PHT)'
        : status == TestingScheduleStatus.cancelled
        ? 'Cancelled'
        : 'Awaiting schedule';
    final detailFields = <(String, String)>[
      ('Student ID', item.studentIdentityLabel),
      ('SMS Contact', (item.contactNumber ?? '').isNotEmpty ? item.contactNumber! : 'Not provided'),
      ('Requested Slot', requestedText),
      ('Scheduled Slot', scheduledText),
      ('Documents', '$docCount ${docCount == 1 ? 'file' : 'files'}'),
      ('Counselor', counselorName ?? 'Unassigned'),
    ];

    return Material(
      color: AdminColors.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('testing-queue-item-${item.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onOpenInquiry(item),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AdminColors.accentSoft,
                    foregroundColor: AdminColors.ink,
                    child: Text(
                      initials.isEmpty ? '?' : initials,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.displayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AdminColors.ink,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AdminColors.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AdminColors.border),
                          ),
                          child: Text(
                            _clientTypeLabel(item),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AdminColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: badgeFg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AdminColors.border),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 760
                      ? 3
                      : constraints.maxWidth >= 460
                      ? 2
                      : 1;
                  final cellWidth =
                      (constraints.maxWidth - (cols - 1) * 16) / cols;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    children: [
                      for (final field in detailFields)
                        SizedBox(
                          width: cellWidth,
                          child: _QueueDetailField(
                            label: field.$1,
                            value: field.$2,
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (status == TestingScheduleStatus.cancelled &&
                  (item.testingSchedule?.cancelReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.redBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Cancellation reason: ${item.testingSchedule!.cancelReason}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.redFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (status == TestingScheduleStatus.completed &&
                  (item.testingSchedule?.completionNote ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.greenBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Completion note: ${item.testingSchedule!.completionNote}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.greenFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1, color: AdminColors.border),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: ValueKey('testing-review-btn-${item.id}'),
                        onPressed: () => widget.onOpenInquiry(item),
                        child: const Text('View Details'),
                      ),
                      if (_canDecideTesting)
                        FilledButton.icon(
                          key: ValueKey('testing-decide-btn-${item.id}'),
                          onPressed: () => _openDecisionDialog(item),
                          icon: const Icon(Icons.fact_check_outlined, size: 17),
                          label: const Text('Schedule / Decide'),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueDetailField extends StatelessWidget {
  const _QueueDetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: AdminColors.muted,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AdminColors.ink,
        ),
      ),
    ],
  );
}
