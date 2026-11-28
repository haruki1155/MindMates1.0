import 'package:flutter/material.dart';

import '../data/admin_insight_catalog_repository.dart';
import '../models/insights_models.dart';
import '../theme/insights_admin_theme.dart';
import '../widgets/insight_content_editor.dart';

/// Admin-only curation of mobile Insights content (`insight_content`).
class ManageInsightsPage extends StatefulWidget {
  const ManageInsightsPage({super.key, this.repository});

  final AdminInsightCatalogRepository? repository;

  @override
  State<ManageInsightsPage> createState() => _ManageInsightsPageState();
}

class _ManageInsightsPageState extends State<ManageInsightsPage> {
  late final _repository = widget.repository ?? AdminInsightCatalogRepository();
  final List<InsightCardItem> _items = [];
  String? _status;
  String? _role;
  String _query = '';
  bool _loading = true;
  String? _error;

  static const _statusFilters = {
    null: 'All',
    'approved': 'Approved',
    'pending_review': 'Pending review',
    'draft': 'Draft',
    'archived': 'Archived',
  };

  static const _roleFilters = {
    null: 'All roles',
    'student': 'Student',
    'teaching': 'Teaching',
    'nonTeaching': 'Non-Teaching',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repository.loadAllContent();
      if (!mounted) return;
      setState(
        () => _items
          ..clear()
          ..addAll(items),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load insights.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _statusOf(InsightCardItem item) => item.reviewStatus ?? 'draft';

  List<InsightCardItem> get _visible {
    final query = _query.trim().toLowerCase();
    return _items
        .where((item) => _status == null || _statusOf(item) == _status)
        .where(
          (item) =>
              _role == null ||
              item.targetRoles.contains(_role) ||
              item.targetRoles.contains('all'),
        )
        .where(
          (item) =>
              query.isEmpty ||
              '${item.id} ${item.title} ${item.sourceTitle ?? ''}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _edit([InsightCardItem? item]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            InsightContentEditor(repository: _repository, item: item),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on InsightCatalogValidationException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('Unable to update. Check access and retry.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setStatus(InsightCardItem item, String status) => _run(
    () => _repository.setReviewStatus(
      item: item,
      reviewStatus: status,
      reviewerUid: _repository.currentUid ?? '',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final eligible = _items.where((item) => item.hasApprovedProvenance).length;
    return Theme(
      data: InsightsAdminTheme.data,
      child: ColoredBox(
        key: const Key('insights_page_canvas'),
        color: InsightsAdminColors.canvas,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 20,
                  runSpacing: 16,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Insights Content',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: InsightsAdminColors.navy,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Curate and approve source-verified wellness guides',
                          style: TextStyle(
                            fontSize: 14,
                            color: InsightsAdminColors.bodyMuted,
                          ),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      key: const Key('new_insight_button'),
                      style: InsightsAdminTheme.newInsightButtonStyle,
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New insight'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  key: const Key('insights_summary_banner'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: InsightsAdminColors.surface,
                    borderRadius: InsightsAdminTheme.controlRadius,
                    border: Border.all(color: InsightsAdminColors.cardBorder),
                    boxShadow: InsightsAdminTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_outlined,
                        size: 18,
                        color: InsightsAdminColors.activeFg,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$eligible Featured-eligible • '
                          '${_items.length - eligible} Need provenance/review',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: InsightsAdminColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _InsightsFilterBar(
                  statusFilters: _statusFilters,
                  selectedStatus: _status,
                  onStatusChanged: (value) => setState(() => _status = value),
                  roleFilters: _roleFilters,
                  selectedRole: _role,
                  onRoleChanged: (value) => setState(() => _role = value),
                  onQueryChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: InsightsAdminColors.dangerBg,
                      borderRadius: InsightsAdminTheme.controlRadius,
                      border: Border.all(
                        color: InsightsAdminColors.dangerBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: InsightsAdminColors.dangerFg,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: InsightsAdminColors.dangerFg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (visible.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 32,
                    ),
                    decoration: InsightsAdminTheme.cardDecoration,
                    child: const Center(
                      child: Text(
                        'No insights match these filters.',
                        style: TextStyle(
                          fontSize: 14,
                          color: InsightsAdminColors.bodyMuted,
                        ),
                      ),
                    ),
                  )
                else
                  for (final item in visible) ...[
                    _InsightRow(
                      item: item,
                      onEdit: () => _edit(item),
                      onApprove: item.provenanceGaps.isEmpty
                          ? () => _setStatus(item, 'approved')
                          : null,
                      onToggleActive: () => _run(
                        () => _repository.setActive(
                          id: item.id,
                          isActive: !item.isActive,
                        ),
                      ),
                      onArchive: _statusOf(item) == 'archived'
                          ? () => _setStatus(item, 'pending_review')
                          : () => _setStatus(item, 'archived'),
                    ),
                    const SizedBox(height: 16),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightsFilterBar extends StatelessWidget {
  const _InsightsFilterBar({
    required this.statusFilters,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.roleFilters,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.onQueryChanged,
  });

  final Map<String?, String> statusFilters;
  final String? selectedStatus;
  final ValueChanged<String?> onStatusChanged;
  final Map<String?, String> roleFilters;
  final String? selectedRole;
  final ValueChanged<String?> onRoleChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final segmentedControl = _StatusSegmentedControl(
      filters: statusFilters,
      selected: selectedStatus,
      onSelected: onStatusChanged,
    );

    final roleDropdown = Container(
      key: const Key('insights_role_filter'),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: InsightsAdminTheme.controlDecoration,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selectedRole,
          isDense: true,
          borderRadius: InsightsAdminTheme.controlRadius,
          dropdownColor: InsightsAdminColors.surface,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: InsightsAdminColors.bodyMuted,
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: InsightsAdminColors.navy,
          ),
          items: [
            for (final entry in roleFilters.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: onRoleChanged,
        ),
      ),
    );

    final searchField = SizedBox(
      height: 44,
      child: TextField(
        key: const Key('insights_search_field'),
        style: const TextStyle(
          fontSize: 14,
          color: InsightsAdminColors.navy,
        ),
        decoration: const InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: InsightsAdminColors.subtleMuted,
          ),
          hintText: 'Search insights',
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        onChanged: onQueryChanged,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 920) {
          return Row(
            children: [
              segmentedControl,
              const SizedBox(width: 12),
              roleDropdown,
              const SizedBox(width: 12),
              Expanded(child: searchField),
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            segmentedControl,
            roleDropdown,
            SizedBox(
              width: constraints.maxWidth < 360 ? constraints.maxWidth : 280,
              child: searchField,
            ),
          ],
        );
      },
    );
  }
}

class _StatusSegmentedControl extends StatelessWidget {
  const _StatusSegmentedControl({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  final Map<String?, String> filters;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('insights_status_segmented_control'),
    padding: const EdgeInsets.all(4),
    decoration: InsightsAdminTheme.controlDecoration,
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in filters.entries)
          _SegmentButton(
            key: Key('status_filter_${entry.key ?? 'all'}'),
            label: entry.value,
            selected: selected == entry.key,
            onPressed: () => onSelected(entry.key),
          ),
      ],
    ),
  );
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? InsightsAdminColors.tagBlueBg : Colors.transparent,
    borderRadius: InsightsAdminTheme.actionRadius,
    child: InkWell(
      onTap: onPressed,
      borderRadius: InsightsAdminTheme.actionRadius,
      hoverColor: selected
          ? InsightsAdminColors.tagBlueBg
          : InsightsAdminColors.canvas,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? InsightsAdminColors.navy
                : InsightsAdminColors.bodyMuted,
          ),
        ),
      ),
    ),
  );
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.item,
    required this.onEdit,
    required this.onApprove,
    required this.onToggleActive,
    required this.onArchive,
  });

  final InsightCardItem item;
  final VoidCallback onEdit;
  final VoidCallback? onApprove;
  final VoidCallback onToggleActive;
  final VoidCallback onArchive;

  String get _description {
    final subtitle = item.subtitle.trim();
    if (subtitle.isNotEmpty) return subtitle;
    return item.body?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final eligible = item.hasApprovedProvenance;
    final status = item.reviewStatus ?? 'draft';
    final isArchived = status == 'archived';
    final description = _description;
    final showApprove = status != 'approved' && !isArchived;

    final statusPills = <Widget>[
      InsightsStatusPill.active(item.isActive),
      InsightsStatusPill.reviewStatus(status),
    ];

    final categoryTags = <Widget>[
      for (final role in item.targetRoles)
        InsightsCategoryTag(insightTargetRoleLabels[role] ?? role),
      InsightsCategoryTag(
        eligible ? 'Featured-eligible' : 'Library only',
        icon: eligible ? Icons.verified_outlined : null,
      ),
      if (item.category.trim().isNotEmpty) InsightsCategoryTag(item.category),
      if (item.sectionId.trim().isNotEmpty) InsightsCategoryTag(item.sectionId),
      for (final domain in item.domainIds) InsightsCategoryTag(domain),
    ];

    final actionButtons = <Widget>[
      OutlinedButton.icon(
        key: Key('edit_${item.id}'),
        style: InsightsAdminTheme.secondaryActionStyle(),
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Edit'),
      ),
      if (showApprove)
        Tooltip(
          message: onApprove == null
              ? 'Complete source provenance before approving'
              : 'Approve for Featured recommendations',
          child: FilledButton.icon(
            key: Key('approve_${item.id}'),
            style: InsightsAdminTheme.primaryActionStyle,
            onPressed: onApprove,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Approve'),
          ),
        ),
      OutlinedButton.icon(
        key: Key('toggle_active_${item.id}'),
        style: InsightsAdminTheme.secondaryActionStyle(),
        onPressed: onToggleActive,
        icon: Icon(
          item.isActive
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 16,
        ),
        label: Text(item.isActive ? 'Hide' : 'Show'),
      ),
      OutlinedButton.icon(
        key: Key('archive_${item.id}'),
        style: InsightsAdminTheme.secondaryActionStyle(
          destructiveHover: !isArchived,
        ),
        onPressed: onArchive,
        icon: Icon(
          isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
          size: 16,
        ),
        label: Text(isArchived ? 'Restore' : 'Archive'),
      ),
    ];

    return Container(
      key: Key('insight_row_${item.id}'),
      padding: const EdgeInsets.all(20),
      decoration: InsightsAdminTheme.cardDecoration,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wideHeader = constraints.maxWidth >= 420;
          final wideActions = constraints.maxWidth >= 500;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wideHeader)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: InsightsAdminColors.navy,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: statusPills,
                    ),
                  ],
                )
              else ...[
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: InsightsAdminColors.navy,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: statusPills),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: categoryTags),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: InsightsAdminColors.bodyMuted,
                    height: 1.45,
                  ),
                ),
              ],
              if (item.sourceTitle != null || item.sourceUrl != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.link_rounded,
                        size: 14,
                        color: InsightsAdminColors.subtleMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${item.sourceTitle ?? 'Untitled source'} — ${item.sourceUrl ?? 'no link'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: InsightsAdminColors.subtleMuted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (!eligible && item.provenanceGaps.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Needs: ${item.provenanceGaps.join(', ')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: InsightsAdminColors.subtleMuted,
                    height: 1.4,
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  height: 2,
                  width: double.infinity,
                  child: ColoredBox(color: InsightsAdminColors.canvas),
                ),
              ),
              if (wideActions)
                Row(
                  children: [
                    for (var i = 0; i < actionButtons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actionButtons[i]),
                    ],
                  ],
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final button in actionButtons)
                      SizedBox(
                        width: (constraints.maxWidth - 10) / 2,
                        child: button,
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
