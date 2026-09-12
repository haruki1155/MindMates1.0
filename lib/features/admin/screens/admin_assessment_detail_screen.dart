import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/assessment_explanation_model.dart';
import '../../../repositories/admin_status_repository.dart';
import '../theme/admin_theme.dart';

class AdminAssessmentDetailScreen extends StatelessWidget {
  const AdminAssessmentDetailScreen({
    required this.userId,
    required this.userLabel,
    required this.repository,
    this.assessmentId,
    super.key,
  });

  final String userId;
  final String userLabel;
  final AdminStatusRepository repository;
  final String? assessmentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assessment details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'User reference: ${_abbreviate(userLabel)}',
              style: const TextStyle(
                color: AdminColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repository.fetchUserAssessments(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load assessments.'));
          }
          final loaded = snapshot.data ?? const <Map<String, dynamic>>[];
          final assessments = assessmentId == null
              ? loaded
              : loaded
                    .where((item) => item['id']?.toString() == assessmentId)
                    .toList();
          if (assessments.isEmpty) {
            return const Center(child: Text('No assessments available.'));
          }
          return ListView.separated(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
            ),
            itemCount: assessments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: _AssessmentCard(
                  assessment: assessments[index],
                  previous: index + 1 < assessments.length
                      ? assessments[index + 1]
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.assessment, this.previous});

  final Map<String, dynamic> assessment;
  final Map<String, dynamic>? previous;

  @override
  Widget build(BuildContext context) {
    final interpretation = _map(assessment['interpretation']);
    if (interpretation == null) {
      return Card(
        child: ListTile(
          title: const Text('Legacy assessment'),
          subtitle: Text(
            '${assessment['status'] ?? assessment['overallLevel'] ?? 'Result available'} — '
            'not recalculated with the current algorithm.',
          ),
        ),
      );
    }
    final quality = _map(interpretation['responseQuality']);
    final domains = _maps(interpretation['domainResults']);
    final explanation = AssessmentExplanationModel.fromAssessment(assessment);
    final String confidenceText;
    if (explanation.responseConfidence.isNotEmpty) {
      confidenceText = explanation.responseConfidence;
    } else {
      confidenceText = quality?['confidenceLabel']?.toString() ?? 'Unavailable';
    }
    final compatible =
        previous != null &&
        previous!['algorithmVersion'] == assessment['algorithmVersion'] &&
        previous!['questionSetVersion'] == assessment['questionSetVersion'];
    final previousDomains = compatible
        ? _maps(_map(previous!['interpretation'])?['domainResults'])
        : const <Map<String, dynamic>>[];
    return Card(
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 18 : 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MetadataChip(
                  icon: Icons.assignment_outlined,
                  label: _assessmentType(assessment),
                ),
                _MetadataChip(
                  icon: Icons.calendar_today_outlined,
                  label: _date(assessment['createdAt']),
                ),
                _MetadataChip(
                  icon: Icons.fact_check_outlined,
                  label: confidenceText,
                ),
                if (explanation.presentedCount > 0)
                  _MetadataChip(
                    icon: Icons.check_circle_outline,
                    label:
                        '${explanation.answeredCount} of ${explanation.presentedCount} answered',
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              explanation.patternLabel,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              explanation.counselorSummary.isNotEmpty
                  ? explanation.counselorSummary
                  : explanation.summary,
              style: const TextStyle(
                color: AdminColors.muted,
                fontSize: 15,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            _GuidanceCallout(message: explanation.followUpGuidance),
            const Divider(height: 48),
            const _SectionHeading(
              title: 'Interpretation basis',
              description:
                  'Factors used to form this response pattern and follow-up guidance.',
            ),
            const SizedBox(height: 12),
            _BulletList(values: explanation.rationale),
            const SizedBox(height: 28),
            _SectionHeading(
              title: explanation.isQuick
                  ? 'Brief response indicators'
                  : 'Well-being areas',
              description: explanation.isQuick
                  ? 'Each indicator reflects one quick-check response and is not a category-level conclusion.'
                  : 'A structured view of the response pattern across assessed areas.',
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth >= 760
                    ? (box.maxWidth - 12) / 2
                    : box.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: explanation.areas
                      .map(
                        (area) => SizedBox(
                          width: width,
                          child: _AreaPanel(
                            name: area.name,
                            pattern: area.patternLabel,
                            completion:
                                '${area.answeredCount}/${area.presentedCount} answered',
                            explanation: area.explanation,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 28),
            LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth >= 760
                    ? (box.maxWidth - 12) / 2
                    : box.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _InsightPanel(
                        icon: Icons.check_circle_outline,
                        title: 'Current strengths',
                        values: explanation.strengthInsights,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _InsightPanel(
                        icon: Icons.explore_outlined,
                        title: 'Areas to explore',
                        values: explanation.focusInsights,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 14),
              title: const Text(
                'Clinical review details',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Flagged responses, supportive factors, and follow-up actions',
              ),
              children: [
                _ListSection(
                  title: 'Flagged responses by category',
                  values: domains
                      .expand(
                        (domain) => _strings(
                          domain['elevatedIndicators'],
                        ).map((item) => '${domain['domain']}: $item'),
                      )
                      .toList(),
                ),
                _ListSection(
                  title: 'Supportive responses',
                  values: explanation.protectiveFactors,
                ),
                _ListSection(
                  title: 'Functional-impact indicators',
                  values: explanation.functionalImpactFlags,
                ),
                _ListSection(
                  title: 'Suggested follow-up',
                  values: explanation.suggestedActions,
                ),
              ],
            ),
            if (compatible)
              _TrendSection(current: domains, previous: previousDomains)
            else
              const _MutedNotice(
                message:
                    'Trend comparison is unavailable because there is no preceding version-compatible assessment.',
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 14),
              title: const Text(
                'Authorized raw responses',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Restricted clinical review information'),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AdminColors.canvas,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    (assessment['responses'] ??
                            assessment['answers'] ??
                            const [])
                        .toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _MutedNotice(
              icon: Icons.info_outline,
              message:
                  'This university wellness-awareness screening is not a diagnosis and does not replace professional clinical judgment.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AdminColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AdminColors.muted),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _GuidanceCallout extends StatelessWidget {
  const _GuidanceCallout({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminColors.accentFaint,
      border: Border.all(color: AdminColors.accentSoft),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.priority_high_rounded, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Follow-up guidance',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        description,
        style: const TextStyle(
          color: AdminColors.muted,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    ],
  );
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.values});
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Text(
        'No additional indicators were recorded.',
        style: TextStyle(color: AdminColors.muted, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: values
          .map(
            (value) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: AdminColors.muted,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _AreaPanel extends StatelessWidget {
  const _AreaPanel({
    required this.name,
    required this.pattern,
    required this.completion,
    required this.explanation,
  });
  final String name;
  final String pattern;
  final String completion;
  final String explanation;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AdminColors.canvas,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AdminColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              completion,
              style: const TextStyle(color: AdminColors.muted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          pattern,
          style: const TextStyle(
            color: AdminColors.accentStrong,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          explanation,
          style: const TextStyle(
            color: AdminColors.muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({
    required this.icon,
    required this.title,
    required this.values,
  });
  final IconData icon;
  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BulletList(values: values),
      ],
    ),
  );
}

class _MutedNotice extends StatelessWidget {
  const _MutedNotice({required this.message, this.icon = Icons.timeline});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AdminColors.canvas,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AdminColors.muted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AdminColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.current, required this.previous});

  final List<Map<String, dynamic>> current;
  final List<Map<String, dynamic>> previous;

  @override
  Widget build(BuildContext context) {
    final previousStatuses = {
      for (final domain in previous.where(
        (domain) => domain['isScorable'] == true,
      ))
        domain['domain']?.toString() ?? '':
            (domain['bandLabel'] ?? domain['band']).toString(),
    };
    final comparable = current.where(
      (domain) =>
          domain['isScorable'] == true &&
          previousStatuses.containsKey(domain['domain']?.toString()),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminColors.accentFaint,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.accentSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trend from the preceding compatible assessment',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final domain in comparable)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${domain['domain']}: '
                  '${previousStatuses[domain['domain']]} → '
                  '${domain['bandLabel'] ?? domain['band']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.canvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 9),
          _BulletList(values: values),
        ],
      ),
    );
  }
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.map(_map).whereType<Map<String, dynamic>>().toList()
    : const [];

List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];

String _assessmentType(Map<String, dynamic> assessment) {
  final type = assessment['type']?.toString().toLowerCase() ?? '';
  return type == 'quick' ? 'Quick Assessment' : 'Psychological Assessment';
}

String _abbreviate(String value) {
  if (value.length <= 18) return value;
  return '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
}

String _date(Object? value) {
  final date = value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'Date unavailable';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
