import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_activity_log_presentation.dart';
import '../domain/admin_dashboard_analytics.dart';
import '../domain/admin_management_models.dart';
import '../domain/admin_status_presentation.dart';
import '../theme/admin_theme.dart';

/// Read-only Admin Activity Logs page monitoring Administrator, Counselor, and
/// PAACC Staff actions recorded in `admin_audit_logs`.
class ActivityLogsPage extends StatefulWidget {
  const ActivityLogsPage({
    super.key,
    required this.repository,
    this.clock,
    this.pageSize = 25,
  });

  final AdminPortalRepository repository;
  final DateTime Function()? clock;
  final int pageSize;

  @override
  State<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends State<ActivityLogsPage> {
  ActivityActorRoleFilter _roleFilter = ActivityActorRoleFilter.all;
  String _categoryFilter = '';
  ActivityDateRangePreset _datePreset = ActivityDateRangePreset.last30Days;
  DateTime? _customStartManilaDay;
  DateTime? _customEndManilaDay;
  final TextEditingController _searchController = TextEditingController();
  String _appliedSearch = '';

  List<AdminAuditEvent> _events = const [];
  DateTime? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _permissionDenied = false;
  String? _errorMessage;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _roleFilter != ActivityActorRoleFilter.all ||
      _categoryFilter.isNotEmpty ||
      _datePreset != ActivityDateRangePreset.last30Days ||
      _appliedSearch.isNotEmpty;

  Future<void> _resetFilters() async {
    _searchController.clear();
    setState(() {
      _roleFilter = ActivityActorRoleFilter.all;
      _categoryFilter = '';
      _datePreset = ActivityDateRangePreset.last30Days;
      _customStartManilaDay = null;
      _customEndManilaDay = null;
      _appliedSearch = '';
    });
    await _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!widget.repository.isSuperAdmin) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _permissionDenied = true;
        _errorMessage = null;
        _events = const [];
      });
      return;
    }

    if (more) {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _permissionDenied = false;
        _errorMessage = null;
        _events = const [];
        _cursor = null;
      });
    }

    final bounds = resolveActivityDateBounds(
      preset: _datePreset,
      now: _now,
      customStartManilaDay: _customStartManilaDay,
      customEndManilaDay: _customEndManilaDay,
    );

    try {
      final result = await widget.repository.fetchActivityLogPage(
        roleFilter: _roleFilter,
        category: _categoryFilter,
        search: _appliedSearch,
        after: bounds.after,
        before: bounds.before,
        cursor: more ? _cursor : null,
        pageSize: widget.pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          final existingIds = _events.map((e) => e.id).toSet();
          final appended = result.events
              .where((e) => e.id.isEmpty || !existingIds.contains(e.id))
              .toList();
          _events = [..._events, ...appended];
        } else {
          _events = result.events;
        }
        _hasMore = result.hasMore;
        if (result.events.isNotEmpty) {
          _cursor = result.events.last.createdAt;
        }
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      final text = '$error'.toLowerCase();
      final isDenied =
          text.contains('permission-denied') ||
          text.contains('permission_denied') ||
          text.contains('unauthenticated') ||
          text.contains('unauthorized');
      setState(() {
        _loading = false;
        _loadingMore = false;
        _permissionDenied = isDenied;
        _errorMessage = isDenied
            ? null
            : 'Unable to load activity logs right now. Check your connection and try again.';
      });
    }
  }

  Future<void> _pickCustomDateRange() async {
    final manilaToday = toManilaDateTime(_now);
    final initialEnd = DateTime(
      manilaToday.year,
      manilaToday.month,
      manilaToday.day,
    );
    final initialStart =
        _customStartManilaDay ?? initialEnd.subtract(const Duration(days: 7));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: initialEnd.add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: _customEndManilaDay ?? initialEnd,
      ),
      helpText: 'Select Manila date range (UTC+8)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _datePreset = ActivityDateRangePreset.custom;
      _customStartManilaDay = picked.start;
      _customEndManilaDay = picked.end;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 28,
        narrow ? 16 : 28,
        narrow ? 16 : 28,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity Logs',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Read-only audit trail of Administrator, Counselor, and PAACC Staff actions.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const _SemanticPill(
                        label: 'Timezone: Asia/Manila (UTC+8)',
                        tone: AdminSemanticTone.blue,
                        icon: Icons.schedule_outlined,
                      ),
                      IconButton(
                        tooltip: 'Refresh activity logs',
                        onPressed: _loading ? null : () => _load(),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AdminSpacing.md),
              if (_permissionDenied)
                const _PermissionDeniedPanel()
              else ...[
                _ScopeNoticeBanner(),
                const SizedBox(height: AdminSpacing.md),
                _buildFilterPanel(),
                const SizedBox(height: AdminSpacing.md),
                _buildBody(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      padding: const EdgeInsets.all(AdminSpacing.md),
      decoration: _panelBox,
      child: LayoutBuilder(
        builder: (context, box) {
          final isWide = box.maxWidth >= 960;
          final isMedium = box.maxWidth >= 560;
          final fieldWidth = isWide
              ? (box.maxWidth - 3 * AdminSpacing.sm) / 4
              : isMedium
              ? (box.maxWidth - AdminSpacing.sm) / 2
              : box.maxWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AdminSpacing.sm,
                runSpacing: AdminSpacing.sm,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<ActivityActorRoleFilter>(
                      key: const ValueKey('activity-role-filter'),
                      initialValue: _roleFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Actor role',
                      ),
                      items: ActivityActorRoleFilter.values
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(
                                r.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _roleFilter = value);
                        _load();
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('activity-category-filter'),
                      initialValue: _categoryFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Action category',
                      ),
                      items: kActivityCategoryOptions
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.code,
                              child: Text(
                                c.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _categoryFilter = value);
                        _load();
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<ActivityDateRangePreset>(
                      key: const ValueKey('activity-date-filter'),
                      initialValue: _datePreset,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Date range (Manila)',
                      ),
                      items: ActivityDateRangePreset.values
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(
                                d.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        if (value == ActivityDateRangePreset.custom) {
                          await _pickCustomDateRange();
                          return;
                        }
                        setState(() => _datePreset = value);
                        await _load();
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      key: const ValueKey('activity-search-input'),
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search actor or action',
                        hintText: 'Actor name, action, or ID…',
                        suffixIcon: IconButton(
                          tooltip: 'Apply search',
                          icon: const Icon(Icons.search_rounded, size: 20),
                          onPressed: () {
                            setState(
                              () => _appliedSearch = _searchController.text
                                  .trim(),
                            );
                            _load();
                          },
                        ),
                      ),
                      onSubmitted: (value) {
                        setState(() => _appliedSearch = value.trim());
                        _load();
                      },
                    ),
                  ),
                ],
              ),
              if (_datePreset == ActivityDateRangePreset.custom ||
                  _hasActiveFilters) ...[
                const SizedBox(height: AdminSpacing.sm),
                Wrap(
                  spacing: AdminSpacing.sm,
                  runSpacing: AdminSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_datePreset == ActivityDateRangePreset.custom)
                      OutlinedButton.icon(
                        onPressed: _pickCustomDateRange,
                        icon: const Icon(Icons.date_range_outlined, size: 18),
                        label: Text(
                          _customStartManilaDay != null &&
                                  _customEndManilaDay != null
                              ? '${_formatDateOnly(_customStartManilaDay!)} – ${_formatDateOnly(_customEndManilaDay!)} (Manila)'
                              : 'Choose custom dates',
                        ),
                      ),
                    if (_hasActiveFilters)
                      TextButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 18,
                        ),
                        label: const Text('Reset filters'),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(36),
        decoration: _panelBox,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AdminSpacing.sm),
            Text(
              'Loading activity logs…',
              textAlign: TextAlign.center,
              style: TextStyle(color: AdminColors.muted),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: _panelBox,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AdminColors.redFg,
              size: 32,
            ),
            const SizedBox(height: AdminSpacing.xs),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AdminSpacing.sm),
            FilledButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_events.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(36),
        decoration: _panelBox,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.history_toggle_off_rounded,
              color: AdminColors.muted,
              size: 36,
            ),
            const SizedBox(height: AdminSpacing.xs),
            const Text(
              'No activity logs match the current filters.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try broadening the date range, role filter, or action category.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AdminColors.muted),
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(height: AdminSpacing.sm),
              OutlinedButton(
                onPressed: _resetFilters,
                child: const Text('Reset filters'),
              ),
            ],
          ],
        ),
      );
    }

    var adminCount = 0;
    var counselorCount = 0;
    var staffCount = 0;
    for (final e in _events) {
      switch (normalizeAuditActorRole(e.actorRoleSnapshot)) {
        case 'admin':
          adminCount++;
        case 'counselor':
          counselorCount++;
        case 'portalStaff':
          staffCount++;
      }
    }

    return Container(
      padding: const EdgeInsets.all(AdminSpacing.md),
      decoration: _panelBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Showing ${_events.length} recorded event${_events.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              _SemanticPill(
                label: 'Administrator: $adminCount',
                tone: AdminSemanticTone.violet,
                icon: Icons.admin_panel_settings_outlined,
              ),
              _SemanticPill(
                label: 'Counselor: $counselorCount',
                tone: AdminSemanticTone.blue,
                icon: Icons.psychology_outlined,
              ),
              _SemanticPill(
                label: 'PAACC Staff: $staffCount',
                tone: AdminSemanticTone.green,
                icon: Icons.badge_outlined,
              ),
            ],
          ),
          const SizedBox(height: AdminSpacing.md),
          const Divider(height: 1),
          for (var i = 0; i < _events.length; i++) ...[
            _ActivityEventRow(
              event: _events[i],
              onTap: () => _showEventDetails(_events[i]),
            ),
            if (i < _events.length - 1) const Divider(height: 1),
          ],
          if (_hasMore) ...[
            const SizedBox(height: AdminSpacing.md),
            Center(
              child: OutlinedButton.icon(
                onPressed: _loadingMore ? null : () => _load(more: true),
                icon: _loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  _loadingMore ? 'Loading more…' : 'Load more activity',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showEventDetails(AdminAuditEvent rawEvent) {
    final event = sanitizeAuditEventForDisplay(rawEvent);
    final roleLabel = auditActorRoleLabel(event.actorRoleSnapshot);
    final categoryText = auditCategoryLabel(event.category);
    final actionText = auditActionLabel(event.action);
    final manilaTime = formatActivityManilaTimestamp(event.createdAt);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(actionText),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SemanticPill(
                      label: roleLabel,
                      tone: auditActorRoleTone(event.actorRoleSnapshot),
                      icon: Icons.person_outline,
                    ),
                    _SemanticPill(
                      label: categoryText,
                      tone: resolveActivityEventTone(event),
                      icon: resolveActivityEventIcon(event),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DetailLine(
                  label: 'Performed by',
                  value: event.actorNameSnapshot,
                ),
                _DetailLine(label: 'Actor role', value: roleLabel),
                _DetailLine(label: 'Category', value: categoryText),
                _DetailLine(label: 'Action code', value: event.action),
                _DetailLine(label: 'Timestamp', value: manilaTime),
                if ((event.targetType ?? '').isNotEmpty ||
                    (event.targetId ?? '').isNotEmpty)
                  _DetailLine(
                    label: 'Target record',
                    value: [
                      if ((event.targetType ?? '').isNotEmpty)
                        event.targetType!,
                      if ((event.targetId ?? '').isNotEmpty) event.targetId!,
                    ].join(' • '),
                  ),
                if (event.reason.trim().isNotEmpty)
                  _DetailLine(label: 'Reason', value: event.reason.trim()),
                if (event.metadata.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Recorded operational metadata',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AdminColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminColors.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: event.metadata.entries
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${e.key}: ${e.value}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ScopeNoticeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(AdminSemanticTone.neutral);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Showing server-recorded Administrator, Counselor, and PAACC Staff '
              'audit events stored in admin_audit_logs. Confidential message/session '
              'contents and student personal identifiers are never logged here, and '
              'actions prior to audit coverage are not backfilled.',
              style: TextStyle(color: fg, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionDeniedPanel extends StatelessWidget {
  const _PermissionDeniedPanel();

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(AdminSemanticTone.red);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.lock_outline_rounded, color: fg, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Administrator access required',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Only system administrators can view the organization-wide activity '
            'logs for Administrator, Counselor, and PAACC Staff actions. '
            'Counselor and PAACC Staff accounts are denied access to this feed.',
            style: TextStyle(color: AdminColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ActivityEventRow extends StatelessWidget {
  const _ActivityEventRow({required this.event, required this.onTap});

  final AdminAuditEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final safe = sanitizeAuditEventForDisplay(event);
    final eventTone = resolveActivityEventTone(safe);
    final eventIcon = resolveActivityEventIcon(safe);
    final (bg, fg, _) = _toneColors(eventTone);
    final roleLabel = auditActorRoleLabel(safe.actorRoleSnapshot);
    final roleTone = auditActorRoleTone(safe.actorRoleSnapshot);
    final categoryLabel = auditCategoryLabel(safe.category);
    final actionTitle = auditActionLabel(safe.action);
    final manilaTimestamp = formatActivityManilaTimestamp(safe.createdAt);

    final targetSummary = [
      if ((safe.targetType ?? '').isNotEmpty) safe.targetType!,
      if ((safe.targetId ?? '').isNotEmpty) safe.targetId!,
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(eventIcon, color: fg, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        actionTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      _SemanticPill(
                        label: categoryLabel,
                        tone: eventTone,
                        compact: true,
                      ),
                      _SemanticPill(
                        label: roleLabel,
                        tone: roleTone,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Actor: ${safe.actorNameSnapshot}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.ink,
                        ),
                      ),
                      if (targetSummary.isNotEmpty)
                        Text(
                          'Target: $targetSummary',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AdminColors.muted,
                          ),
                        ),
                      if (safe.reason.trim().isNotEmpty)
                        Text(
                          'Reason: ${safe.reason.trim()}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AdminColors.muted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    manilaTimestamp,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AdminColors.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SemanticPill extends StatelessWidget {
  const _SemanticPill({
    required this.label,
    required this.tone,
    this.icon,
    this.compact = false,
  });

  final String label;
  final AdminSemanticTone tone;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _toneColors(tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 115,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AdminColors.muted,
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

(Color bg, Color fg, Color border) _toneColors(AdminSemanticTone tone) =>
    switch (tone) {
      AdminSemanticTone.amber => (
        AdminColors.amberBg,
        AdminColors.amberFg,
        AdminColors.amberBorder,
      ),
      AdminSemanticTone.blue => (
        AdminColors.blueBg,
        AdminColors.blueFg,
        AdminColors.blueBorder,
      ),
      AdminSemanticTone.green => (
        AdminColors.greenBg,
        AdminColors.greenFg,
        AdminColors.greenBorder,
      ),
      AdminSemanticTone.violet => (
        AdminColors.violetBg,
        AdminColors.violetFg,
        AdminColors.violetBorder,
      ),
      AdminSemanticTone.red => (
        AdminColors.redBg,
        AdminColors.redFg,
        AdminColors.redBorder,
      ),
      AdminSemanticTone.neutral => (
        AdminColors.neutralBg,
        AdminColors.neutralFg,
        AdminColors.neutralBorder,
      ),
    };

String _formatDateOnly(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _panelBox = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: AdminColors.border),
);
