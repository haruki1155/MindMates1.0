import 'package:flutter/material.dart';

import '../../../models/profile_roles.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';
import '../theme/admin_theme.dart';
import '../widgets/college_assignment_dialog.dart';

enum _AssignmentFilter { all, assigned, unassigned, conflicts }

/// Super-administrator overview of counselor-to-college assignments.
class AdminCollegeAssignmentsPage extends StatefulWidget {
  const AdminCollegeAssignmentsPage({super.key, required this.repository});

  final AdminPortalRepository repository;

  @override
  State<AdminCollegeAssignmentsPage> createState() =>
      _AdminCollegeAssignmentsPageState();
}

class _AdminCollegeAssignmentsPageState
    extends State<AdminCollegeAssignmentsPage> {
  Stream<List<College>>? _collegesStream;
  Stream<List<UserModel>>? _usersStream;
  _AssignmentFilter _filter = _AssignmentFilter.all;
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(covariant AdminCollegeAssignmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _initStreams();
    }
  }

  void _initStreams() {
    if (!widget.repository.isSuperAdmin) {
      _collegesStream = null;
      _usersStream = null;
      return;
    }
    _collegesStream = widget.repository.watchColleges();
    _usersStream = widget.repository.watchUsers();
  }

  void _retry() {
    setState(_initStreams);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _statusFor(College college, List<UserModel> owners) {
    if (owners.length > 1) return 'Assignment conflict';
    if (owners.length == 1) return 'Assigned';
    return college.active ? 'Unassigned' : 'Archived';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isSuperAdmin ||
        _collegesStream == null ||
        _usersStream == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Super-administrator access is required.'),
        ),
      );
    }

    return StreamBuilder<List<College>>(
      stream: _collegesStream,
      builder: (context, collegesSnapshot) {
        return StreamBuilder<List<UserModel>>(
          stream: _usersStream,
          builder: (context, usersSnapshot) {
            if (collegesSnapshot.hasError || usersSnapshot.hasError) {
              return _ErrorView(onRetry: _retry);
            }
            if (!collegesSnapshot.hasData || !usersSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final colleges = [...collegesSnapshot.data!]
              ..sort((a, b) => a.name.compareTo(b.name));
            final users = usersSnapshot.data!;
            final eligibleCounselors =
                users.where(isEligibleCounselorAccount).toList()
                  ..sort((a, b) => a.displayName.compareTo(b.displayName));

            final ownersByCollege = <String, List<UserModel>>{};
            for (final user in users) {
              if (user.accessRole != AccessRole.counselor ||
                  user.assignedCollegeIds.isEmpty) {
                continue;
              }
              for (final cid in user.assignedCollegeIds.toSet()) {
                (ownersByCollege[cid] ??= <UserModel>[]).add(user);
              }
            }
            for (final owners in ownersByCollege.values) {
              owners.sort((a, b) => a.displayName.compareTo(b.displayName));
            }

            final catalogIds = colleges.map((c) => c.id).toSet();
            final unknownAssignedIds =
                ownersByCollege.keys
                    .where((id) => !catalogIds.contains(id))
                    .toList()
                  ..sort();

            var assignedCount = 0;
            var unassignedCount = 0;
            var conflictCount = 0;
            for (final college in colleges) {
              final owners = ownersByCollege[college.id] ?? const [];
              if (owners.length > 1) {
                conflictCount += 1;
              } else if (owners.length == 1) {
                assignedCount += 1;
              } else if (college.active) {
                unassignedCount += 1;
              }
            }

            final filtered = colleges.where((college) {
              final owners = ownersByCollege[college.id] ?? const [];
              final status = _statusFor(college, owners);
              final matchesFilter = switch (_filter) {
                _AssignmentFilter.all => true,
                _AssignmentFilter.assigned => status == 'Assigned',
                _AssignmentFilter.unassigned => status == 'Unassigned',
                _AssignmentFilter.conflicts => status == 'Assignment conflict',
              };
              if (!matchesFilter) return false;
              if (_search.isEmpty) return true;
              final ownerMatch = owners.any(
                (o) => o.displayName.toLowerCase().contains(_search),
              );
              return college.name.toLowerCase().contains(_search) ||
                  college.code.toLowerCase().contains(_search) ||
                  ownerMatch;
            }).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'College Assignments',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Manage counselor ownership across colleges. Changes use the authorized assignment and transfer workflow.',
                        style: TextStyle(color: AdminColors.muted),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _Badge(
                            label: '$assignedCount Assigned',
                            backgroundColor: AdminColors.accentSoft,
                          ),
                          _Badge(label: '$unassignedCount Unassigned'),
                          if (conflictCount > 0)
                            _Badge(
                              label: '$conflictCount Conflicts',
                              backgroundColor: Colors.red.withValues(
                                alpha: 0.14,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 300,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (value) => setState(
                                () => _search = value.trim().toLowerCase(),
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                prefixIcon: const Icon(Icons.search, size: 18),
                                hintText: 'Search college or counselor',
                                suffixIcon: _search.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _search = '');
                                        },
                                        icon: const Icon(Icons.close, size: 16),
                                      ),
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final option in const [
                                (_AssignmentFilter.all, 'All Colleges'),
                                (_AssignmentFilter.assigned, 'Assigned'),
                                (_AssignmentFilter.unassigned, 'Unassigned'),
                                (_AssignmentFilter.conflicts, 'Conflicts'),
                              ])
                                ChoiceChip(
                                  label: Text(option.$2),
                                  selected: _filter == option.$1,
                                  onSelected: (_) =>
                                      setState(() => _filter = option.$1),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (unknownAssignedIds.isNotEmpty) ...[
                        _UnknownAssignmentsCard(
                          unknownIds: unknownAssignedIds,
                          ownersByCollege: ownersByCollege,
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (filtered.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AdminColors.surface,
                            border: Border.all(color: AdminColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'No colleges match the selected filter.',
                            style: TextStyle(color: AdminColors.muted),
                          ),
                        )
                      else
                        for (final college in filtered)
                          _CollegeOverviewRow(
                            college: college,
                            owners: ownersByCollege[college.id] ?? const [],
                            status: _statusFor(
                              college,
                              ownersByCollege[college.id] ?? const [],
                            ),
                            eligibleCounselors: eligibleCounselors,
                            repository: widget.repository,
                          ),
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

class _CollegeOverviewRow extends StatelessWidget {
  const _CollegeOverviewRow({
    required this.college,
    required this.owners,
    required this.status,
    required this.eligibleCounselors,
    required this.repository,
  });

  final College college;
  final List<UserModel> owners;
  final String status;
  final List<UserModel> eligibleCounselors;
  final AdminPortalRepository repository;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (status) {
      'Assigned' => AdminColors.accentSoft,
      'Assignment conflict' => Colors.red.withValues(alpha: 0.14),
      'Archived' => AdminColors.surfaceMuted,
      _ => AdminColors.canvas,
    };

    Future<void> openTransfer({bool readOnly = false}) =>
        showCollegeCounselorTransferDialog(
          context,
          repository: repository,
          college: college,
          currentOwners: owners,
          eligibleCounselors: eligibleCounselors,
          readOnly: readOnly,
        );

    final ownerLabels = owners.isEmpty
        ? 'Unassigned'
        : owners
              .map(
                (owner) => isEligibleCounselorAccount(owner)
                    ? owner.displayName
                    : '${owner.displayName} (Inactive)',
              )
              .join(', ');

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              college.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            if (college.code.isNotEmpty) _Badge(label: 'Code ${college.code}'),
            if (!college.active)
              const _Badge(
                label: 'Archived',
                backgroundColor: AdminColors.surfaceMuted,
              ),
            _Badge(label: status, backgroundColor: statusColor),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Assigned counselor: $ownerLabels',
          style: const TextStyle(fontSize: 13),
        ),
        if (owners.length > 1)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Multiple counselors are assigned to this college. Resolve the conflict through transfer.',
              style: TextStyle(color: AdminColors.danger, fontSize: 12),
            ),
          )
        else if (!college.active && owners.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'College archived — existing counselor assignment can be reviewed or released.',
              style: TextStyle(color: AdminColors.muted, fontSize: 12),
            ),
          ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (status == 'Assignment conflict')
          FilledButton(
            onPressed: () => openTransfer(),
            child: const Text('Resolve Conflict'),
          )
        else if (status == 'Assigned') ...[
          OutlinedButton(
            onPressed: () => openTransfer(readOnly: true),
            child: const Text('View'),
          ),
          FilledButton.tonal(
            onPressed: () => openTransfer(),
            child: const Text('Manage'),
          ),
        ] else if (status == 'Unassigned')
          FilledButton.tonal(
            onPressed: () => openTransfer(),
            child: const Text('Assign'),
          )
        else
          OutlinedButton(
            onPressed: () => openTransfer(readOnly: true),
            child: const Text('View'),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _UnknownAssignmentsCard extends StatelessWidget {
  const _UnknownAssignmentsCard({
    required this.unknownIds,
    required this.ownersByCollege,
  });

  final List<String> unknownIds;
  final Map<String, List<UserModel>> ownersByCollege;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminColors.accentFaint,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Unknown catalog college references',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        for (final id in unknownIds)
          Text(
            'Unlisted college assignment: ${(ownersByCollege[id] ?? const []).map((u) => u.displayName).join(', ')}',
            style: const TextStyle(color: AdminColors.muted, fontSize: 13),
          ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.backgroundColor});

  final String label;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: backgroundColor ?? AdminColors.canvas,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AdminColors.border),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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
          const Text('We could not load college assignments.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
