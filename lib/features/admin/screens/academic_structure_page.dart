import 'package:flutter/material.dart';

import '../domain/admin_management_models.dart';
import '../theme/admin_theme.dart';
import '../../../repositories/admin_portal_repository.dart';

/// The administrator's single source of truth for colleges, departments and courses.
class AcademicStructurePage extends StatefulWidget {
  const AcademicStructurePage({super.key, required this.repository});
  final AdminPortalRepository repository;

  @override
  State<AcademicStructurePage> createState() => _AcademicStructurePageState();
}

class _AcademicStructurePageState extends State<AcademicStructurePage> {
  String query = '';
  String status = 'Active';
  bool _initializingCatalog = false;
  final Set<String> _updatingStructureIds = <String>{};
  // Editor dialog controllers live as long as the page, so they can never be
  // disposed while a dialog is still animating out.
  final List<TextEditingController> _editorControllers = [];

  @override
  void dispose() {
    for (final controller in _editorControllers) {
      controller.dispose();
    }
    _editorControllers.clear();
    super.dispose();
  }

  List<College> _loadedColleges = const <College>[];
  List<Department> _loadedDepartments = const <Department>[];

  bool _matches(OrganizationRecord item) =>
      (status == 'All' || (status == 'Active' ? item.active : !item.active)) &&
      (query.isEmpty ||
          '${item.name} ${item.code}'.toLowerCase().contains(query));

  String? _selectedCollegeId;

  /// Width at which the page switches from two panes to the single-column list.
  static const double _twoPaneBreakpoint = 900;

  bool _statusOk(OrganizationRecord item) =>
      status == 'All' || (status == 'Active' ? item.active : !item.active);

  bool _textMatch(OrganizationRecord item) =>
      query.isEmpty ||
      '${item.name} ${item.code}'.toLowerCase().contains(query);

  bool _collegeVisible(
    College college,
    List<Department> departments,
    List<Course> courses,
  ) =>
      _statusOk(college) &&
      (_textMatch(college) ||
          departments.any(
            (item) => item.collegeId == college.id && _textMatch(item),
          ) ||
          courses.any(
            (item) => item.collegeId == college.id && _textMatch(item),
          ));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < _twoPaneBreakpoint) return _singleColumn();
      return Padding(
        key: const ValueKey('academic-two-pane'),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 20),
            _toolbar(),
            const SizedBox(height: 16),
            Expanded(child: _streams(wide: true, builder: _twoPanes)),
          ],
        ),
      );
    },
  );

  Widget _singleColumn() => SingleChildScrollView(
    key: const ValueKey('academic-single-column'),
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 24),
        _toolbar(),
        const SizedBox(height: 20),
        _streams(wide: false, builder: _singleColumnList),
      ],
    ),
  );

  Widget _header() => LayoutBuilder(
    builder: (context, box) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Academic Structure',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Manage the colleges, departments, and courses used throughout MindMate.',
                  ),
                ],
              ),
            ),
            if (box.maxWidth > 560)
              FilledButton.icon(
                onPressed: () => _edit('college'),
                icon: const Icon(Icons.add),
                label: const Text('Add college'),
              ),
          ],
        ),
        if (box.maxWidth <= 560) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _edit('college'),
            icon: const Icon(Icons.add),
            label: const Text('Add college'),
          ),
        ],
      ],
    ),
  );

  /// Search, status filter and page-level actions. Further actions (such as
  /// the catalogue importer) are added in [_toolbarActions].
  Widget _toolbar() => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 340,
        child: TextField(
          onChanged: (value) =>
              setState(() => query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search academic structure',
          ),
        ),
      ),
      SizedBox(
        width: 170,
        child: DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: const ['Active', 'Inactive', 'All']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) => setState(() => status = value!),
        ),
      ),
      ..._toolbarActions(),
    ],
  );

  List<Widget> _toolbarActions() => const <Widget>[];

  Widget _streams({
    required bool wide,
    required Widget Function(
      List<College> colleges,
      List<Department> departments,
      List<Course> courses,
    )
    builder,
  }) {
    Widget wrap(Widget child) =>
        wide ? SingleChildScrollView(child: child) : child;
    return StreamBuilder<List<College>>(
      stream: widget.repository.watchColleges(),
      builder: (context, collegeSnapshot) {
        if (collegeSnapshot.hasError) return wrap(_error());
        if (!collegeSnapshot.hasData) return wrap(const _StructureSkeleton());
        return StreamBuilder<List<Department>>(
          stream: widget.repository.watchDepartments(),
          builder: (context, departmentSnapshot) {
            if (!departmentSnapshot.hasData) {
              return wrap(const _StructureSkeleton());
            }
            return StreamBuilder<List<Course>>(
              stream: widget.repository.watchCourses(),
              builder: (context, courseSnapshot) {
                if (!courseSnapshot.hasData) {
                  return wrap(const _StructureSkeleton());
                }
                _loadedDepartments = departmentSnapshot.data!;
                _loadedColleges = collegeSnapshot.data!;
                return builder(
                  _loadedColleges,
                  _loadedDepartments,
                  courseSnapshot.data!,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _singleColumnList(
    List<College> allColleges,
    List<Department> departments,
    List<Course> courses,
  ) {
    final colleges = allColleges.where(_matches).toList();
    if (colleges.isEmpty) return _empty();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: colleges
              .map((college) => _collegeTile(college, departments, courses))
              .toList(),
        ),
      ),
    );
  }

  // ---- Two-pane layout ----------------------------------------------------

  Widget _twoPanes(
    List<College> allColleges,
    List<Department> departments,
    List<Course> courses,
  ) {
    final colleges = allColleges
        .where((item) => _collegeVisible(item, departments, courses))
        .toList();
    if (colleges.isEmpty) {
      _selectedCollegeId = null;
      return SingleChildScrollView(child: _empty());
    }
    College? selected;
    for (final college in colleges) {
      if (college.id == _selectedCollegeId) selected = college;
    }
    // A filter or search that removes the selected college clears the selection.
    if (selected == null) _selectedCollegeId = null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 360,
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListView(
              children: colleges
                  .map((college) => _collegeRow(college, courses))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: selected == null
                ? const _SelectCollegePrompt()
                : _collegeDetail(selected, departments, courses),
          ),
        ),
      ],
    );
  }

  Widget _collegeRow(College college, List<Course> courses) {
    final selected = college.id == _selectedCollegeId;
    final activeCourses = courses
        .where((item) => item.collegeId == college.id && item.active)
        .length;
    return Material(
      key: ValueKey('college-row-${college.id}'),
      color: selected ? AdminColors.accentFaint : AdminColors.surface,
      child: InkWell(
        onTap: () => setState(() => _selectedCollegeId = college.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AdminColors.accent : Colors.transparent,
                width: 4,
              ),
              bottom: const BorderSide(color: AdminColors.border),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      college.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AdminColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Chip(college.code),
                        _statusChip(college),
                        Text(
                          activeCourses == 0
                              ? 'no courses'
                              : activeCourses == 1
                              ? '1 course'
                              : '$activeCourses courses',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdminColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _actions('college', college),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(OrganizationRecord item) => _Chip(
    item.active ? 'Active' : 'Inactive',
    color: item.active ? AdminColors.success : AdminColors.muted,
  );

  Widget _collegeDetail(
    College college,
    List<Department> departments,
    List<Course> courses,
  ) {
    final collegeDepartments = departments
        .where((item) => item.collegeId == college.id && _statusOk(item))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          college.name,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [_Chip(college.code), _statusChip(college)]),
        const SizedBox(height: 16),
        if (collegeDepartments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No departments yet.',
              style: TextStyle(color: AdminColors.muted),
            ),
          ),
        for (final department in collegeDepartments)
          _departmentBlock(department, courses),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _edit('department', initialCollegeId: college.id),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add department'),
          ),
        ),
      ],
    );
  }

  Widget _departmentBlock(Department department, List<Course> courses) {
    final departmentCourses = courses
        .where((item) => item.departmentId == department.id && _statusOk(item))
        .toList();
    return Container(
      key: ValueKey('department-${department.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AdminColors.surfaceMuted,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        department.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      _Chip(department.code),
                      _statusChip(department),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('add-course-${department.id}'),
                  onPressed: () => _edit(
                    'course',
                    initialCollegeId: department.collegeId,
                    initialDepartmentId: department.id,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Course'),
                ),
                _actions('department', department),
              ],
            ),
          ),
          if (departmentCourses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No courses yet.',
                style: TextStyle(color: AdminColors.muted),
              ),
            ),
          for (final course in departmentCourses)
            Container(
              key: ValueKey('course-${course.id}'),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AdminColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(course.name),
                        _Chip(course.code),
                        _statusChip(course),
                      ],
                    ),
                  ),
                  _actions('course', course),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Row menu (or progress spinner while the record is updating).
  Widget _actions(String kind, OrganizationRecord record) {
    if (_updatingStructureIds.contains(record.id)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'edit':
            _edit(
              kind,
              college: record is College ? record : null,
              department: record is Department ? record : null,
              course: record is Course ? record : null,
            );
          case 'addDepartment':
            _edit('department', initialCollegeId: record.id);
          case 'addCourse':
            final department = record as Department;
            _edit(
              'course',
              initialCollegeId: department.collegeId,
              initialDepartmentId: department.id,
            );
          default:
            _toggle(kind, record);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (kind == 'college')
          const PopupMenuItem(
            value: 'addDepartment',
            child: Text('Add department'),
          ),
        if (kind == 'department')
          const PopupMenuItem(value: 'addCourse', child: Text('Add course')),
        PopupMenuItem(
          value: 'toggle',
          child: Text(record.active ? 'Archive' : 'Restore'),
        ),
      ],
    );
  }

  Widget _collegeTile(
    College college,
    List<Department> departments,
    List<Course> courses,
  ) {
    final collegeDepartments = departments
        .where(
          (item) =>
              item.collegeId == college.id &&
              (status == 'All' || item.active == college.active),
        )
        .toList();
    final hasMatch =
        _matches(college) ||
        collegeDepartments.any(
          (department) =>
              _matches(department) ||
              courses.any(
                (course) =>
                    course.departmentId == department.id && _matches(course),
              ),
        );
    if (!hasMatch) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: query.isNotEmpty,
      leading: Icon(
        college.active
            ? Icons.account_balance_outlined
            : Icons.archive_outlined,
      ),
      title: Text(
        college.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${college.code} • ${college.active ? 'Active' : 'Inactive'}',
      ),
      trailing: _updatingStructureIds.contains(college.id)
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _edit('college', college: college);
                  case 'addDepartment':
                    _edit('department', initialCollegeId: college.id);
                  default:
                    _toggle('college', college);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                  value: 'addDepartment',
                  child: Text('Add department'),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(college.active ? 'Archive' : 'Restore'),
                ),
              ],
            ),
      children: collegeDepartments.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.only(left: 22, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        _edit('department', initialCollegeId: college.id),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add department'),
                  ),
                ),
              ),
            ]
          : collegeDepartments
                .map((department) => _departmentTile(department, courses))
                .toList(),
    );
  }

  Widget _departmentTile(
    Department department,
    List<Course> courses,
  ) => Padding(
    padding: const EdgeInsets.only(left: 22),
    child: ExpansionTile(
      initiallyExpanded: query.isNotEmpty,
      leading: Icon(
        department.active
            ? Icons.account_tree_outlined
            : Icons.archive_outlined,
        size: 20,
      ),
      title: Text(department.name),
      subtitle: Text(
        '${department.code} • ${department.active ? 'Active' : 'Inactive'}',
      ),
      trailing: _updatingStructureIds.contains(department.id)
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _edit('department', department: department);
                  case 'addCourse':
                    _edit(
                      'course',
                      initialCollegeId: department.collegeId,
                      initialDepartmentId: department.id,
                    );
                  default:
                    _toggle('department', department);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                  value: 'addCourse',
                  child: Text('Add course'),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(department.active ? 'Archive' : 'Restore'),
                ),
              ],
            ),
      children: courses
          .where(
            (course) =>
                course.departmentId == department.id &&
                (status == 'All' || course.active == department.active) &&
                (query.isEmpty || _matches(course)),
          )
          .map(
            (course) => Padding(
              padding: const EdgeInsets.only(left: 22),
              child: ListTile(
                leading: const Icon(Icons.school_outlined, size: 20),
                title: Text(course.name),
                subtitle: Text(
                  '${course.code} • ${course.active ? 'Active' : 'Inactive'}',
                ),
                trailing: _updatingStructureIds.contains(course.id)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        onSelected: (value) => value == 'edit'
                            ? _edit('course', course: course)
                            : _toggle('course', course),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(course.active ? 'Archive' : 'Restore'),
                          ),
                        ],
                      ),
              ),
            ),
          )
          .toList(),
    ),
  );

  Widget _empty() => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.account_tree_outlined,
              size: 40,
              color: AdminColors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'No academic structure configured'
                  : 'No matching academic structure',
            ),
            const SizedBox(height: 6),
            Text(
              query.isEmpty
                  ? 'Add your first college to begin.'
                  : 'Try a different search or status filter.',
              style: const TextStyle(color: AdminColors.muted),
            ),
            if (query.isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _edit('college'),
                icon: const Icon(Icons.add),
                label: const Text('Add college'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _initializingCatalog ? null : _initializeCatalog,
                icon: _initializingCatalog
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  _initializingCatalog
                      ? 'Loading catalog…'
                      : 'Load current catalog',
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _error() => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Text("We couldn't load the academic structure."),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() {}),
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );

  Future<void> _initializeCatalog() async {
    if (_initializingCatalog) return;
    setState(() => _initializingCatalog = true);
    try {
      final count = await widget.repository.initializeAcademicStructure();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? 'Current academic catalog loaded.'
                  : 'Academic structure is already configured.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The academic catalog could not be loaded. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _initializingCatalog = false);
    }
  }

  Future<void> _edit(
    String kind, {
    College? college,
    Department? department,
    Course? course,
    String? initialCollegeId,
    String? initialDepartmentId,
  }) async {
    if (!mounted) return;
    final name = TextEditingController(
      text: college?.name ?? department?.name ?? course?.name,
    );
    final code = TextEditingController(
      text: college?.code ?? department?.code ?? course?.code,
    );
    _editorControllers.addAll([name, code]);
    final colleges = _loadedColleges;
    final departments = _loadedDepartments;
    if (!mounted) return;
    String? collegeId =
        department?.collegeId ?? course?.collegeId ?? initialCollegeId;
    String? departmentId = course?.departmentId ?? initialDepartmentId;
    var active =
        college?.active ?? department?.active ?? course?.active ?? true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final availableDepartments = departments
              .where((item) => item.collegeId == collegeId && item.active)
              .toList();
          return AlertDialog(
            title: Text(
              '${college != null || department != null || course != null ? 'Edit' : 'Add'} ${kind[0].toUpperCase()}${kind.substring(1)}',
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (kind != 'college')
                    DropdownButtonFormField<String>(
                      initialValue: collegeId,
                      decoration: const InputDecoration(labelText: 'College'),
                      items: colleges
                          .where((item) => item.active)
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(() {
                        collegeId = value;
                        departmentId = null;
                      }),
                    ),
                  if (kind == 'course')
                    DropdownButtonFormField<String>(
                      initialValue: departmentId,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                      ),
                      items: availableDepartments
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => departmentId = value),
                    ),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText:
                          '${kind[0].toUpperCase()}${kind.substring(1)} name',
                    ),
                  ),
                  TextField(
                    controller: code,
                    decoration: InputDecoration(
                      labelText:
                          '${kind[0].toUpperCase()}${kind.substring(1)} code',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  college != null || department != null || course != null
                      ? 'Save'
                      : 'Add',
                ),
              ),
            ],
          );
        },
      ),
    );
    if (result == true &&
        name.text.trim().length >= 2 &&
        code.text.trim().isNotEmpty &&
        (kind == 'college' || collegeId != null) &&
        (kind != 'course' || departmentId != null)) {
      try {
        await widget.repository.saveOrganizationRecord(
          kind: kind,
          id: college?.id ?? department?.id ?? course?.id,
          name: name.text,
          code: code.text,
          active: active,
          collegeId: collegeId ?? '',
          departmentId: departmentId ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Academic structure saved.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This record could not be saved. Check for duplicates and try again.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _toggle(String kind, OrganizationRecord item) async {
    if (_updatingStructureIds.contains(item.id)) return;
    final action = item.active ? 'archive' : 'restore';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} ${item.name}?',
        ),
        content: Text(
          item.active
              ? 'This keeps historical references but prevents the record from being used in new forms.'
              : 'This will make the record available again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _updatingStructureIds.add(item.id));
    try {
      await widget.repository.archiveOrganizationRecord(
        kind: kind,
        id: item.id,
        archived: item.active,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Academic structure ${item.active ? 'archived' : 'restored'}.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This record cannot be archived while active child records depend on it.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingStructureIds.remove(item.id));
    }
  }
}

class _StructureSkeleton extends StatelessWidget {
  const _StructureSkeleton();
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      4,
      (index) => const Card(
        child: SizedBox(
          height: 70,
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 300, child: LinearProgressIndicator()),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color = AdminColors.ink});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _SelectCollegePrompt extends StatelessWidget {
  const _SelectCollegePrompt();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.account_balance_outlined,
          size: 40,
          color: AdminColors.muted,
        ),
        SizedBox(height: 12),
        Text('Select a college'),
        SizedBox(height: 6),
        Text(
          'Its departments and courses appear here.',
          style: TextStyle(color: AdminColors.muted),
        ),
      ],
    ),
  );
}
