import 'package:flutter/material.dart';

import '../../../models/profile_roles.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';

enum ProfileSort {
  name('Name'),
  identifier('ID number'),
  department('Department'),
  course('Course'),
  yearLevel('Year level'),
  position('Designation');

  const ProfileSort(this.label);
  final String label;
}

/// A read-only, category-aware directory backed by the profiles created during
/// registration. It deliberately excludes portal staff accounts and never
/// combines student, teaching, and non-teaching records.
class ProfileManagementPage extends StatefulWidget {
  const ProfileManagementPage({super.key, required this.repository});

  final AdminPortalRepository repository;

  @override
  State<ProfileManagementPage> createState() => _ProfileManagementPageState();
}

class _ProfileManagementPageState extends State<ProfileManagementPage> {
  final _searchController = TextEditingController();
  PopulationRole _category = PopulationRole.student;
  String? _department;
  String? _course;
  String? _yearLevel;
  String? _position;
  ProfileSort _sort = ProfileSort.name;
  bool _ascending = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: widget.repository.watchUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _MessageState(
            icon: Icons.lock_outline_rounded,
            title: 'Unable to load user profiles',
            message:
                'Profiling records are available only to authorized administrators. Check your access and try again.',
          );
        }

        final allProfiles = (snapshot.data ?? const <UserModel>[])
            .where(
              (user) => user.isAppUser && user.effectivePopulationRole != null,
            )
            .toList(growable: false);
        final categoryProfiles = allProfiles
            .where((user) => user.effectivePopulationRole == _category)
            .toList(growable: false);
        final filteredProfiles = _filterAndSort(categoryProfiles);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
            28,
            MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profiling Management',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find and organize registered users by academic or employment information.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  _SummaryRow(profiles: allProfiles),
                  const SizedBox(height: 18),
                  _DirectoryCard(
                    category: _category,
                    allProfiles: allProfiles,
                    categoryProfiles: categoryProfiles,
                    filteredProfiles: filteredProfiles,
                    searchController: _searchController,
                    department: _department,
                    course: _course,
                    yearLevel: _yearLevel,
                    position: _position,
                    sort: _sort,
                    ascending: _ascending,
                    onCategoryChanged: _changeCategory,
                    onSearchChanged: (_) => setState(() {}),
                    onDepartmentChanged: (value) =>
                        setState(() => _department = value),
                    onCourseChanged: (value) => setState(() => _course = value),
                    onYearChanged: (value) =>
                        setState(() => _yearLevel = value),
                    onPositionChanged: (value) =>
                        setState(() => _position = value),
                    onSortChanged: (value) => setState(() => _sort = value),
                    onDirectionChanged: () =>
                        setState(() => _ascending = !_ascending),
                    onClear: _clearFilters,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _changeCategory(PopulationRole category) {
    setState(() {
      _category = category;
      _department = null;
      _course = null;
      _yearLevel = null;
      _position = null;
      _sort = ProfileSort.name;
      _searchController.clear();
    });
  }

  void _clearFilters() {
    setState(() {
      _department = null;
      _course = null;
      _yearLevel = null;
      _position = null;
      _searchController.clear();
    });
  }

  List<UserModel> _filterAndSort(List<UserModel> users) {
    final query = _searchController.text.trim().toLowerCase();
    final result = users.where((user) {
      final matchesSearch =
          query.isEmpty ||
          user.displayName.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          _identifier(user).toLowerCase().contains(query);
      return matchesSearch &&
          (_department == null || _organization(user) == _department) &&
          (_course == null || _text(user.course) == _course) &&
          (_yearLevel == null || _text(user.yearLevel) == _yearLevel) &&
          (_position == null || _text(user.position) == _position);
    }).toList();

    result.sort((a, b) {
      final first = _sortValue(a, _sort).toLowerCase();
      final second = _sortValue(b, _sort).toLowerCase();
      final comparison = first.compareTo(second);
      if (comparison != 0) return _ascending ? comparison : -comparison;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return result;
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.profiles});
  final List<UserModel> profiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 840
            ? 3
            : constraints.maxWidth >= 500
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final role in PopulationRole.values)
              _SummaryTile(
                width: width,
                role: role,
                count: profiles
                    .where((user) => user.effectivePopulationRole == role)
                    .length,
              ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.width,
    required this.role,
    required this.count,
  });
  final double width;
  final PopulationRole role;
  final int count;

  @override
  Widget build(BuildContext context) {
    final icon = switch (role) {
      PopulationRole.student => Icons.school_outlined,
      PopulationRole.teaching => Icons.co_present_outlined,
      PopulationRole.nonTeaching => Icons.business_center_outlined,
    };
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AdminColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${role.label} users',
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _DirectoryCard extends StatelessWidget {
  const _DirectoryCard({
    required this.category,
    required this.allProfiles,
    required this.categoryProfiles,
    required this.filteredProfiles,
    required this.searchController,
    required this.department,
    required this.course,
    required this.yearLevel,
    required this.position,
    required this.sort,
    required this.ascending,
    required this.onCategoryChanged,
    required this.onSearchChanged,
    required this.onDepartmentChanged,
    required this.onCourseChanged,
    required this.onYearChanged,
    required this.onPositionChanged,
    required this.onSortChanged,
    required this.onDirectionChanged,
    required this.onClear,
  });

  final PopulationRole category;
  final List<UserModel> allProfiles;
  final List<UserModel> categoryProfiles;
  final List<UserModel> filteredProfiles;
  final TextEditingController searchController;
  final String? department;
  final String? course;
  final String? yearLevel;
  final String? position;
  final ProfileSort sort;
  final bool ascending;
  final ValueChanged<PopulationRole> onCategoryChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onCourseChanged;
  final ValueChanged<String?> onYearChanged;
  final ValueChanged<String?> onPositionChanged;
  final ValueChanged<ProfileSort> onSortChanged;
  final VoidCallback onDirectionChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isStudent = category == PopulationRole.student;
    final departments = _options(categoryProfiles.map(_organization));
    final courses = _options(
      categoryProfiles.map((user) => _text(user.course)),
    );
    final years = _options(
      categoryProfiles.map((user) => _text(user.yearLevel)),
    );
    final positions = _options(
      categoryProfiles.map((user) => _text(user.position)),
    );
    final hasFilters =
        searchController.text.trim().isNotEmpty ||
        department != null ||
        course != null ||
        yearLevel != null ||
        position != null;
    final availableSorts = isStudent
        ? const [
            ProfileSort.name,
            ProfileSort.identifier,
            ProfileSort.department,
            ProfileSort.course,
            ProfileSort.yearLevel,
          ]
        : const [
            ProfileSort.name,
            ProfileSort.identifier,
            ProfileSort.department,
            ProfileSort.position,
          ];

    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'User directory',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Categories stay separate so academic and employment data are never mixed.',
                  style: TextStyle(color: AdminColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final role in PopulationRole.values)
                      ChoiceChip(
                        key: ValueKey('profile-category-${role.name}'),
                        label: Text(
                          '${role.label} (${allProfiles.where((user) => user.effectivePopulationRole == role).length})',
                        ),
                        selected: category == role,
                        onSelected: (_) => onCategoryChanged(role),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final controlCount = isStudent ? 5 : 4;
                    final fieldWidth = constraints.maxWidth >= 1100
                        ? (constraints.maxWidth - ((controlCount - 1) * 12)) /
                              controlCount
                        : constraints.maxWidth >= 600
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            key: const ValueKey('profile-search'),
                            controller: searchController,
                            onChanged: onSearchChanged,
                            decoration: InputDecoration(
                              labelText: isStudent
                                  ? 'Search name or Student ID'
                                  : 'Search name or Employee ID',
                              prefixIcon: const Icon(Icons.search, size: 20),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _FilterDropdown(
                            key: const ValueKey('profile-department-filter'),
                            label: isStudent
                                ? 'Department'
                                : 'Department / unit',
                            value: department,
                            options: departments,
                            onChanged: onDepartmentChanged,
                          ),
                        ),
                        if (isStudent)
                          SizedBox(
                            width: fieldWidth,
                            child: _FilterDropdown(
                              key: const ValueKey('profile-course-filter'),
                              label: 'Course',
                              value: course,
                              options: courses,
                              onChanged: onCourseChanged,
                            ),
                          ),
                        if (isStudent)
                          SizedBox(
                            width: fieldWidth,
                            child: _FilterDropdown(
                              key: const ValueKey('profile-year-filter'),
                              label: 'Year level',
                              value: yearLevel,
                              options: years,
                              onChanged: onYearChanged,
                            ),
                          ),
                        if (!isStudent)
                          SizedBox(
                            width: fieldWidth,
                            child: _FilterDropdown(
                              key: const ValueKey('profile-position-filter'),
                              label: 'Designation / position',
                              value: position,
                              options: positions,
                              onChanged: onPositionChanged,
                            ),
                          ),
                        SizedBox(
                          key: const ValueKey('profile-sort-control'),
                          width: fieldWidth,
                          height: 48,
                          child: _SortControl(
                            sort: availableSorts.contains(sort)
                                ? sort
                                : ProfileSort.name,
                            availableSorts: availableSorts,
                            ascending: ascending,
                            onSortChanged: onSortChanged,
                            onDirectionChanged: onDirectionChanged,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                _ResultsToolbar(
                  resultLabel:
                      '${filteredProfiles.length} of ${categoryProfiles.length} ${category.label.toLowerCase()} users',
                  hasFilters: hasFilters,
                  onClear: onClear,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (filteredProfiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 54),
              child: _MessageState(
                icon: Icons.person_search_outlined,
                title: 'No matching users',
                message: 'Try another ID, name, or filter selection.',
              ),
            )
          else
            _ProfileResults(users: filteredProfiles, category: category),
        ],
      ),
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({
    required this.sort,
    required this.availableSorts,
    required this.ascending,
    required this.onSortChanged,
    required this.onDirectionChanged,
  });

  final ProfileSort sort;
  final List<ProfileSort> availableSorts;
  final bool ascending;
  final ValueChanged<ProfileSort> onSortChanged;
  final VoidCallback onDirectionChanged;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: DropdownButtonFormField<ProfileSort>(
          key: const ValueKey('profile-sort'),
          initialValue: sort,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Sort by'),
          items: [
            for (final item in availableSorts)
              DropdownMenuItem(value: item, child: Text(item.label)),
          ],
          onChanged: (value) {
            if (value != null) onSortChanged(value);
          },
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: ascending ? 'Sort ascending' : 'Sort descending',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            key: const ValueKey('profile-sort-direction'),
            color: AdminColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AdminColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onDirectionChanged,
              child: Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _ResultsToolbar extends StatelessWidget {
  const _ResultsToolbar({
    required this.resultLabel,
    required this.hasFilters,
    required this.onClear,
  });

  final String resultLabel;
  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          resultLabel,
          style: const TextStyle(
            color: AdminColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (hasFilters)
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
          label: const Text('Clear filters'),
        ),
    ],
  );
}

class _ProfileResults extends StatelessWidget {
  const _ProfileResults({required this.users, required this.category});
  final List<UserModel> users;
  final PopulationRole category;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var index = 0; index < users.length; index++) ...[
                _ProfileCard(user: users[index], category: category),
                if (index != users.length - 1) const Divider(height: 1),
              ],
            ],
          );
        }
        final isStudent = category == PopulationRole.student;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: [
              const DataColumn(label: Text('User')),
              DataColumn(label: Text(isStudent ? 'Student ID' : 'Employee ID')),
              DataColumn(
                label: Text(isStudent ? 'Department' : 'Department / unit'),
              ),
              if (isStudent) const DataColumn(label: Text('Course')),
              if (isStudent) const DataColumn(label: Text('Year')),
              if (!isStudent)
                const DataColumn(label: Text('Designation / position')),
              const DataColumn(label: Text('Profile')),
            ],
            rows: [
              for (final user in users)
                DataRow(
                  key: ValueKey('profile-row-${user.id}'),
                  onSelectChanged: (_) => showManagedUserProfile(context, user),
                  cells: [
                    DataCell(_UserCell(user: user)),
                    DataCell(Text(_identifier(user))),
                    DataCell(Text(_organization(user))),
                    if (isStudent) DataCell(Text(_text(user.course))),
                    if (isStudent) DataCell(Text(_text(user.yearLevel))),
                    if (!isStudent) DataCell(Text(_text(user.position))),
                    DataCell(
                      _CompletenessBadge(complete: user.isProfileComplete),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UserCell extends StatelessWidget {
  const _UserCell({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: AdminColors.accentSoft,
          backgroundImage: (user.profilePhotoUrl ?? '').trim().isNotEmpty
              ? NetworkImage(user.profilePhotoUrl!)
              : null,
          child: (user.profilePhotoUrl ?? '').trim().isEmpty
              ? Text(
                  _initials(user.displayName),
                  style: const TextStyle(
                    color: AdminColors.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 210),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AdminColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.category});
  final UserModel user;
  final PopulationRole category;

  @override
  Widget build(BuildContext context) {
    final isStudent = category == PopulationRole.student;
    return InkWell(
      key: ValueKey('profile-card-${user.id}'),
      onTap: () => showManagedUserProfile(context, user),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _UserCell(user: user)),
                const Icon(Icons.chevron_right, color: AdminColors.muted),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 7,
              children: [
                _CompactFact(
                  label: isStudent ? 'Student ID' : 'Employee ID',
                  value: _identifier(user),
                ),
                _CompactFact(label: 'Department', value: _organization(user)),
                if (isStudent)
                  _CompactFact(label: 'Course', value: _text(user.course)),
                if (isStudent)
                  _CompactFact(label: 'Year', value: _text(user.yearLevel)),
                if (!isStudent)
                  _CompactFact(label: 'Position', value: _text(user.position)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFact extends StatelessWidget {
  const _CompactFact({required this.label, required this.value});
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

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: options.contains(value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem(value: null, child: Text('All')),
      for (final option in options)
        DropdownMenuItem(value: option, child: Text(option)),
    ],
    onChanged: onChanged,
  );
}

class _CompletenessBadge extends StatelessWidget {
  const _CompletenessBadge({required this.complete});
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final color = complete ? AdminColors.success : AdminColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        complete ? 'Complete' : 'Incomplete',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final role = user.effectivePopulationRole ?? PopulationRole.student;
    final isStudent = role == PopulationRole.student;
    final birthDate = user.dateOfBirth;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: AdminColors.accentSoft,
                    backgroundImage:
                        (user.profilePhotoUrl ?? '').trim().isNotEmpty
                        ? NetworkImage(user.profilePhotoUrl!)
                        : null,
                    child: (user.profilePhotoUrl ?? '').trim().isEmpty
                        ? Text(
                            _initials(user.displayName),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AdminColors.ink,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${role.label} user  •  ${_identifier(user)}',
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 20),
              const _SectionTitle(
                icon: Icons.person_outline,
                title: 'Personal information',
              ),
              const SizedBox(height: 12),
              _DetailsGrid(
                items: [
                  _Detail('Full name', user.displayName),
                  _Detail('Email address', _text(user.email)),
                  _Detail('Gender', _text(user.gender)),
                  _Detail(
                    'Date of birth',
                    birthDate == null ? 'Not provided' : _formatDate(birthDate),
                  ),
                  _Detail(
                    'Age',
                    user.age == null ? 'Not provided' : '${user.age} years old',
                  ),
                  _Detail('Category', role.label),
                ],
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                icon: isStudent
                    ? Icons.school_outlined
                    : Icons.business_center_outlined,
                title: isStudent
                    ? 'Academic information'
                    : 'Employment information',
              ),
              const SizedBox(height: 12),
              _DetailsGrid(
                items: isStudent
                    ? [
                        _Detail('Student ID', _identifier(user)),
                        _Detail('Department', _organization(user)),
                        _Detail('Course', _text(user.course)),
                        _Detail('Year level', _text(user.yearLevel)),
                      ]
                    : [
                        _Detail('Employee ID', _identifier(user)),
                        _Detail('Department / unit', _organization(user)),
                        _Detail('Designation / position', _text(user.position)),
                      ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _CompletenessBadge(complete: user.isProfileComplete),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Registration profile record',
                      style: TextStyle(color: AdminColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: AdminColors.accentStrong),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.items});
  final List<_Detail> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 520
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in items)
            Container(
              width: width,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AdminColors.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      color: AdminColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _Detail {
  const _Detail(this.label, this.value);
  final String label;
  final String value;
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: AdminColors.accentStrong),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

void showManagedUserProfile(BuildContext context, UserModel user) {
  showDialog<void>(
    context: context,
    builder: (_) => _ProfileDialog(user: user),
  );
}

String _identifier(UserModel user) {
  return user.effectivePopulationRole == PopulationRole.student
      ? _text(user.schoolId)
      : _text(user.employeeId);
}

String _organization(UserModel user) {
  final department = user.department?.trim() ?? '';
  if (department.isNotEmpty) return department;
  return _text(user.sector);
}

String _sortValue(UserModel user, ProfileSort sort) => switch (sort) {
  ProfileSort.name => user.displayName,
  ProfileSort.identifier => _identifier(user),
  ProfileSort.department => _organization(user),
  ProfileSort.course => _text(user.course),
  ProfileSort.yearLevel => _text(user.yearLevel),
  ProfileSort.position => _text(user.position),
};

String _text(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? 'Not provided' : text;
}

List<String> _options(Iterable<String> values) {
  final result =
      values.where((value) => value != 'Not provided').toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  return words.take(2).map((word) => word[0].toUpperCase()).join();
}

String _formatDate(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.day.toString().padLeft(2, '0')}/${date.year}';
