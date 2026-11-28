import 'package:flutter/material.dart';

import '../../admin/theme/admin_theme.dart';
import '../data/admin_insight_catalog_repository.dart';
import '../models/insights_models.dart';
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
      data: AdminTheme.data.copyWith(visualDensity: VisualDensity.standard),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 20,
                runSpacing: 16,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Insights Content',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Curate and approve source-verified wellness guides',
                        style: TextStyle(color: AdminColors.muted),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminColors.accentSoft,
                      foregroundColor: AdminColors.ink,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('New insight'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                key: const Key('insights_summary_banner'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AdminColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminColors.border),
                ),
                child: Text(
                  '$eligible Featured-eligible • '
                  '${_items.length - eligible} Need provenance/review',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final entry in _statusFilters.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _status == entry.key,
                      onSelected: (_) => setState(() => _status = entry.key),
                    ),
                  DropdownButton<String?>(
                    value: _role,
                    items: [
                      for (final entry in _roleFilters.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) => setState(() => _role = value),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search insights',
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AdminColors.danger))
              else if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (visible.isEmpty)
                const Text('No insights match these filters.')
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
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final eligible = item.hasApprovedProvenance;
    final status = item.reviewStatus ?? 'draft';
    final isArchived = status == 'archived';
    return Container(
      key: Key('insight_row_${item.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(
                eligible ? 'Featured-eligible' : 'Library only',
                background: eligible
                    ? AdminColors.greenBg
                    : AdminColors.amberBg,
                foreground: eligible
                    ? AdminColors.greenFg
                    : AdminColors.amberFg,
              ),
              _Badge(status.replaceAll('_', ' ')),
              _Badge(item.isActive ? 'Active' : 'Hidden'),
              _Badge(item.category),
              if (item.sectionId.isNotEmpty) _Badge(item.sectionId),
              for (final role in item.targetRoles)
                _Badge(insightTargetRoleLabels[role] ?? role),
              for (final domain in item.domainIds) _Badge(domain),
            ],
          ),
          if (item.sourceTitle != null || item.sourceUrl != null) ...[
            const SizedBox(height: 6),
            Text(
              '${item.sourceTitle ?? 'Untitled source'} — ${item.sourceUrl ?? 'no link'}',
              style: const TextStyle(color: AdminColors.muted, fontSize: 12),
            ),
          ],
          if (!eligible && item.provenanceGaps.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Needs: ${item.provenanceGaps.join(', ')}',
              style: const TextStyle(color: AdminColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
              if (status != 'approved' && !isArchived)
                OutlinedButton(
                  key: Key('approve_${item.id}'),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              OutlinedButton(
                key: Key('toggle_active_${item.id}'),
                onPressed: onToggleActive,
                child: Text(item.isActive ? 'Hide' : 'Show'),
              ),
              OutlinedButton(
                key: Key('archive_${item.id}'),
                onPressed: onArchive,
                child: Text(isArchived ? 'Restore' : 'Archive'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.background, this.foreground});

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background ?? AdminColors.neutralBg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: foreground ?? AdminColors.neutralFg,
      ),
    ),
  );
}
