import 'package:flutter/material.dart';

import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';
import '../theme/admin_theme.dart';

/// Read-only view of the signed-in counselor's assigned colleges.
class CounselorAssignedCollegesPage extends StatefulWidget {
  const CounselorAssignedCollegesPage({super.key, required this.repository});

  final AdminPortalRepository repository;

  @override
  State<CounselorAssignedCollegesPage> createState() =>
      _CounselorAssignedCollegesPageState();
}

class _CounselorAssignedCollegesPageState
    extends State<CounselorAssignedCollegesPage> {
  Stream<Map<String, dynamic>?>? _profileStream;
  Stream<List<College>>? _collegesStream;

  bool get _isAuthorized {
    final uid = widget.repository.currentUserId?.trim() ?? '';
    return widget.repository.currentAccessRole == AccessRole.counselor &&
        !widget.repository.isSuperAdmin &&
        uid.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(covariant CounselorAssignedCollegesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _initStreams();
    }
  }

  void _initStreams() {
    if (!_isAuthorized) {
      _profileStream = null;
      _collegesStream = null;
      return;
    }
    final uid = widget.repository.currentUserId!.trim();
    _profileStream = widget.repository.watchOwnProfile(uid);
    _collegesStream = widget.repository.watchColleges();
  }

  void _retry() {
    setState(_initStreams);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized || _profileStream == null || _collegesStream == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Assigned colleges are available only to signed-in counselors.',
          ),
        ),
      );
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _profileStream,
      builder: (context, profileSnapshot) {
        return StreamBuilder<List<College>>(
          stream: _collegesStream,
          builder: (context, collegesSnapshot) {
            if (profileSnapshot.hasError || collegesSnapshot.hasError) {
              return _ErrorView(onRetry: _retry);
            }
            if (!profileSnapshot.hasData || !collegesSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final profile = profileSnapshot.data;
            final accountStatus = profile?['accountStatus']?.toString().trim();
            final staffStatus = profile?['staffAccountStatus']
                ?.toString()
                .trim();
            final isRestricted =
                profile == null ||
                (accountStatus != null &&
                    accountStatus.isNotEmpty &&
                    accountStatus != 'active') ||
                (staffStatus != null &&
                    staffStatus.isNotEmpty &&
                    staffStatus != 'approved');

            final rawIds = profile?['assignedCollegeIds'];
            final assignedIds = (!isRestricted && rawIds is List)
                ? (rawIds
                      .whereType<String>()
                      .map((id) => id.trim())
                      .where((id) => id.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort())
                : <String>[];

            final byId = <String, College>{
              for (final college in collegesSnapshot.data!) college.id: college,
            };

            final entries =
                assignedIds
                    .map((id) => _AssignedCollegeEntry(id: id, college: byId[id]))
                    .toList()
                  ..sort((a, b) => a.sortLabel.compareTo(b.sortLabel));

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Assigned Colleges',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Read-only overview of the colleges assigned to your counselor caseload.',
                        style: TextStyle(color: AdminColors.muted),
                      ),
                      const SizedBox(height: 20),
                      if (isRestricted)
                        _NoticeCard(
                          title: 'Account access restricted',
                          message:
                              'Your counselor profile is not currently active for college-scoped caseload access. Contact your administrator for assistance.',
                        )
                      else if (entries.isEmpty)
                        const _NoticeCard(
                          title: 'No colleges assigned yet',
                          message:
                              'You do not currently have any assigned colleges. Contact your administrator if you need college caseload access.',
                        )
                      else ...[
                        _SummaryBanner(entries: entries),
                        const SizedBox(height: 16),
                        for (final entry in entries)
                          _AssignedCollegeCard(entry: entry),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AssignedCollegeEntry {
  const _AssignedCollegeEntry({required this.id, required this.college});

  final String id;
  final College? college;

  bool get isKnown => college != null;
  bool get isActive => college?.active == true;
  String get sortLabel =>
      college != null ? college!.name.toLowerCase() : '~$id';
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.entries});

  final List<_AssignedCollegeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final activeCount = entries.where((e) => e.isKnown && e.isActive).length;
    final attentionCount = entries.length - activeCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${entries.length} assigned ${entries.length == 1 ? 'college' : 'colleges'}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          _StatusPill(
            label: '$activeCount Active',
            backgroundColor: AdminColors.accentSoft,
          ),
          if (attentionCount > 0)
            _StatusPill(
              label: '$attentionCount Inactive or Unavailable',
              backgroundColor: AdminColors.surfaceMuted,
            ),
        ],
      ),
    );
  }
}

class _AssignedCollegeCard extends StatelessWidget {
  const _AssignedCollegeCard({required this.entry});

  final _AssignedCollegeEntry entry;

  @override
  Widget build(BuildContext context) {
    final college = entry.college;
    final title = college != null
        ? college.name
        : 'Unknown or unavailable college';
    final statusLabel = college == null
        ? 'Unavailable / Unknown'
        : college.active
        ? 'Active'
        : 'Inactive / Archived';
    final statusColor = college != null && college.active
        ? AdminColors.accentSoft
        : AdminColors.surfaceMuted;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              if (college != null && college.code.isNotEmpty)
                Text(
                  'Code ${college.code}',
                  style: const TextStyle(color: AdminColors.muted),
                )
              else if (college == null)
                const Text(
                  'Catalog entry not found. Contact your administrator to verify this assignment.',
                  style: TextStyle(color: AdminColors.muted),
                ),
              if (college != null && !college.active) ...[
                const SizedBox(height: 4),
                const Text(
                  'This college is archived in the academic catalog.',
                  style: TextStyle(color: AdminColors.muted, fontSize: 12),
                ),
              ],
            ],
          );

          final badge = _StatusPill(
            label: statusLabel,
            backgroundColor: statusColor,
          );

          if (constraints.maxWidth < 540) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 10), badge],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              badge,
            ],
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.backgroundColor});

  final String label;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AdminColors.border),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(message, style: const TextStyle(color: AdminColors.muted)),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('We could not load your assigned colleges.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
