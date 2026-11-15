import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';

/// Opens the college assignment editor for one staff member or counselor.
/// Returns true when the assignments were saved.
Future<bool> showCollegeAssignmentDialog(
  BuildContext context, {
  required AdminPortalRepository repository,
  required UserModel user,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          CollegeAssignmentDialog(repository: repository, user: user),
    ) ==
    true;

/// Edits the colleges a PACC staff member serves. Uses the existing college
/// catalogue; authorization and validation happen in the
/// `setStaffCollegeAssignments` callable.
class CollegeAssignmentDialog extends StatefulWidget {
  const CollegeAssignmentDialog({
    super.key,
    required this.repository,
    required this.user,
  });

  final AdminPortalRepository repository;
  final UserModel user;

  @override
  State<CollegeAssignmentDialog> createState() =>
      _CollegeAssignmentDialogState();
}

class _CollegeAssignmentDialogState extends State<CollegeAssignmentDialog> {
  late final Set<String> _selected = {...widget.user.assignedCollegeIds};
  late final Stream<List<College>> _colleges = widget.repository
      .watchColleges();
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && _reason.text.trim().length >= 3;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.setStaffCollegeAssignments(
        userId: widget.user.id,
        collegeIds: (_selected.toList()..sort()),
        expectedRevision: widget.user.collegeAssignmentRevision,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.code == 'permission-denied'
            ? 'Only the configured super-administrator can change college '
                  'assignments.'
            : (error.message?.trim().isNotEmpty == true
                  ? error.message!
                  : 'College assignments could not be saved (${error.code}).'),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'College assignments could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('College assignments · ${widget.user.displayName}'),
    content: SizedBox(
      width: 520,
      child: StreamBuilder<List<College>>(
        stream: _colleges,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('The college list could not be loaded.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final byId = {for (final c in snapshot.data!) c.id: c};
          // Active colleges are assignable; archived ones appear only while
          // still assigned so they can be removed.
          final visible = [
            for (final c in snapshot.data!)
              if (c.active || widget.user.assignedCollegeIds.contains(c.id)) c,
          ]..sort((a, b) => a.name.compareTo(b.name));
          final missing = widget.user.assignedCollegeIds
              .where((id) => !byId.containsKey(id))
              .toList();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selected.isEmpty
                      ? 'Unassigned'
                      : '${_selected.length} college(s) selected',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final college in visible)
                  CheckboxListTile(
                    dense: true,
                    value: _selected.contains(college.id),
                    title: Text(
                      college.active
                          ? college.name
                          : '${college.name} (archived)',
                    ),
                    subtitle: college.code.isEmpty ? null : Text(college.code),
                    onChanged: _saving
                        ? null
                        : (checked) => setState(
                            () => checked == true
                                ? _selected.add(college.id)
                                : _selected.remove(college.id),
                          ),
                  ),
                for (final id in missing)
                  CheckboxListTile(
                    dense: true,
                    value: _selected.contains(id),
                    title: Text('Unknown college ($id)'),
                    onChanged: _saving
                        ? null
                        : (checked) => setState(
                            () => checked == true
                                ? _selected.add(id)
                                : _selected.remove(id),
                          ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reason,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reason for change',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _canSave ? _save : null,
        child: const Text('Save assignments'),
      ),
    ],
  );
}
