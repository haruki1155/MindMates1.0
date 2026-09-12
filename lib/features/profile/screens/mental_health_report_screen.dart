import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/report_model.dart';
import '../../../models/assessment_explanation_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';

class MentalHealthReportScreen extends StatefulWidget {
  const MentalHealthReportScreen({super.key});

  @override
  State<MentalHealthReportScreen> createState() =>
      _MentalHealthReportScreenState();
}

class _MentalHealthReportScreenState extends State<MentalHealthReportScreen> {
  String? _loadedUserId;
  bool _isRefreshing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = _currentUserId(hydrate: true);
    if (userId == null || userId.isEmpty || _loadedUserId == userId) return;
    _loadedUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAssessmentSummary(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = _watchProviderOrNull<ReportProvider>();
    final userId = _currentUserId();
    return Scaffold(
      backgroundColor: const Color(0xFFFAF4E1),
      appBar: AppBar(
        title: const Text('Mental Health Summary'),
        backgroundColor: const Color(0xFFFFCA24),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: userId == null || userId.isEmpty
          ? const _StatusMessage(
              message: 'Please sign in to view your assessment summary.',
            )
          : RefreshIndicator(
              onRefresh: () => _loadAssessmentSummary(userId),
              child: _AssessmentSummaryBody(
                report: provider?.latestReport,
                isLoading: provider?.isLoading ?? false,
                errorMessage: provider?.errorMessage,
              ),
            ),
    );
  }

  Future<void> _loadAssessmentSummary(String userId) async {
    if (_isRefreshing) return;
    final provider = _readProviderOrNull<ReportProvider>();
    if (provider == null) return;
    _isRefreshing = true;
    try {
      // Rebuild on every visit/refresh so the latest of the two allowed weekly
      // full assessments is reflected immediately.
      await provider.refreshWeeklyReport(userId);
    } finally {
      _isRefreshing = false;
    }
  }

  String? _currentUserId({bool hydrate = false}) {
    final auth = _readProviderOrNull<AuthProvider>();
    final authId =
        auth?.userId ?? (hydrate ? auth?.hydrateCurrentUser() : null);
    if (authId != null && authId.isNotEmpty) return authId;
    final profileId = _readProviderOrNull<UserProvider>()?.user?.id;
    return profileId == null || profileId.isEmpty ? null : profileId;
  }

  T? _readProviderOrNull<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  T? _watchProviderOrNull<T>() {
    try {
      return context.watch<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _AssessmentSummaryBody extends StatelessWidget {
  const _AssessmentSummaryBody({
    required this.report,
    required this.isLoading,
    required this.errorMessage,
  });

  final ReportModel? report;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (report == null && isLoading) {
      return const _StatusMessage(child: CircularProgressIndicator());
    }
    if (report == null) {
      return _StatusMessage(
        message:
            errorMessage ??
            'Complete a Quick or Full Assessment to create your mental health summary.',
      );
    }

    final value = report!;
    final hasQuick =
        value.quickAssessmentExplanation != null ||
        value.quickAssessmentStatus != null ||
        value.quickAssessmentSummary != null;
    final hasFull =
        value.fullAssessmentExplanation != null ||
        value.fullAssessmentStatus != null ||
        value.fullAssessmentSummary != null;
    if (!hasQuick && !hasFull) {
      return const _StatusMessage(
        message:
            'Complete a Quick or Full Assessment to create your mental health summary.',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        const _IntroCard(),
        if (hasFull) ...[
          const SizedBox(height: 14),
          if (value.fullAssessmentExplanation != null)
            _AssessmentExplanationCard(
              title: 'Latest Full Well-Being Assessment',
              explanation: value.fullAssessmentExplanation!,
            )
          else
            _AssessmentResultCard(
              title: 'Latest Psychological Assessment',
              status: value.fullAssessmentStatus ?? 'Result available',
              summary:
                  value.fullAssessmentSummary ??
                  'Your latest full assessment result is available.',
              sectorStatuses: value.fullAssessmentDomainStatuses,
            ),
        ],
        if (hasQuick) ...[
          const SizedBox(height: 14),
          if (value.quickAssessmentExplanation != null)
            _AssessmentExplanationCard(
              title: 'Latest Quick Check-In',
              explanation: value.quickAssessmentExplanation!,
            )
          else
            _AssessmentResultCard(
              title: 'Quick Assessment',
              status: value.quickAssessmentStatus ?? 'Result available',
              summary:
                  value.quickAssessmentSummary ??
                  'Your quick assessment result is available.',
              sectorStatuses: value.quickAssessmentAreaStatuses,
            ),
        ],
        const SizedBox(height: 14),
        _HistoryNote(assessmentCount: value.assessmentCount),
        const SizedBox(height: 14),
        const _Disclaimer(),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(errorMessage!, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) => const _Panel(
    color: Color(0xFFFFF0BA),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.health_and_safety_outlined, size: 30),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your assessment-based well-being summary',
                style: _TextStyles.heading,
              ),
              SizedBox(height: 7),
              Text(
                'This page shows the exact latest summaries from your Quick and Psychological Assessments. New full assessments replace the current result here while every attempt remains recorded for authorized review.',
                style: _TextStyles.body,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AssessmentResultCard extends StatelessWidget {
  const _AssessmentResultCard({
    required this.title,
    required this.status,
    required this.summary,
    required this.sectorStatuses,
  });

  final String title;
  final String status;
  final String summary;
  final Map<String, String> sectorStatuses;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: _TextStyles.heading)),
            _StatusChip(label: _readable(status)),
          ],
        ),
        const SizedBox(height: 12),
        Text(summary, style: _TextStyles.body),
        if (sectorStatuses.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Well-being status by sector', style: _TextStyles.section),
          const SizedBox(height: 9),
          for (final entry in sectorStatuses.entries) ...[
            Row(
              children: [
                Expanded(child: Text(entry.key, style: _TextStyles.body)),
                const SizedBox(width: 10),
                _StatusChip(label: _readable(entry.value), compact: true),
              ],
            ),
            if (entry.key != sectorStatuses.keys.last)
              const Divider(height: 18),
          ],
        ],
      ],
    ),
  );
}

class _AssessmentExplanationCard extends StatelessWidget {
  const _AssessmentExplanationCard({
    required this.title,
    required this.explanation,
  });

  final String title;
  final AssessmentExplanationModel explanation;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _TextStyles.heading),
        const SizedBox(height: 5),
        Text(_metadata(explanation), style: _TextStyles.muted),
        const SizedBox(height: 16),
        const Text('Your well-being profile', style: _TextStyles.section),
        const SizedBox(height: 8),
        _StatusChip(label: explanation.patternLabel),
        const SizedBox(height: 14),
        const Text('At a glance', style: _TextStyles.section),
        const SizedBox(height: 6),
        Text(explanation.summary, style: _TextStyles.body),
        if (explanation.strengthInsights.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Your strengths', style: _TextStyles.section),
          const SizedBox(height: 6),
          _BulletList(items: explanation.strengthInsights),
        ],
        if (explanation.focusInsights.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Areas to explore', style: _TextStyles.section),
          const SizedBox(height: 6),
          _BulletList(items: explanation.focusInsights),
        ],
        if (explanation.areas.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            explanation.isQuick
                ? 'Brief response indicators'
                : 'Well-being areas',
            style: _TextStyles.section,
          ),
          if (explanation.isQuick) ...[
            const SizedBox(height: 4),
            const Text(
              'Each indicator comes from one quick-check question. It is a prompt for reflection, not a complete category assessment.',
              style: _TextStyles.muted,
            ),
          ],
          const SizedBox(height: 8),
          for (final area in explanation.areas) _AreaRow(area: area),
        ],
        if (explanation.rationale.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('How this profile was formed', style: _TextStyles.section),
          const SizedBox(height: 6),
          _BulletList(items: explanation.rationale),
        ],
        if (explanation.suggestedActions.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Options you can try', style: _TextStyles.section),
          const SizedBox(height: 6),
          _BulletList(items: explanation.suggestedActions),
        ],
        const SizedBox(height: 14),
        const Text('Support options', style: _TextStyles.section),
        const SizedBox(height: 7),
        _StatusChip(label: explanation.followUpGuidance),
        const SizedBox(height: 6),
        const Text(
          'This guidance considers response coverage and possible day-to-day effects. Counseling is an optional, confidential source of support and this profile is not a diagnosis.',
          style: _TextStyles.muted,
        ),
      ],
    ),
  );

  static String _metadata(AssessmentExplanationModel value) {
    final parts = <String>[];
    final date = value.completedAt;
    if (date != null) {
      parts.add('${_month(date.month)} ${date.day}, ${date.year}');
    }
    parts.add('Past ${value.recallPeriodDays} days');
    if (value.presentedCount > 0) {
      parts.add('${value.answeredCount}/${value.presentedCount} answered');
    }
    if (value.responseConfidence.isNotEmpty) {
      parts.add(value.responseConfidence);
    }
    return parts.join('  •  ');
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({required this.area});
  final AssessmentAreaExplanation area;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(area.name, style: _TextStyles.bodyStrong)),
            const SizedBox(width: 8),
            Flexible(
              child: _StatusChip(label: area.patternLabel, compact: true),
            ),
          ],
        ),
        if (area.explanation.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(area.explanation, style: _TextStyles.muted),
        ],
        if (area.suggestedAction.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Option to try: ${area.suggestedAction}',
            style: _TextStyles.muted,
          ),
        ],
      ],
    ),
  );
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: _TextStyles.body),
              Expanded(child: Text(item, style: _TextStyles.body)),
            ],
          ),
        ),
    ],
  );
}

class _HistoryNote extends StatelessWidget {
  const _HistoryNote({required this.assessmentCount});
  final int assessmentCount;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Row(
      children: [
        const Icon(Icons.history_rounded, color: Color(0xFF9A6700)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$assessmentCount assessment${assessmentCount == 1 ? '' : 's'} completed this week. Each card shows the latest available result for that assessment type, which may be from a different date. Authorized staff can review the complete history.',
            style: _TextStyles.body,
          ),
        ),
      ],
    ),
  );
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => const _Panel(
    color: Color(0xFFFFF8E5),
    child: Text(
      'These response patterns support self-reflection. They do not label you, provide a diagnosis, or replace evaluation by a qualified professional. Seek urgent local help if you may be in immediate danger.',
      style: _TextStyles.body,
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.compact = false});
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    final Color color;
    if (normalized.contains('high') ||
        normalized.contains('prompt') ||
        normalized.contains('at risk') ||
        normalized.contains('stronger support') ||
        normalized.contains('support may be useful') ||
        normalized.contains('timely support')) {
      color = const Color(0xFFB3261E);
    } else if (normalized.contains('elevated') ||
        normalized.contains('moderate') ||
        normalized.contains('watch') ||
        normalized.contains('follow') ||
        normalized.contains('some strain') ||
        normalized.contains('areas to strengthen') ||
        normalized.contains('additional support') ||
        normalized.contains('needs improvement')) {
      color = const Color(0xFF8A6500);
    } else {
      color = const Color(0xFF2E7D57);
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0x1F000000)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 10,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({this.message, this.child});
  final String? message;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      SizedBox(
        height: MediaQuery.sizeOf(context).height * .58,
        child: Center(
          child:
              child ??
              Text(
                message ?? '',
                textAlign: TextAlign.center,
                style: _TextStyles.body,
              ),
        ),
      ),
    ],
  );
}

String _readable(String value) {
  final spaced = value
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .trim();
  if (spaced.isEmpty) return 'Result available';
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String _month(int month) => const [
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
][month - 1];

class _TextStyles {
  const _TextStyles._();
  static const heading = TextStyle(
    color: Colors.black,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w900,
  );
  static const bodyStrong = TextStyle(
    color: Colors.black,
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );
  static const muted = TextStyle(
    color: Color(0xFF625F58),
    fontSize: 13,
    height: 1.4,
  );
  static const section = TextStyle(
    color: Colors.black,
    fontSize: 14,
    fontWeight: FontWeight.w900,
  );
  static const body = TextStyle(
    color: Color(0xFF514A40),
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );
}
