import 'package:flutter/material.dart';

import '../../../models/admin_status_summary_model.dart';
import '../../../repositories/admin_status_repository.dart';
import 'admin_assessment_detail_screen.dart';
import '../theme/admin_theme.dart';

class AdminStatusDashboardScreen extends StatelessWidget {
  const AdminStatusDashboardScreen({
    super.key,
    this.repository,
    this.embedded = false,
  });

  final AdminStatusRepository? repository;
  final bool embedded;

  AdminStatusRepository get _effectiveRepository =>
      repository ?? AdminStatusRepository();

  @override
  Widget build(BuildContext context) {
    final content = StreamBuilder<List<AdminStatusSummaryModel>>(
      stream: _effectiveRepository.watchUserStatuses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MessagePanel(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load statuses',
            message: 'Check the admin status Firestore rules and try again.',
          );
        }

        final statuses = snapshot.data ?? const <AdminStatusSummaryModel>[];
        if (statuses.isEmpty) {
          return const _MessagePanel(
            icon: Icons.monitor_heart_outlined,
            title: 'No statuses yet',
            message:
                'User statuses will appear here after app activity generates mental health summaries.',
          );
        }

        return _DashboardContent(
          statuses: statuses,
          repository: _effectiveRepository,
          showHeading: embedded,
        );
      },
    );
    if (embedded) return content;
    return Scaffold(
      backgroundColor: AdminColors.canvas,
      appBar: AppBar(
        title: const Text('Admin User Status'),
        backgroundColor: AdminColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: content,
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.statuses,
    required this.repository,
    required this.showHeading,
  });

  final List<AdminStatusSummaryModel> statuses;
  final AdminStatusRepository repository;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final severeCount = _count(AdminUserStatus.severe);
    final moderateCount = _count(AdminUserStatus.moderate);
    final normalCount = _count(AdminUserStatus.normal);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth < 600 ? 16 : 28,
            28,
            constraints.maxWidth < 600 ? 16 : 28,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showHeading) ...[
                    Text(
                      'Admin Status',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Review well-being signals and prioritize follow-up',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                  ],
                  LayoutBuilder(
                    builder: (context, tileBox) {
                      final columns = tileBox.maxWidth >= 840
                          ? 3
                          : tileBox.maxWidth >= 500
                          ? 2
                          : 1;
                      final width =
                          (tileBox.maxWidth - ((columns - 1) * 12)) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _StatusSummaryTile(
                            width: width,
                            label: 'Prompt follow-up',
                            count: severeCount,
                            color: const Color(0xFFB3261E),
                          ),
                          _StatusSummaryTile(
                            width: width,
                            label: 'Review suggested',
                            count: moderateCount,
                            color: const Color(0xFFB06A00),
                          ),
                          _StatusSummaryTile(
                            width: width,
                            label: 'Routine monitoring',
                            count: normalCount,
                            color: AdminColors.accentStrong,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _StatusTable(statuses: statuses, repository: repository),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _count(AdminUserStatus status) {
    return statuses.where((item) => item.status == status).length;
  }
}

class _StatusSummaryTile extends StatelessWidget {
  const _StatusSummaryTile({
    required this.width,
    required this.label,
    required this.count,
    required this.color,
  });

  final double width;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AdminColors.ink,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _StatusTable extends StatelessWidget {
  const _StatusTable({required this.statuses, required this.repository});

  final List<AdminStatusSummaryModel> statuses;
  final AdminStatusRepository repository;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F6F4)),
            columnSpacing: 28,
            columns: const [
              DataColumn(label: Text('User')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Engagement')),
              DataColumn(label: Text('Assessment')),
              DataColumn(label: Text('Secret Chat')),
              DataColumn(label: Text('Updated')),
            ],
            rows: [
              for (final item in statuses)
                DataRow(
                  onSelectChanged: (_) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminAssessmentDetailScreen(
                        userId: item.userId,
                        userLabel: item.userLabel,
                        repository: repository,
                      ),
                    ),
                  ),
                  cells: [
                    DataCell(Text(item.userLabel)),
                    DataCell(_StatusBadge(status: item.status)),
                    DataCell(Text(item.role ?? '-')),
                    DataCell(Text('${item.totalActivityCount}')),
                    DataCell(Text(_assessmentText(item))),
                    DataCell(Text('${item.secretChatEngagementCount}')),
                    DataCell(Text(_formatDate(item.updatedAt))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _assessmentText(AdminStatusSummaryModel item) {
    final full = item.fullAssessmentStatus;
    if (full != null && full.isNotEmpty) return full;
    final quick = item.quickAssessmentStatus;
    if (quick != null && quick.isNotEmpty) return quick;
    return item.latestAssessmentStatus ?? '-';
  }

  static String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final AdminUserStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AdminUserStatus.severe => const Color(0xFFB3261E),
      AdminUserStatus.moderate => const Color(0xFFB06A00),
      AdminUserStatus.normal => AdminColors.accentStrong,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AdminColors.accentStrong, size: 38),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminColors.muted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
