import 'package:flutter/material.dart';

import '../../../models/profile_roles.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';
import '../screens/profile_management_page.dart';
import '../theme/admin_theme.dart';

enum AppDirectoryGroup { students, employees }

bool matchesAppDirectoryGroup(UserModel user, AppDirectoryGroup group) {
  if (!user.isAppUser) return false;
  final role = user.effectivePopulationRole;
  return group == AppDirectoryGroup.students
      ? role == PopulationRole.student
      : role == PopulationRole.teaching || role == PopulationRole.nonTeaching;
}

String appDirectoryStatus(UserModel user) {
  final status = (user.accountStatus ?? '').trim().toLowerCase();
  if (status == 'disabled' || status == 'suspended' || status == 'inactive') {
    return 'Suspended';
  }
  if (status == 'rejected' || status == 'closed') return 'Closed';
  return switch (user.verificationStatus) {
    VerificationStatus.verified => 'Active',
    VerificationStatus.rejected => 'Verification rejected',
    VerificationStatus.needsReview => 'Needs review',
    VerificationStatus.pending => 'Pending verification',
  };
}

/// This component must only be used inside the super-admin User Management flow.
/// Identifiers are obtained from the existing authorized watchUsers() stream.
class AppUserDirectoryTable extends StatefulWidget {
  const AppUserDirectoryTable({
    super.key,
    required this.repository,
    required this.profiles,
    required this.group,
    required this.query,
  });
  final AdminPortalRepository repository;
  final List<UserModel> profiles;
  final AppDirectoryGroup group;
  final String query;

  @override
  State<AppUserDirectoryTable> createState() => _AppUserDirectoryTableState();
}

class _AppUserDirectoryTableState extends State<AppUserDirectoryTable> {
  late Stream<List<College>> _colleges;
  String _collegeId = 'all';

  @override
  void initState() {
    super.initState();
    _colleges = widget.repository.watchColleges();
  }

  @override
  void didUpdateWidget(covariant AppUserDirectoryTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _colleges = widget.repository.watchColleges();
    }
    if (oldWidget.group != widget.group) _collegeId = 'all';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isSuperAdmin) {
      return const Text('Super-administrator access is required.');
    }
    return StreamBuilder<List<College>>(
      stream: _colleges,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Unable to load colleges.');
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final colleges = snapshot.data!;
        final names = {
          for (final college in colleges) college.id: college.name,
        };
        final availableIds = colleges.map((c) => c.id).toSet();
        final selected =
            _collegeId == 'all' ||
                _collegeId == 'unassigned' ||
                availableIds.contains(_collegeId)
            ? _collegeId
            : 'all';
        final query = widget.query.trim().toLowerCase();
        final profiles =
            widget.profiles
                .where((user) => matchesAppDirectoryGroup(user, widget.group))
                .where((user) {
                  if (selected == 'unassigned') {
                    if ((user.collegeId ?? '').trim().isNotEmpty) return false;
                  } else if (selected != 'all' && user.collegeId != selected) {
                    return false;
                  }
                  if (query.isEmpty) return true;
                  return user.displayName.toLowerCase().contains(query) ||
                      (user.schoolId ?? '').toLowerCase().contains(query) ||
                      (user.employeeId ?? '').toLowerCase().contains(query);
                })
                .toList()
              ..sort((a, b) => a.displayName.compareTo(b.displayName));
        final employees = widget.group == AppDirectoryGroup.employees;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Names and IDs are visible only to the authorized super-administrator.',
              style: TextStyle(color: AdminColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('college-filter-$selected'),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'College'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All colleges'),
                      ),
                      ...colleges.map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ),
                      const DropdownMenuItem(
                        value: 'unassigned',
                        child: Text('Unassigned college'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _collegeId = value);
                    },
                  ),
                ),
                Text(
                  '${profiles.length} ${employees ? 'employees' : 'students'}',
                  style: const TextStyle(color: AdminColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (profiles.isEmpty)
              Text(employees ? 'No employees found.' : 'No students found.')
            else
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      columns: employees
                          ? const [
                              DataColumn(label: Text('Employee ID')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('College')),
                              DataColumn(
                                label: Text('Teaching or non-teaching'),
                              ),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Action')),
                            ]
                          : const [
                              DataColumn(label: Text('Student ID')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('College')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Action')),
                            ],
                      rows: profiles.map((user) {
                        final id = employees ? user.employeeId : user.schoolId;
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                id == null || id.trim().isEmpty
                                    ? 'Not provided'
                                    : id.trim(),
                              ),
                            ),
                            DataCell(Text(user.displayName)),
                            DataCell(
                              Text(names[user.collegeId] ?? 'Unassigned'),
                            ),
                            if (employees)
                              DataCell(
                                Text(user.effectivePopulationRole!.label),
                              ),
                            DataCell(Text(appDirectoryStatus(user))),
                            DataCell(
                              OutlinedButton.icon(
                                onPressed: () =>
                                    showManagedUserProfile(context, user),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 17,
                                ),
                                label: const Text('View user'),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
