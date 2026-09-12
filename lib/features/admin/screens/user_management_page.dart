import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/profile_roles.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';
import '../theme/admin_theme.dart';
import 'profile_management_page.dart';

enum UserManagementCategory { appUsers, staff, admin }

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key, required this.repository});
  final AdminPortalRepository repository;

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  UserManagementCategory category = UserManagementCategory.appUsers;
  String query = '';
  String staffRoleFilter = 'All roles';
  String staffStatusFilter = 'All account statuses';
  final Set<String> _updatingStaff = <String>{};
  final searchController = TextEditingController();
  late Future<List<PublicAppUserRecord>> publicUsers;
  int? publicUserCount;

  @override
  void initState() {
    super.initState();
    publicUsers = _loadPublicUsers();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isSuperAdmin) {
      return const Center(
        child: Text('Super-administrator access is required.'),
      );
    }
    return Material(
      color: Colors.transparent,
      child: StreamBuilder<List<UserModel>>(
        stream: widget.repository.watchUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load user management.'));
          }
          final all = snapshot.data ?? const <UserModel>[];
          final staff = all
              .where(
                (user) =>
                    user.staffAccountStatus != null &&
                    user.accessRole != AccessRole.admin,
              )
              .toList();
          final admins = all
              .where((user) => user.accessRole == AccessRole.admin)
              .toList();
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
              28,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
              40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final heading = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User Management',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Manage application accounts, staff access, and system roles.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    );
                    final directory = OutlinedButton.icon(
                      onPressed: _showOrganizationDirectory,
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Organization directory'),
                    );
                    if (box.maxWidth < 620) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          const SizedBox(height: 16),
                          directory,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 20),
                        directory,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _categoryButton(
                      UserManagementCategory.appUsers,
                      'App users  ${publicUserCount ?? '…'}',
                    ),
                    _categoryButton(
                      UserManagementCategory.staff,
                      'Staff / Counselors (${staff.length})',
                    ),
                    _categoryButton(
                      UserManagementCategory.admin,
                      'Admin  ${admins.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) =>
                        setState(() => query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: category == UserManagementCategory.appUsers
                          ? 'Search Student ID or Public User ID'
                          : 'Search name, email, or employee ID',
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                searchController.clear();
                                setState(() => query = '');
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (category == UserManagementCategory.staff) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _userFilter(
                        value: staffRoleFilter,
                        values: const [
                          'All roles',
                          'Portal Staff',
                          'Counselor',
                        ],
                        onChanged: (value) =>
                            setState(() => staffRoleFilter = value!),
                      ),
                      _userFilter(
                        value: staffStatusFilter,
                        values: const [
                          'All account statuses',
                          'Active',
                          'Suspended',
                          'Pending review',
                          'More information required',
                        ],
                        onChanged: (value) =>
                            setState(() => staffStatusFilter = value!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (category == UserManagementCategory.staff)
                  _staffTable(staff)
                else
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
                      ),
                      child: category == UserManagementCategory.appUsers
                          ? _appUsersTable(all)
                          : _adminProfiles(admins),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _categoryButton(UserManagementCategory value, String label) =>
      ChoiceChip(
        selected: category == value,
        label: Text(label),
        onSelected: (_) => setState(() {
          category = value;
          query = '';
          searchController.clear();
        }),
      );

  Widget _userFilter({
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) => SizedBox(
    width: 210,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Filter'),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    ),
  );

  Widget _appUsersTable(
    List<UserModel> allProfiles,
  ) => FutureBuilder<List<PublicAppUserRecord>>(
    future: publicUsers,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            const Text('Unable to load anonymous app users.'),
            FilledButton(
              onPressed: _refreshPublicUsers,
              child: const Text('Retry'),
            ),
          ],
        );
      }
      final profilesById = {for (final user in allProfiles) user.id: user};
      final users = (snapshot.data ?? const <PublicAppUserRecord>[]).where((
        user,
      ) {
        final profile = profilesById[user.userId];
        return query.isEmpty ||
            user.publicUserId.toLowerCase().contains(query) ||
            user.department.toLowerCase().contains(query) ||
            (profile?.displayName.toLowerCase().contains(query) ?? false);
      }).toList();
      if (users.isEmpty) return const Text('No app users found.');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: AdminColors.muted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'App-user records are visible only to the authorized administrator.',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 760) {
                return Column(
                  children: users
                      .map(
                        (user) => _CompactAppUserRow(
                          record: user,
                          profile: profilesById[user.userId],
                          onView: profilesById[user.userId] == null
                              ? null
                              : () => showManagedUserProfile(
                                  context,
                                  profilesById[user.userId]!,
                                ),
                        ),
                      )
                      .toList(),
                );
              }
              return SizedBox(
                width: double.infinity,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Public user ID')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Department')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Account created')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: users
                      .map(
                        (user) => DataRow(
                          cells: [
                            DataCell(
                              Text(
                                user.publicUserId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DataCell(Text(user.populationRole.label)),
                            DataCell(
                              Text(
                                user.department.isEmpty
                                    ? 'Not provided'
                                    : user.department,
                              ),
                            ),
                            const DataCell(Text('Active')),
                            DataCell(Text(_date(user.createdAt))),
                            DataCell(
                              OutlinedButton.icon(
                                onPressed: profilesById[user.userId] == null
                                    ? null
                                    : () => showManagedUserProfile(
                                        context,
                                        profilesById[user.userId]!,
                                      ),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 17,
                                ),
                                label: const Text('View user'),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ],
      );
    },
  );

  Widget _staffTable(List<UserModel> values) {
    final staff = values
        .where(
          (user) =>
              query.isEmpty ||
              user.displayName.toLowerCase().contains(query) ||
              user.email.toLowerCase().contains(query) ||
              (user.employeeId ?? '').toLowerCase().contains(query),
        )
        .where((user) {
          final role = user.accessRole == AccessRole.counselor
              ? 'Counselor'
              : 'Portal Staff';
          final accountStatus = _accountStatus(user);
          return (staffRoleFilter == 'All roles' || role == staffRoleFilter) &&
              (staffStatusFilter == 'All account statuses' ||
                  accountStatus == staffStatusFilter);
        })
        .toList();
    if (staff.isEmpty) return const Text('No staff accounts found.');
    return Column(
      children: staff
          .map(
            (user) =>
                _StaffRecordCard(user: user, actions: _staffActions(user)),
          )
          .toList(),
    );
  }

  List<Widget> _staffActions(UserModel user) {
    final status = user.staffAccountStatus;
    return [
      OutlinedButton.icon(
        onPressed: _updatingStaff.contains(user.id)
            ? null
            : () => _openManageDrawer(user),
        icon: _updatingStaff.contains(user.id)
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.tune_outlined, size: 17),
        label: const Text('Manage'),
      ),
      PopupMenuButton<String>(
        tooltip: 'More staff actions',
        onSelected: (action) => _handleStaffAction(user, action),
        itemBuilder: (_) => [
          if (status == StaffAccountStatus.pending)
            const PopupMenuItem(
              value: 'verify',
              child: Text('Review invitation'),
            ),
          if (status == StaffAccountStatus.pending)
            const PopupMenuItem(
              value: 'reject',
              child: Text('Remove invitation'),
            ),
          if (status == StaffAccountStatus.approved)
            const PopupMenuItem(
              value: 'suspend',
              child: Text('Suspend account'),
            ),
          if (status == StaffAccountStatus.disabled)
            const PopupMenuItem(
              value: 'enable',
              child: Text('Reactivate account'),
            ),
          const PopupMenuItem(value: 'history', child: Text('Activity Log')),
        ],
      ),
    ];
  }

  Future<void> _handleStaffAction(UserModel user, String action) async {
    switch (action) {
      case 'verify':
        await _verify(user);
      case 'reject':
        await _reject(user);
      case 'suspend':
        await _setEnabled(user, false);
      case 'enable':
        await _setEnabled(user, true);
      case 'history':
        await _openManageDrawer(user, historyOnly: true);
    }
  }

  Widget _adminProfiles(List<UserModel> admins) {
    if (admins.isEmpty) {
      return const Text('The configured administrator profile was not found.');
    }
    return Column(
      children: admins
          .map(
            (user) => Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    backgroundColor: AdminColors.accentSoft,
                    child: Icon(Icons.admin_panel_settings_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user.email,
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            const _UserBadge(
                              label: 'Protected administrator',
                              highlighted: true,
                            ),
                            if ((user.employeeId ?? '').isNotEmpty)
                              _UserBadge(label: user.employeeId!),
                            if ((user.position ?? '').isNotEmpty)
                              _UserBadge(label: user.position!),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _verify(UserModel user) async {
    try {
      await widget.repository.recordAuditEvent(
        action: 'STAFF_ACCESS_REQUEST_VIEWED',
        category: 'USER_MANAGEMENT',
        targetType: 'staff',
        targetId: user.id,
      );
    } catch (_) {
      // Reviewing a request remains available if audit delivery is temporarily unavailable.
    }
    var role = user.requestedRole == AccessRole.counselor
        ? AccessRole.counselor
        : AccessRole.portalStaff;
    final reason = TextEditingController();
    final decision = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text('Review access request — ${user.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${user.email}\nEmployee ID: ${user.employeeId ?? 'Not provided'}\nPosition: ${user.position ?? 'Not provided'}',
                  style: const TextStyle(color: AdminColors.muted, height: 1.45),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Requested role: ${_accessRoleLabel(user.requestedRole == AccessRole.counselor ? AccessRole.counselor : AccessRole.portalStaff)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PAACC Staff: appointments, schedules, inquiries, and limited administrative information.\nCounselor: authorized counseling profiles, assessment summaries, and counseling workflows.',
                  style: TextStyle(color: AdminColors.muted, fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<AccessRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'New role'),
                items: const [
                  DropdownMenuItem(
                    value: AccessRole.portalStaff,
                    child: Text('Portal Staff'),
                  ),
                  DropdownMenuItem(
                    value: AccessRole.counselor,
                    child: Text('Counselor'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => role = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Approval reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'more_information'),
              child: const Text('Request more information'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'approve'),
              child: const Text('Approve access'),
            ),
          ],
        ),
      ),
    );
    if (decision != null && reason.text.trim().length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter at least 3 characters in the review reason.'),
          ),
        );
      }
    } else if (decision != null) {
      setState(() => _updatingStaff.add(user.id));
      try {
        await widget.repository.reviewStaffRegistration(
          userId: user.id,
          approve: decision == 'approve',
          accessRole: role,
          reason: reason.text,
          decision: decision,
        );
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(
                decision == 'approve'
                    ? 'Access approved'
                    : 'More information requested',
              ),
              content: Text(
                decision == 'approve'
                    ? '${user.displayName} can now sign in with ${_accessRoleLabel(role)} access.'
                    : '${user.displayName} remains pending until the requested information is provided.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_friendlyAdminError(error))));
        }
      } finally {
        if (mounted) setState(() => _updatingStaff.remove(user.id));
      }
    }
    reason.dispose();
  }

  String _friendlyAdminError(Object error) {
    if (error is FirebaseFunctionsException) {
      return switch (error.code) {
        'failed-precondition' =>
          'This request is no longer pending. Refresh the list and try again.',
        'permission-denied' =>
          'You do not have permission to review this request.',
        'invalid-argument' =>
          'Check the selected role and review reason, then try again.',
        'not-found' => 'The staff request could not be found.',
        _ => 'The request could not be updated. Please try again.',
      };
    }
    return 'The request could not be updated. Please try again.';
  }

  Future<void> _reject(UserModel user) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reject ${user.displayName}'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Rejection reason'),
        ),
        actions: _confirmActions(dialogContext, 'Reject'),
      ),
    );
    if (confirmed == true && reason.text.trim().length >= 3) {
      await widget.repository.reviewStaffRegistration(
        userId: user.id,
        approve: false,
        accessRole: AccessRole.portalStaff,
        reason: reason.text,
      );
    }
    reason.dispose();
  }

  // Kept as a compatibility entry point for callers from older admin builds.
  // ignore: unused_element
  Future<void> _review(UserModel user) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Staff registration — ${user.displayName}'),
      content: SizedBox(
        width: 620,
        child: ListView(
          shrinkWrap: true,
          children: [
            _detail('Email', user.email),
            _detail('Employee ID', user.employeeId),
            _detail('Position', user.position),
            _detail('Department', user.department ?? user.departmentId),
            _detail('College', user.collegeId),
            _detail('Course', user.courseId),
            _detail('Account status', user.staffAccountStatus?.label),
            _detail('Portal role', user.accessRole.storedValue),
            _detail('Registered', _date(user.createdAt)),
            _detail('Verified', _date(user.verifiedAt)),
            const Divider(),
            const Text(
              'Audit history',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            StreamBuilder<List<AdminAuditEvent>>(
              stream: widget.repository.watchAdminAudit(user.id),
              builder: (_, snapshot) => Column(
                children: (snapshot.data ?? const [])
                    .map(
                      (event) => ListTile(
                        dense: true,
                        title: Text(event.action),
                        subtitle: Text(event.reason),
                        trailing: Text(_date(event.createdAt)),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _openManageDrawer(
    UserModel user, {
    bool historyOnly = false,
  }) => showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close manage access',
    pageBuilder: (context, animation, secondaryAnimation) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width < 560
              ? MediaQuery.sizeOf(context).width
              : 500,
          height: double.infinity,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          historyOnly ? 'Activity Log' : 'Manage access',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AdminColors.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user.email,
                          style: const TextStyle(color: AdminColors.muted),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          children: [
                            _UserBadge(
                              label: _accessRoleLabel(user.accessRole),
                              highlighted: true,
                            ),
                            _UserBadge(label: _accountStatus(user)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!historyOnly) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _detail(
                            'Role',
                            _accessRoleLabel(user.accessRole),
                          ),
                        ),
                        Expanded(
                          child: _detail(
                            'Account status',
                            _accountStatus(user),
                          ),
                        ),
                      ],
                    ),
                    _detail('Last sign-in', _date(user.lastActiveAt)),
                    _detail('Department', user.department ?? user.departmentId),
                    const SizedBox(height: 10),
                    const Text(
                      'Available permissions',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    ..._rolePermissions(
                      user.accessRole == AccessRole.counselor
                          ? AccessRole.counselor
                          : AccessRole.portalStaff,
                    ).map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check,
                              size: 16,
                              color: AdminColors.success,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item)),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 26),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (user.staffAccountStatus ==
                            StaffAccountStatus.approved)
                          OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _changeRole(user);
                            },
                            icon: const Icon(Icons.manage_accounts_outlined),
                            label: const Text('Change role'),
                          ),
                        if (user.staffAccountStatus ==
                            StaffAccountStatus.approved)
                          OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _setEnabled(user, false);
                            },
                            icon: const Icon(Icons.pause_circle_outline),
                            label: const Text('Suspend'),
                          ),
                        if (user.staffAccountStatus ==
                            StaffAccountStatus.disabled)
                          FilledButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _setEnabled(user, true);
                            },
                            icon: const Icon(Icons.play_circle_outline),
                            label: const Text('Reactivate'),
                          ),
                        if (user.staffAccountStatus ==
                            StaffAccountStatus.pending)
                          FilledButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _verify(user);
                            },
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('Review invitation'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Access and activity history',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: _ActivityLogView(
                      repository: widget.repository,
                      user: user,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _detail(String label, String? value) => ListTile(
    dense: true,
    title: Text(label),
    trailing: Text((value ?? '').isEmpty ? '—' : value!),
  );

  Future<void> _changeRole(UserModel user) async {
    var role = user.accessRole == AccessRole.counselor
        ? AccessRole.counselor
        : AccessRole.portalStaff;
    final reason = TextEditingController();
    String? reasonError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text('Change account role — ${user.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current role: ${user.accessRole == AccessRole.counselor ? 'Counselor' : 'Portal Staff'}',
                style: const TextStyle(color: AdminColors.muted),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccessRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'New role'),
                items: const [
                  DropdownMenuItem(
                    value: AccessRole.portalStaff,
                    child: Text('Portal Staff'),
                  ),
                  DropdownMenuItem(
                    value: AccessRole.counselor,
                    child: Text('Counselor'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => role = v);
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'This role will allow the user to:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ..._rolePermissions(role).map(
                (permission) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(permission)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                decoration: InputDecoration(
                  labelText: 'Reason for change',
                  helperText: 'This reason is recorded in the audit log.',
                  errorText: reasonError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length < 3) {
                  setDialogState(
                    () => reasonError = 'Enter at least 3 characters.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Change role'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && reason.text.trim().length >= 3) {
      await widget.repository.assignAccessRole(
        userId: user.id,
        accessRole: role,
        reason: reason.text,
      );
    }
    reason.dispose();
  }

  List<String> _rolePermissions(AccessRole role) => role == AccessRole.counselor
      ? const [
          'Access counseling appointments',
          'Manage assigned schedules',
          'View authorized counseling profiles',
          'Respond to inquiries',
        ]
      : const [
          'Access appointments and scheduling',
          'View limited staff operations',
          'No access to counseling reports or profiles',
        ];

  Future<void> _setEnabled(UserModel user, bool enabled) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${enabled ? 'Enable' : 'Disable'} ${user.displayName}'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: _confirmActions(dialogContext, enabled ? 'Enable' : 'Disable'),
      ),
    );
    if (confirmed == true && reason.text.trim().length >= 3) {
      setState(() => _updatingStaff.add(user.id));
      try {
        await widget.repository.setStaffAccountEnabled(
          userId: user.id,
          enabled: enabled,
          reason: reason.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${user.displayName} is now ${enabled ? 'active' : 'suspended'}.',
              ),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The account status could not be updated. Please try again.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _updatingStaff.remove(user.id));
      }
    }
    reason.dispose();
  }

  List<Widget> _confirmActions(BuildContext context, String action) => [
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: const Text('Cancel'),
    ),
    FilledButton(
      onPressed: () => Navigator.pop(context, true),
      child: Text(action),
    ),
  ];

  Future<void> _refreshPublicUsers() async {
    setState(() => publicUsers = _loadPublicUsers());
  }

  Future<List<PublicAppUserRecord>> _loadPublicUsers() async {
    final users = await widget.repository.listPublicAppUsers();
    if (mounted) setState(() => publicUserCount = users.length);
    return users;
  }

  Future<void> _showOrganizationDirectory() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Organization Directory'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _organizationList<College>(
                'college',
                'Colleges',
                widget.repository.watchColleges(),
              ),
              _organizationList<Department>(
                'department',
                'Departments',
                widget.repository.watchDepartments(),
              ),
              _organizationList<Course>(
                'course',
                'Courses',
                widget.repository.watchCourses(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _organizationList<T extends OrganizationRecord>(
    String kind,
    String title,
    Stream<List<T>> stream,
  ) => StreamBuilder<List<T>>(
    stream: stream,
    builder: (_, snapshot) => ExpansionTile(
      title: Text('$title (${snapshot.data?.length ?? 0})'),
      trailing: IconButton(
        tooltip: 'Add $title',
        onPressed: () => _editOrganization(kind),
        icon: const Icon(Icons.add),
      ),
      children: (snapshot.data ?? <T>[])
          .map(
            (record) => ListTile(
              title: Text(record.name),
              subtitle: Text(record.code),
              trailing: Icon(
                record.active ? Icons.check_circle : Icons.pause_circle,
              ),
              onTap: () => _editOrganization(kind, record: record),
            ),
          )
          .toList(),
    ),
  );

  Future<void> _editOrganization(
    String kind, {
    OrganizationRecord? record,
  }) async {
    final name = TextEditingController(text: record?.name);
    final code = TextEditingController(text: record?.code);
    final colleges = kind == 'course'
        ? await widget.repository.watchColleges().first
        : const <College>[];
    String? collegeId = record is Course ? record.collegeId : null;
    var active = record?.active ?? true;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text('${record == null ? 'Add' : 'Edit'} $kind'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              if (kind == 'course')
                DropdownButtonFormField<String>(
                  initialValue: collegeId,
                  decoration: const InputDecoration(labelText: 'College'),
                  items: colleges
                      .where((college) => college.active)
                      .map(
                        (college) => DropdownMenuItem(
                          value: college.id,
                          child: Text(college.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => collegeId = value),
                ),
              SwitchListTile(
                value: active,
                title: const Text('Active'),
                onChanged: (value) => setDialogState(() => active = value),
              ),
            ],
          ),
          actions: _confirmActions(dialogContext, 'Save'),
        ),
      ),
    );
    if (confirmed == true &&
        name.text.trim().length >= 2 &&
        code.text.trim().isNotEmpty &&
        (kind != 'course' || collegeId != null)) {
      await widget.repository.saveOrganizationRecord(
        kind: kind,
        id: record?.id,
        name: name.text,
        code: code.text,
        active: active,
        collegeId: collegeId ?? '',
      );
    }
    name.dispose();
    code.dispose();
  }
}

class _CompactAppUserRow extends StatelessWidget {
  const _CompactAppUserRow({
    required this.record,
    required this.profile,
    required this.onView,
  });

  final PublicAppUserRecord record;
  final UserModel? profile;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.canvas,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AdminColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.person_outline,
              size: 19,
              color: AdminColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                record.publicUserId,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _UserBadge(label: record.populationRole.label),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 7,
          children: [
            _AppUserFact(
              label: 'Department',
              value: record.department.isEmpty
                  ? 'Not provided'
                  : record.department,
            ),
            _AppUserFact(
              label: 'Account created',
              value: _date(record.createdAt),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.visibility_outlined, size: 17),
            label: const Text('View user'),
          ),
        ),
      ],
    ),
  );
}

class _AppUserFact extends StatelessWidget {
  const _AppUserFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(
      style: const TextStyle(color: AdminColors.ink, fontSize: 12),
      children: [
        TextSpan(
          text: '$label: ',
          style: const TextStyle(
            color: AdminColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(
          text: value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _StaffRecordCard extends StatelessWidget {
  const _StaffRecordCard({required this.user, required this.actions});

  final UserModel user;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final role = switch (user.accessRole) {
      AccessRole.portalStaff => 'Portal Staff',
      AccessRole.counselor => 'Counselor',
      AccessRole.admin => 'Administrator',
      AccessRole.appUser => 'App user',
    };
    final displayRole = user.staffAccountStatus == StaffAccountStatus.pending
        ? 'Requested: ${_accessRoleLabel(user.requestedRole == AccessRole.counselor ? AccessRole.counselor : AccessRole.portalStaff)}'
        : role;
    final status = _accountStatus(user);
    final position = [
      user.position,
      user.department ?? user.departmentId,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AdminColors.accentSoft,
                child: Text(
                  user.displayName.trim().isEmpty
                      ? '?'
                      : user.displayName.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AdminColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(position, style: const TextStyle(fontSize: 13)),
                    ],
                    if ((user.employeeId ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Employee ID ${user.employeeId}',
                        style: const TextStyle(
                          color: AdminColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      'Last sign-in: ${_date(user.lastActiveAt)}',
                      style: const TextStyle(
                        color: AdminColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final metadata = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _UserBadge(label: displayRole, highlighted: true),
              _UserBadge(
                label: user.staffAccountStatus == StaffAccountStatus.pending
                    ? 'Pending review'
                    : status,
              ),
              ...actions,
            ],
          );
          if (box.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 14), metadata],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: identity),
              const SizedBox(width: 20),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: metadata),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActivityLogView extends StatefulWidget {
  const _ActivityLogView({required this.repository, required this.user});
  final AdminPortalRepository repository;
  final UserModel user;

  @override
  State<_ActivityLogView> createState() => _ActivityLogViewState();
}

class _ActivityLogViewState extends State<_ActivityLogView> {
  String category = 'All modules';
  String period = 'Last 30 days';
  String actionFilter = 'All actions';
  List<AdminAuditEvent> events = const [];
  DateTime? cursor;
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  String? error;

  static const categories = [
    'All modules',
    'Authentication',
    'User Management',
    'Profiling',
    'Appointments',
    'Schedule',
    'Inquiries',
    'Reports',
    'System',
  ];
  static const actions = [
    'All actions',
    'Role changed',
    'Access revoked',
    'Account suspended',
    'Account reactivated',
    'Registration approved',
    'Signed in',
    'Signed out',
    'Appointment confirmed',
    'Appointment rescheduled',
    'Appointment completed',
    'Schedule adjustment requested',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      setState(() => loadingMore = true);
    } else {
      setState(() {
        loading = true;
        error = null;
        events = const [];
        cursor = null;
      });
    }
    try {
      final result = await widget.repository.fetchAuditLogPage(
        targetUserId: widget.user.id,
        category: category == 'All modules'
            ? ''
            : category.toUpperCase().replaceAll(' ', '_'),
        action: _actionValue(),
        before: cursor,
        after: _periodStart(),
      );
      if (!mounted) return;
      setState(() {
        events = [...events, ...result.events];
        hasMore = result.hasMore;
        if (result.events.isNotEmpty) cursor = result.events.last.createdAt;
        loading = false;
        loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadingMore = false;
        error = "We couldn't load this activity log.";
      });
    }
  }

  DateTime? _periodStart() {
    final now = DateTime.now();
    return switch (period) {
      'Today' => DateTime(now.year, now.month, now.day),
      'Last 7 days' => now.subtract(const Duration(days: 7)),
      'This month' => DateTime(now.year, now.month),
      'Last 30 days' => now.subtract(const Duration(days: 30)),
      _ => null,
    };
  }

  String _actionValue() => switch (actionFilter) {
    'Role changed' => 'STAFF_ROLE_CHANGED',
    'Access revoked' => 'STAFF_ACCESS_REVOKED',
    'Account suspended' => 'STAFF_ACCOUNT_SUSPENDED',
    'Account reactivated' => 'STAFF_ACCOUNT_REACTIVATED',
    'Registration approved' => 'STAFF_REGISTRATION_APPROVED',
    'Signed in' => 'STAFF_SIGNED_IN',
    'Signed out' => 'STAFF_SIGNED_OUT',
    'Appointment confirmed' => 'APPOINTMENT_CONFIRMED',
    'Appointment rescheduled' => 'APPOINTMENT_RESCHEDULED',
    'Appointment completed' => 'APPOINTMENT_COMPLETED',
    'Schedule adjustment requested' => 'APPOINTMENT_ADJUSTMENT_REQUESTED',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            const SizedBox(height: 10),
            FilledButton(onPressed: _load, child: const Text('Try Again')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filter(category, categories, (value) {
              category = value!;
              _load();
            }),
            _filter(actionFilter, actions, (value) {
              actionFilter = value!;
              _load();
            }),
            _filter(
              period,
              const [
                'Today',
                'Last 7 days',
                'Last 30 days',
                'This month',
                'All time',
              ],
              (value) {
                period = value!;
                _load();
              },
            ),
          ],
        ),
        if (events.isEmpty)
          const Expanded(
            child: Center(child: Text('No activity matches these filters.')),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 12),
              itemCount: events.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                if (index == events.length) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: OutlinedButton(
                        onPressed: loadingMore ? null : () => _load(more: true),
                        child: Text(loadingMore ? 'Loading…' : 'Load more'),
                      ),
                    ),
                  );
                }
                final event = events[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(_auditActionLabel(event.action)),
                  subtitle: Text(
                    [
                      _auditCategoryLabel(event.category),
                      if ((event.targetId ?? '').isNotEmpty)
                        '${event.targetType ?? 'Record'} • ${event.targetId}',
                      if (event.reason.isNotEmpty) event.reason,
                    ].join('\n'),
                  ),
                  trailing: Text(_date(event.createdAt)),
                  onTap: () => _showDetails(event),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _filter(
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => SizedBox(
    width: 180,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Filter'),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    ),
  );

  void _showDetails(AdminAuditEvent event) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(_auditActionLabel(event.action)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performed by: ${event.actorNameSnapshot.isEmpty ? 'Administrator' : event.actorNameSnapshot}',
          ),
          Text(
            'Role at the time: ${_accessRoleLabel(AccessRole.parse(event.actorRoleSnapshot))}',
          ),
          Text('Module: ${_auditCategoryLabel(event.category)}'),
          if ((event.targetId ?? '').isNotEmpty)
            Text('Target: ${event.targetId}'),
          if (event.reason.isNotEmpty) Text('Reason: ${event.reason}'),
          Text('Timestamp: ${_date(event.createdAt)}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _UserBadge extends StatelessWidget {
  const _UserBadge({required this.label, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: highlighted ? AdminColors.accentSoft : AdminColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

String _accountStatus(UserModel user) => switch (user.staffAccountStatus) {
  StaffAccountStatus.approved => 'Active',
  StaffAccountStatus.pending => user.registrationStatus ==
          'more_information_required'
      ? 'More information required'
      : 'Pending review',
  StaffAccountStatus.disabled => 'Suspended',
  StaffAccountStatus.rejected => 'Closed',
  null => 'Unknown',
};

String _accessRoleLabel(AccessRole role) => switch (role) {
  AccessRole.portalStaff => 'Portal Staff',
  AccessRole.counselor => 'Counselor',
  AccessRole.admin => 'Administrator',
  AccessRole.appUser => 'App user',
};

String _auditActionLabel(String action) => switch (action) {
  'STAFF_ROLE_CHANGED' => 'Role changed',
  'STAFF_ACCESS_REVOKED' => 'Portal access revoked',
  'STAFF_ACCOUNT_SUSPENDED' => 'Account suspended',
  'STAFF_ACCOUNT_REACTIVATED' => 'Account reactivated',
  'STAFF_REGISTRATION_APPROVED' => 'Staff registration approved',
  'STAFF_REGISTRATION_REJECTED' => 'Staff registration removed',
  'accessRoleAssigned' => 'Role changed',
  'staffAccountEnabled' => 'Account reactivated',
  'staffAccountDisabled' => 'Account suspended',
  'staffRegistrationApproved' => 'Invitation accepted',
  'staffRegistrationRejected' => 'Invitation removed',
  _ => action.isEmpty ? 'Access updated' : action,
};

String _auditCategoryLabel(String category) => switch (category) {
  'AUTHENTICATION' => 'Authentication',
  'USER_MANAGEMENT' => 'User Management',
  'PROFILING' => 'Profiling',
  'APPOINTMENTS' => 'Appointments',
  'SCHEDULE' => 'Schedule',
  'INQUIRIES' => 'Inquiries',
  'REPORTS' => 'Reports',
  'SYSTEM' => 'System',
  'SECURITY' => 'Security',
  _ => category.isEmpty ? 'User Management' : category,
};

String _date(DateTime? value) => value == null
    ? '—'
    : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
