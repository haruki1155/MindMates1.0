import 'package:flutter/material.dart';

import '../../../repositories/insights_seed_data.dart';
import '../data/admin_insight_catalog_repository.dart';
import '../models/insights_models.dart';
import '../services/insight_link_launcher.dart';
import '../theme/insights_admin_theme.dart';

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
      data: InsightsAdminTheme.data,
      child: Scaffold(
        key: const Key('insight_editor_scaffold'),
        backgroundColor: InsightsAdminColors.canvas,
        appBar: AppBar(
          title: Text(
            _isNew ? 'New insight' : 'Edit insight',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: InsightsAdminColors.navy,
            ),
          ),
          backgroundColor: InsightsAdminColors.surface,
          foregroundColor: InsightsAdminColors.navy,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: SizedBox(
              height: 1,
              width: double.infinity,
              child: ColoredBox(color: InsightsAdminColors.cardBorder),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InsightsStatusPill.active(_isActive),
                  const SizedBox(width: 8),
                  InsightsStatusPill.reviewStatus(_reviewStatus),
                ],
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _isNew
                          ? 'Create a source-verified wellness guide for the Insights catalog.'
                          : 'Update guide details, audience targeting, and source provenance.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: InsightsAdminColors.bodyMuted,
                      ),
                    ),
                  ),
                  _Section(
                    step: '1',
                    title: 'Content',
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
                        decoration: InputDecoration(
                          labelText: 'Document ID',
                          helperText: 'Lowercase letters, numbers, underscores',
                          fillColor: _isNew
                              ? InsightsAdminColors.surface
                              : InsightsAdminColors.canvas,
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
                      _FieldPair(
                        left: DropdownButtonFormField<String>(
                          initialValue: _categoryId,
                          isExpanded: true,
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
                        right: TextFormField(
                          controller: _categoryLabel,
                          decoration: const InputDecoration(
                            labelText: 'Card label (optional)',
                          ),
                        ),
                      ),
                      _FieldPair(
                        left: DropdownButtonFormField<String>(
                          initialValue: _sectionId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Section',
                          ),
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
                        right: TextFormField(
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
                      ),
                      TextFormField(
                        controller: _tags,
                        decoration: const InputDecoration(
                          labelText: 'Tags (comma-separated)',
                        ),
                      ),
                      Material(
                        color: InsightsAdminColors.canvas,
                        shape: const RoundedRectangleBorder(
                          borderRadius: InsightsAdminTheme.controlRadius,
                          side: BorderSide(
                            color: InsightsAdminColors.controlBorder,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          title: const Text(
                            'Visible in the mobile app',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: InsightsAdminColors.navy,
                            ),
                          ),
                          subtitle: const Text(
                            'Active guides are available in the mobile Insights library.',
                            style: TextStyle(
                              fontSize: 12,
                              color: InsightsAdminColors.subtleMuted,
                            ),
                          ),
                          value: _isActive,
                          onChanged: (value) =>
                              setState(() => _isActive = value),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    step: '2',
                    title: 'Role & signal targeting',
                    children: [
                      const Text(
                        'Audience',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: InsightsAdminColors.navy,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in insightTargetRoleLabels.entries)
                            FilterChip(
                              label: Text(entry.value),
                              selected: _roles.contains(entry.key),
                              side: BorderSide(
                                color: _roles.contains(entry.key)
                                    ? InsightsAdminColors.primaryBlue
                                    : InsightsAdminColors.controlBorder,
                              ),
                              onSelected: (value) =>
                                  _toggleRole(entry.key, value),
                            ),
                        ],
                      ),
                      const Text(
                        'Assessment domains',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: InsightsAdminColors.navy,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final domain in insightDomainIds)
                            FilterChip(
                              label: Text(domain),
                              selected: _domains.contains(domain),
                              side: BorderSide(
                                color: _domains.contains(domain)
                                    ? InsightsAdminColors.primaryBlue
                                    : InsightsAdminColors.controlBorder,
                              ),
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
                        isExpanded: true,
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
                    step: '3',
                    title: 'Source provenance & review',
                    children: [
                      TextFormField(
                        key: const Key('insight_editor_source_title'),
                        controller: _sourceTitle,
                        decoration: const InputDecoration(
                          labelText: 'Source title',
                          helperText: 'e.g. WHO — Mental Health at Work',
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final field = TextFormField(
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
                          );
                          final button = OutlinedButton.icon(
                            style: InsightsAdminTheme.secondaryActionStyle(
                              minHeight: 48,
                            ),
                            onPressed: _testLink,
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                            ),
                            label: const Text('Test link'),
                          );
                          if (constraints.maxWidth >= 420) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: field),
                                const SizedBox(width: 10),
                                button,
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              field,
                              const SizedBox(height: 10),
                              button,
                            ],
                          );
                        },
                      ),
                      _FieldPair(
                        left: DropdownButtonFormField<String?>(
                          initialValue: _evidenceType,
                          isExpanded: true,
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
                        right: DropdownButtonFormField<String?>(
                          initialValue: _rightsStatus,
                          isExpanded: true,
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
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('review_$_reviewStatus'),
                        initialValue: _reviewStatus,
                        isExpanded: true,
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
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
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
                              key: const Key('insight_editor_error'),
                              style: const TextStyle(
                                color: InsightsAdminColors.dangerFg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: InsightsAdminTheme.cardDecoration,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          key: const Key('insight_editor_cancel'),
                          style: InsightsAdminTheme.secondaryActionStyle(),
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.icon(
                          key: const Key('insight_editor_save'),
                          style: InsightsAdminTheme.primaryActionStyle,
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: Text(_saving ? 'Saving…' : 'Save insight'),
                        ),
                      ],
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

class _FieldPair extends StatelessWidget {
  const _FieldPair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 560) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: 14), right],
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.step,
    required this.title,
    required this.children,
  });

  final String step;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: InsightsAdminTheme.cardDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: const BoxDecoration(
                color: InsightsAdminColors.tagBlueBg,
                borderRadius: InsightsAdminTheme.tagRadius,
              ),
              child: Text(
                step,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: InsightsAdminColors.navy,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: InsightsAdminColors.navy,
                ),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: SizedBox(
            height: 2,
            width: double.infinity,
            child: ColoredBox(color: InsightsAdminColors.canvas),
          ),
        ),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          children[i],
        ],
      ],
    ),
  );
}

class _EligibilityChecklist extends StatelessWidget {
  const _EligibilityChecklist({required this.gaps, required this.approved});

  final List<String> gaps;
  final bool approved;

  @override
  Widget build(BuildContext context) {
    final ready = gaps.isEmpty && approved;
    final checks = {
      'Source title': !gaps.contains('Source title'),
      'HTTPS source link': !gaps.contains('HTTPS source link'),
      'Eligible evidence type': !gaps.contains('Eligible evidence type'),
      'Cleared rights status': !gaps.contains('Cleared rights status'),
      'Review approved': approved,
    };
    return Container(
      key: const Key('insight_eligibility_checklist'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: InsightsAdminColors.canvas,
        borderRadius: InsightsAdminTheme.controlRadius,
        border: Border.all(color: InsightsAdminColors.controlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Text(
                  'Featured Recommendation eligibility',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: InsightsAdminColors.navy,
                  ),
                ),
                InsightsStatusPill(
                  label: ready ? 'Featured-eligible' : 'Library only',
                  background: ready
                      ? InsightsAdminColors.activeBg
                      : InsightsAdminColors.amberBg,
                  foreground: ready
                      ? InsightsAdminColors.activeFg
                      : InsightsAdminColors.amberFg,
                  borderColor: ready
                      ? InsightsAdminColors.activeBorder
                      : InsightsAdminColors.amberBorder,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in checks.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    entry.value
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: entry.value
                        ? InsightsAdminColors.activeFg
                        : InsightsAdminColors.disabledFg,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: entry.value
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: entry.value
                            ? InsightsAdminColors.navy
                            : InsightsAdminColors.bodyMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
