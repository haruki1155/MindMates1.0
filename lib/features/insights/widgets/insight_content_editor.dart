import 'package:flutter/material.dart';

import '../../../repositories/insights_seed_data.dart';
import '../../admin/theme/admin_theme.dart';
import '../data/admin_insight_catalog_repository.dart';
import '../models/insights_models.dart';
import '../services/insight_link_launcher.dart';

const insightTargetRoleLabels = {
  'all': 'Everyone',
  'student': 'Student',
  'teaching': 'Teaching',
  'nonTeaching': 'Non-Teaching',
};

const insightDomainIds = [
  'academicStress',
  'financialWellbeing',
  'socialAdjustment',
  'workplaceStress',
  'professionalSupport',
  'professionalWellbeing',
  'workplaceResponsibilities',
  'workplaceSupport',
  'workplaceWellbeing',
  'sleepRest',
  'emotionalWellbeing',
];

const _sections = {
  'recommended': 'Recommended for you',
  'wellbeing_101': 'Mental Wellbeing 101',
  'latest': 'The latest',
  'patterns': 'Your mental health patterns',
};

const _rightsLabels = {
  'original': 'Original MindMate summary',
  'open_license': 'Open license',
  'permission_granted': 'Permission granted',
};

const _reviewLabels = {
  'draft': 'Draft',
  'pending_review': 'Pending review',
  'approved': 'Approved',
  'archived': 'Archived',
};

/// Create or edit one `insight_content` document. Pops `true` after a save.
class InsightContentEditor extends StatefulWidget {
  const InsightContentEditor({super.key, required this.repository, this.item});

  final AdminInsightCatalogRepository repository;
  final InsightCardItem? item;

  @override
  State<InsightContentEditor> createState() => _InsightContentEditorState();
}

class _InsightContentEditorState extends State<InsightContentEditor> {
  final _formKey = GlobalKey<FormState>();
  late final InsightCardItem? _original = widget.item;
  late final _id = TextEditingController(text: _original?.id ?? '');
  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _subtitle = TextEditingController(text: _original?.subtitle ?? '');
  late final _body = TextEditingController(text: _original?.body ?? '');
  late final _categoryLabel = TextEditingController(
    text: _original?.category ?? '',
  );
  late final _tags = TextEditingController(
    text: _original?.tags.join(', ') ?? '',
  );
  late final _sortOrder = TextEditingController(
    text: '${_original?.sortOrder ?? 0}',
  );
  late final _sourceTitle = TextEditingController(
    text: _original?.sourceTitle ?? '',
  );
  late final _sourceUrl = TextEditingController(
    text: _original?.sourceUrl ?? '',
  );
  late String _categoryId = _known(
    _original?.categoryId,
    insightSeedCategories.map((c) => c['id'] as String),
  );
  late String _sectionId = _known(_original?.sectionId, _sections.keys);
  late bool _isActive = _original?.isActive ?? true;
  late Set<String> _roles = {...?_original?.targetRoles};
  late final Set<String> _domains = {...?_original?.domainIds};
  late String? _actionRoute = _original?.validActionRoute;
  late String? _evidenceType =
      insightEligibleEvidenceTypes.containsKey(_original?.evidenceType)
      ? _original?.evidenceType
      : null;
  late String? _rightsStatus =
      insightEligibleRightsStatuses.contains(_original?.rightsStatus)
      ? _original?.rightsStatus
      : null;
  late String _reviewStatus =
      insightReviewStatuses.contains(_original?.reviewStatus)
      ? _original!.reviewStatus!
      : 'draft';
  bool _idEdited = false;
  bool _saving = false;
  String? _error;

  bool get _isNew => _original == null;

  static String _known(String? value, Iterable<String> options) =>
      options.contains(value) ? value! : options.first;

  List<String> get _gaps => insightProvenanceGaps(
    sourceTitle: _sourceTitle.text,
    sourceUrl: _sourceUrl.text,
    evidenceType: _evidenceType,
    rightsStatus: _rightsStatus,
  );

  @override
  void dispose() {
    for (final controller in [
      _id,
      _title,
      _subtitle,
      _body,
      _categoryLabel,
      _tags,
      _sortOrder,
      _sourceTitle,
      _sourceUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTitleChanged(String value) {
    if (!_isNew || _idEdited) return;
    _id.text = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    setState(() {});
  }

  String? _trimOrNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  InsightCardItem _draft() {
    final original = _original;
    final category = insightSeedCategories.firstWhere(
      (c) => c['id'] == _categoryId,
    );
    return InsightCardItem(
      id: _id.text.trim(),
      title: _title.text.trim(),
      subtitle: _subtitle.text.trim(),
      body: _trimOrNull(_body.text),
      category: _trimOrNull(_categoryLabel.text) ?? category['label'] as String,
      categoryId: _categoryId,
      sectionId: _sectionId,
      imageAsset: original?.imageAsset ?? '',
      publishedAt: original?.publishedAt ?? DateTime.now(),
      contentType: original?.contentType ?? 'article',
      source: original?.source ?? 'MindMate',
      videoUrl: original?.videoUrl,
      thumbnailUrl: original?.thumbnailUrl,
      durationLabel: original?.durationLabel,
      tags: _tags.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
      isActive: _isActive,
      targetRoles: _roles.isEmpty ? const ['all'] : _roles.toList(),
      domainIds: _domains.toList(),
      actionRoute: _actionRoute,
      sourceTitle: _trimOrNull(_sourceTitle.text),
      sourceUrl: _trimOrNull(_sourceUrl.text),
      evidenceType: _evidenceType,
      rightsStatus: _rightsStatus,
      reviewStatus: _reviewStatus,
      reviewedAt: original?.reviewedAt,
      reviewedBy: original?.reviewedBy,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveContent(
        _draft(),
        reviewerUid: widget.repository.currentUid ?? '',
      );
      if (mounted) Navigator.of(context).pop(true);
    } on InsightCatalogValidationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to save. Check access and retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testLink() async {
    final uri = validInsightSourceUri(_sourceUrl.text);
    final messenger = ScaffoldMessenger.of(context);
    if (uri == null || !await openInsightSource(uri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a valid https:// link to test.')),
      );
    }
  }

  void _toggleRole(String role, bool selected) {
    setState(() {
      if (role == 'all') {
        _roles = selected ? {'all'} : {};
      } else {
        _roles = {..._roles}..remove('all');
        selected ? _roles.add(role) : _roles.remove(role);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gaps = _gaps;
    if (_reviewStatus == 'approved' && gaps.isNotEmpty) {
      // Provenance was edited after choosing approval; fall back safely.
      _reviewStatus = 'pending_review';
    }
    return Theme(
      data: AdminTheme.data,
      child: Scaffold(
        backgroundColor: AdminColors.canvas,
        appBar: AppBar(
          title: Text(_isNew ? 'New insight' : 'Edit insight'),
          backgroundColor: AdminColors.surface,
          foregroundColor: AdminColors.ink,
        ),
        body: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _Section(
                    title: '1. Content',
                    children: [
                      TextFormField(
                        key: const Key('insight_editor_title'),
                        controller: _title,
                        decoration: const InputDecoration(labelText: 'Title'),
                        onChanged: _onTitleChanged,
                        validator: (value) => value == null || value.isEmpty
                            ? 'A title is required.'
                            : null,
                      ),
                      TextFormField(
                        key: const Key('insight_editor_id'),
                        controller: _id,
                        readOnly: !_isNew,
                        decoration: const InputDecoration(
                          labelText: 'Document ID',
                          helperText: 'Lowercase letters, numbers, underscores',
                        ),
                        onChanged: (_) => _idEdited = true,
                      ),
                      TextFormField(
                        controller: _subtitle,
                        decoration: const InputDecoration(
                          labelText: 'Subtitle',
                        ),
                      ),
                      TextFormField(
                        controller: _body,
                        minLines: 4,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          labelText: 'Plain-language summary',
                          helperText:
                              'Write an original short summary. Do not paste the source text.',
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: [
                          for (final category in insightSeedCategories)
                            DropdownMenuItem(
                              value: category['id'] as String,
                              child: Text(category['label'] as String),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryId = value!),
                      ),
                      TextFormField(
                        controller: _categoryLabel,
                        decoration: const InputDecoration(
                          labelText: 'Card label (optional)',
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _sectionId,
                        decoration: const InputDecoration(labelText: 'Section'),
                        items: [
                          for (final entry in _sections.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _sectionId = value!),
                      ),
                      TextFormField(
                        controller: _tags,
                        decoration: const InputDecoration(
                          labelText: 'Tags (comma-separated)',
                        ),
                      ),
                      TextFormField(
                        controller: _sortOrder,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Sort order',
                        ),
                        validator: (value) =>
                            int.tryParse(value?.trim() ?? '') == null
                            ? 'Enter a whole number.'
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Visible in the mobile app'),
                        value: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                      ),
                    ],
                  ),
                  _Section(
                    title: '2. Role & signal targeting',
                    children: [
                      const Text('Audience'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in insightTargetRoleLabels.entries)
                            FilterChip(
                              label: Text(entry.value),
                              selected: _roles.contains(entry.key),
                              onSelected: (value) =>
                                  _toggleRole(entry.key, value),
                            ),
                        ],
                      ),
                      const Text('Assessment domains'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final domain in insightDomainIds)
                            FilterChip(
                              label: Text(domain),
                              selected: _domains.contains(domain),
                              onSelected: (value) => setState(
                                () => value
                                    ? _domains.add(domain)
                                    : _domains.remove(domain),
                              ),
                            ),
                        ],
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue: _actionRoute,
                        decoration: const InputDecoration(
                          labelText: 'In-app action (optional)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final entry in insightActionRouteLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _actionRoute = value),
                      ),
                    ],
                  ),
                  _Section(
                    title: '3. Source provenance & review',
                    children: [
                      TextFormField(
                        key: const Key('insight_editor_source_title'),
                        controller: _sourceTitle,
                        decoration: const InputDecoration(
                          labelText: 'Source title',
                          helperText: 'e.g. WHO — Mental Health at Work',
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('insight_editor_source_url'),
                              controller: _sourceUrl,
                              decoration: const InputDecoration(
                                labelText: 'Source link',
                              ),
                              validator: (value) =>
                                  value != null &&
                                      value.trim().isNotEmpty &&
                                      validInsightSourceUri(value) == null
                                  ? 'Use a full https:// link without credentials.'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _testLink,
                            child: const Text('Test link'),
                          ),
                        ],
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue: _evidenceType,
                        decoration: const InputDecoration(
                          labelText: 'Evidence type',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Not set'),
                          ),
                          for (final entry
                              in insightEligibleEvidenceTypes.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _evidenceType = value),
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue: _rightsStatus,
                        decoration: const InputDecoration(
                          labelText: 'Rights status',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Not cleared'),
                          ),
                          for (final entry in _rightsLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _rightsStatus = value),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('review_$_reviewStatus'),
                        initialValue: _reviewStatus,
                        decoration: const InputDecoration(
                          labelText: 'Review status',
                        ),
                        items: [
                          for (final entry in _reviewLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              enabled: entry.key != 'approved' || gaps.isEmpty,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _reviewStatus = value!),
                      ),
                      _EligibilityChecklist(
                        gaps: gaps,
                        approved: _reviewStatus == 'approved',
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        key: const Key('insight_editor_error'),
                        style: const TextStyle(color: AdminColors.danger),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('insight_editor_save'),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save insight'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: AdminColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            for (final child in children) ...[
              const SizedBox(height: 12),
              child,
            ],
          ],
        ),
      ),
    ),
  );
}

class _EligibilityChecklist extends StatelessWidget {
  const _EligibilityChecklist({required this.gaps, required this.approved});

  final List<String> gaps;
  final bool approved;

  @override
  Widget build(BuildContext context) {
    final checks = {
      'Source title': !gaps.contains('Source title'),
      'HTTPS source link': !gaps.contains('HTTPS source link'),
      'Eligible evidence type': !gaps.contains('Eligible evidence type'),
      'Cleared rights status': !gaps.contains('Cleared rights status'),
      'Review approved': approved,
    };
    return Column(
      key: const Key('insight_eligibility_checklist'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Featured Recommendation eligibility',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final entry in checks.entries)
          Row(
            children: [
              Icon(
                entry.value ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: entry.value ? AdminColors.success : AdminColors.muted,
              ),
              const SizedBox(width: 6),
              Text(entry.key),
            ],
          ),
      ],
    );
  }
}
