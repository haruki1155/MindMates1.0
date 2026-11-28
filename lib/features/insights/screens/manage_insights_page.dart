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

  Widget _buildCard(InsightCardItem item, {required bool compactActions}) =>
      _InsightRow(
        item: item,
        compactActions: compactActions,
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
      );

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final eligible = _items.where((item) => item.hasApprovedProvenance).length;
    final summaryText =
        '$eligible Featured-eligible • '
        '${_items.length - eligible} Need provenance/review';

    return Theme(
      data: InsightsAdminTheme.data,
      child: ColoredBox(
        key: const Key('insights_page_canvas'),
        color: InsightsAdminColors.canvas,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wideHeader = constraints.maxWidth >= 660;
                    const titleBlock = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Insights Content',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: InsightsAdminColors.navy,
                            letterSpacing: -0.5,
                            height: 1.15,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Curate and approve source-verified wellness guides',
                          style: TextStyle(
                            fontSize: 14,
                            color: InsightsAdminColors.bodyMuted,
                          ),
                        ),
                      ],
                    );

                    final actionColumn = Column(
                      crossAxisAlignment: wideHeader
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        FilledButton.icon(
                          key: const Key('new_insight_button'),
                          style: InsightsAdminTheme.newInsightButtonStyle,
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New insight'),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          key: const Key('insights_summary_banner'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: const BoxDecoration(
                            color: InsightsAdminColors.summaryPillBg,
                            borderRadius: InsightsAdminTheme.pillRadius,
                          ),
                          child: Text(
                            summaryText,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: InsightsAdminColors.navy,
                            ),
                          ),
                        ),
                      ],
                    );

                    if (wideHeader) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(child: titleBlock),
                          const SizedBox(width: 20),
                          actionColumn,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleBlock,
                        const SizedBox(height: 14),
                        actionColumn,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                _InsightsFilterBar(
                  statusFilters: _statusFilters,
                  selectedStatus: _status,
                  onStatusChanged: (value) => setState(() => _status = value),
                  roleFilters: _roleFilters,
                  selectedRole: _role,
                  onRoleChanged: (value) => setState(() => _role = value),
                  onQueryChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 18),
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 820;
                      const columnGap = 16.0;
                      final cardInnerWidth =
                          (twoColumns
                              ? (constraints.maxWidth - columnGap) / 2
                              : constraints.maxWidth) -
                          40;
                      final compactActions = cardInnerWidth < 330;

                      if (!twoColumns) {
                        return Column(
                          key: const Key('insights_card_grid_single'),
                          children: [
                            for (var i = 0; i < visible.length; i++) ...[
                              if (i > 0) const SizedBox(height: 16),
                              _buildCard(
                                visible[i],
                                compactActions: compactActions,
                              ),
                            ],
                          ],
                        );
                      }

                      return Column(
                        key: const Key('insights_card_grid_two_col'),
                        children: [
                          for (var i = 0; i < visible.length; i += 2) ...[
                            if (i > 0) const SizedBox(height: 16),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildCard(
                                      visible[i],
                                      compactActions: compactActions,
                                    ),
                                  ),
                                  const SizedBox(width: columnGap),
                                  Expanded(
                                    child: i + 1 < visible.length
                                        ? _buildCard(
                                            visible[i + 1],
                                            compactActions: compactActions,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
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
    final roleDropdown = Container(
      key: const Key('insights_role_filter'),
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
            fontWeight: FontWeight.w500,
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
      height: 42,
      child: TextField(
        key: const Key('insights_search_field'),
        style: const TextStyle(
          fontSize: 13.5,
          color: InsightsAdminColors.navy,
        ),
        decoration: const InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 19,
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
        final compactSegment = constraints.maxWidth < 520;
        final segmentedControl = _StatusSegmentedControl(
          filters: statusFilters,
          selected: selectedStatus,
          onSelected: onStatusChanged,
          pillContainer: !compactSegment,
        );

        if (constraints.maxWidth >= 880) {
          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: segmentedControl),
                    const SizedBox(width: 12),
                    roleDropdown,
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 230, child: searchField),
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
              width: constraints.maxWidth < 360 ? constraints.maxWidth : 230,
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
    required this.pillContainer,
  });

  final Map<String?, String> filters;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool pillContainer;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('insights_status_segmented_control'),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: InsightsAdminColors.surface,
      borderRadius: pillContainer
          ? InsightsAdminTheme.pillRadius
          : InsightsAdminTheme.controlRadius,
      border: Border.all(color: InsightsAdminColors.controlBorder, width: 1),
    ),
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
    color: selected ? InsightsAdminColors.ctaYellow : Colors.transparent,
    borderRadius: InsightsAdminTheme.pillRadius,
    child: InkWell(
      onTap: onPressed,
      borderRadius: InsightsAdminTheme.pillRadius,
      hoverColor: selected
          ? InsightsAdminColors.ctaYellowHover
          : InsightsAdminColors.canvas,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: InsightsAdminColors.navy,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: InsightsAdminColors.navy,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.item,
    required this.compactActions,
    required this.onEdit,
    required this.onApprove,
    required this.onToggleActive,
    required this.onArchive,
  });

  final InsightCardItem item;
  final bool compactActions;
  final VoidCallback onEdit;
  final VoidCallback? onApprove;
  final VoidCallback onToggleActive;
  final VoidCallback onArchive;

  String get _description {
    final subtitle = item.subtitle.trim();
    if (subtitle.isNotEmpty) return subtitle;
    return item.body?.trim() ?? '';
  }

  Widget _actionLabel(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 15),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final eligible = item.hasApprovedProvenance;
    final status = item.reviewStatus ?? 'draft';
    final isArchived = status == 'archived';
    final description = _description;
    final showApprove = status != 'approved' && !isArchived;
    final needsProvenance = !eligible && item.provenanceGaps.isNotEmpty;

    final categoryTags = <Widget>[
      for (final role in item.targetRoles)
        InsightsCategoryTag(insightTargetRoleLabels[role] ?? role),
      for (final domain in item.domainIds) InsightsCategoryTag(domain),
      if (item.domainIds.isEmpty && item.category.trim().isNotEmpty)
        InsightsCategoryTag(item.category),
      InsightsCategoryTag(
        eligible ? 'Featured-eligible' : 'Library only',
        icon: eligible ? Icons.verified_outlined : null,
        muted: !eligible,
        highlighted: eligible,
      ),
    ];

    final actions = <(int, Widget)>[
      (
        10,
        OutlinedButton(
          key: Key('edit_${item.id}'),
          style: InsightsAdminTheme.secondaryActionStyle(),
          onPressed: onEdit,
          child: _actionLabel(Icons.edit_outlined, 'Edit'),
        ),
      ),
      if (showApprove)
        (
          13,
          Tooltip(
            message: onApprove == null
                ? 'Complete source provenance before approving'
                : 'Approve for Featured recommendations',
            child: FilledButton(
              key: Key('approve_${item.id}'),
              style: InsightsAdminTheme.primaryActionStyle,
              onPressed: onApprove,
              child: _actionLabel(Icons.check_rounded, 'Approve'),
            ),
          ),
        ),
      (
        10,
        OutlinedButton(
          key: Key('toggle_active_${item.id}'),
          style: InsightsAdminTheme.secondaryActionStyle(),
          onPressed: onToggleActive,
          child: _actionLabel(
            item.isActive
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            item.isActive ? 'Hide' : 'Show',
          ),
        ),
      ),
      (
        12,
        OutlinedButton(
          key: Key('archive_${item.id}'),
          style: InsightsAdminTheme.secondaryActionStyle(
            destructiveHover: !isArchived,
          ),
          onPressed: onArchive,
          child: _actionLabel(
            isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
            isArchived ? 'Restore' : 'Archive',
          ),
        ),
      ),
    ];

    return Container(
      key: Key('insight_row_${item.id}'),
      padding: const EdgeInsets.all(20),
      decoration: InsightsAdminTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: InsightsAdminColors.navy,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (needsProvenance) ...[
                    const SizedBox(width: 10),
                    InsightsStatusPill.needsProvenance(
                      key: Key('needs_provenance_${item.id}'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  InsightsStatusPill.active(item.isActive),
                  InsightsStatusPill.reviewStatus(status),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: categoryTags),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: InsightsAdminColors.bodyText,
                    height: 1.42,
                  ),
                ),
              ],
              if (item.sourceTitle != null || item.sourceUrl != null) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.link_rounded,
                        size: 13,
                        color: InsightsAdminColors.subtleMuted,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${item.sourceTitle ?? 'Untitled source'} — ${item.sourceUrl ?? 'no link'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: InsightsAdminColors.subtleMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (needsProvenance) ...[
                const SizedBox(height: 6),
                Text(
                  'Needs: ${item.provenanceGaps.join(', ')}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: InsightsAdminColors.bodyMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
          Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 14, bottom: 12),
                child: SizedBox(
                  height: 2,
                  width: double.infinity,
                  child: ColoredBox(color: InsightsAdminColors.canvas),
                ),
              ),
              if (!compactActions)
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(flex: actions[i].$1, child: actions[i].$2),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < actions.length; i += 2) ...[
                      if (i > 0) const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: actions[i].$2),
                          if (i + 1 < actions.length) ...[
                            const SizedBox(width: 8),
                            Expanded(child: actions[i + 1].$2),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
