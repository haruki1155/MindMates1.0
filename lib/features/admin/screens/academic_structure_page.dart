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

  bool _matches(OrganizationRecord item) =>
      (status == 'All' || (status == 'Active' ? item.active : !item.active)) &&
      (query.isEmpty || '${item.name} ${item.code}'.toLowerCase().contains(query));

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, box) => Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Academic Structure', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          const Text('Manage the colleges, departments, and courses used throughout MindMate.'),
        ])),
        if (box.maxWidth > 560) FilledButton.icon(onPressed: () => _edit('college'), icon: const Icon(Icons.add), label: const Text('Add college')),
      ])),
      if (MediaQuery.sizeOf(context).width <= 560) ...[
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => _edit('college'), icon: const Icon(Icons.add), label: const Text('Add college')),
      ],
      const SizedBox(height: 24),
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 340, child: TextField(onChanged: (value) => setState(() => query = value.trim().toLowerCase()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search academic structure'))),
        SizedBox(width: 170, child: DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Status'), items: const ['Active', 'Inactive', 'All'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => status = value!))),
      ]),
      const SizedBox(height: 20),
      StreamBuilder<List<College>>(stream: widget.repository.watchColleges(), builder: (context, collegeSnapshot) {
        if (collegeSnapshot.hasError) return _error();
        if (!collegeSnapshot.hasData) return const _StructureSkeleton();
        return StreamBuilder<List<Department>>(stream: widget.repository.watchDepartments(), builder: (context, departmentSnapshot) {
          if (!departmentSnapshot.hasData) return const _StructureSkeleton();
          return StreamBuilder<List<Course>>(stream: widget.repository.watchCourses(), builder: (context, courseSnapshot) {
            if (!courseSnapshot.hasData) return const _StructureSkeleton();
            final departments = departmentSnapshot.data!;
            final courses = courseSnapshot.data!;
            final colleges = collegeSnapshot.data!.where(_matches).toList();
            if (colleges.isEmpty) return _empty();
            return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: colleges.map((college) => _collegeTile(college, departments, courses)).toList())));
          });
        });
      }),
    ]),
  );

  Widget _collegeTile(College college, List<Department> departments, List<Course> courses) {
    final collegeDepartments = departments.where((item) => item.collegeId == college.id && (status == 'All' || item.active == college.active)).toList();
    final hasMatch = _matches(college) || collegeDepartments.any((department) => _matches(department) || courses.any((course) => course.departmentId == department.id && _matches(course)));
    if (!hasMatch) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: query.isNotEmpty,
      leading: Icon(college.active ? Icons.account_balance_outlined : Icons.archive_outlined),
      title: Text(college.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${college.code} • ${college.active ? 'Active' : 'Inactive'}'),
      trailing: PopupMenuButton<String>(onSelected: (value) => value == 'edit' ? _edit('college', college: college) : _toggle('college', college), itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text(college.active ? 'Archive' : 'Restore'))]),
      children: collegeDepartments.map((department) => _departmentTile(department, courses)).toList(),
    );
  }

  Widget _departmentTile(Department department, List<Course> courses) => Padding(
    padding: const EdgeInsets.only(left: 22),
    child: ExpansionTile(
      initiallyExpanded: query.isNotEmpty,
      leading: Icon(department.active ? Icons.account_tree_outlined : Icons.archive_outlined, size: 20),
      title: Text(department.name), subtitle: Text('${department.code} • ${department.active ? 'Active' : 'Inactive'}'),
      trailing: PopupMenuButton<String>(onSelected: (value) => value == 'edit' ? _edit('department', department: department) : _toggle('department', department), itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text(department.active ? 'Archive' : 'Restore'))]),
      children: courses.where((course) => course.departmentId == department.id && (status == 'All' || course.active == department.active) && (query.isEmpty || _matches(course))).map((course) => Padding(padding: const EdgeInsets.only(left: 22), child: ListTile(leading: const Icon(Icons.school_outlined, size: 20), title: Text(course.name), subtitle: Text('${course.code} • ${course.active ? 'Active' : 'Inactive'}'), trailing: PopupMenuButton<String>(onSelected: (value) => value == 'edit' ? _edit('course', course: course) : _toggle('course', course), itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text(course.active ? 'Archive' : 'Restore'))])))).toList(),
    ),
  );

  Widget _empty() => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Center(child: Column(children: [
        const Icon(Icons.account_tree_outlined, size: 40, color: AdminColors.muted),
        const SizedBox(height: 12),
        Text(query.isEmpty ? 'No academic structure configured' : 'No matching academic structure'),
        const SizedBox(height: 6),
        Text(query.isEmpty ? 'Add your first college to begin.' : 'Try a different search or status filter.', style: const TextStyle(color: AdminColors.muted)),
        if (query.isEmpty) ...[
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () => _edit('college'), icon: const Icon(Icons.add), label: const Text('Add college')),
        ],
      ])),
    ),
  );

  Widget _error() => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(children: [
        const Text("We couldn't load the academic structure."),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => setState(() {}), child: const Text('Try again')),
      ]),
    ),
  );

  Future<void> _edit(String kind, {College? college, Department? department, Course? course}) async {
    final name = TextEditingController(text: college?.name ?? department?.name ?? course?.name);
    final code = TextEditingController(text: college?.code ?? department?.code ?? course?.code);
    final colleges = await widget.repository.watchColleges().first;
    final departments = await widget.repository.watchDepartments().first;
    String? collegeId = department?.collegeId ?? course?.collegeId;
    String? departmentId = course?.departmentId;
    var active = college?.active ?? department?.active ?? course?.active ?? true;
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
      final availableDepartments = departments.where((item) => item.collegeId == collegeId && item.active).toList();
      return AlertDialog(title: Text('${college != null || department != null || course != null ? 'Edit' : 'Add'} ${kind[0].toUpperCase()}${kind.substring(1)}'), content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [if (kind != 'college') DropdownButtonFormField<String>(initialValue: collegeId, decoration: const InputDecoration(labelText: 'College'), items: colleges.where((item) => item.active).map((item) => DropdownMenuItem(value: item.id, child: Text(item.name, overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setDialogState(() { collegeId = value; departmentId = null; })), if (kind == 'course') DropdownButtonFormField<String>(initialValue: departmentId, decoration: const InputDecoration(labelText: 'Department'), items: availableDepartments.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name, overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setDialogState(() => departmentId = value)), TextField(controller: name, decoration: InputDecoration(labelText: '$kind name')), TextField(controller: code, decoration: InputDecoration(labelText: '$kind code'))])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(college != null || department != null || course != null ? 'Save' : 'Add'))]);
    }));
    if (result == true && name.text.trim().length >= 2 && code.text.trim().isNotEmpty && (kind == 'college' || collegeId != null) && (kind != 'course' || departmentId != null)) {
      try { await widget.repository.saveOrganizationRecord(kind: kind, id: college?.id ?? department?.id ?? course?.id, name: name.text, code: code.text, active: active, collegeId: collegeId ?? '', departmentId: departmentId ?? ''); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Academic structure saved.'))); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This record could not be saved. Check for duplicates and try again.'))); }
    }
    name.dispose(); code.dispose();
  }

  Future<void> _toggle(String kind, OrganizationRecord item) async {
    final action = item.active ? 'archive' : 'restore';
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text('${action[0].toUpperCase()}${action.substring(1)} ${item.name}?'), content: Text(item.active ? 'This keeps historical references but prevents the record from being used in new forms.' : 'This will make the record available again.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action[0].toUpperCase() + action.substring(1)))]));
    if (ok != true) return;
    try { await widget.repository.archiveOrganizationRecord(kind: kind, id: item.id, archived: item.active); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Academic structure ${item.active ? 'archived' : 'restored'}.'))); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This record cannot be archived while active child records depend on it.'))); }
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
