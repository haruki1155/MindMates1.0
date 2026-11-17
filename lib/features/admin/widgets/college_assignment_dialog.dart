import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/profile_roles.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';
import '../theme/admin_theme.dart';

const String collegeAlreadyAssignedMessage =
    'This college is already assigned to another counselor. Reassign it through the authorized transfer process.';

bool isEligibleCounselorAccount(UserModel user) =>
    user.accessRole == AccessRole.counselor &&
    (user.staffAccountStatus == null ||
        user.staffAccountStatus == StaffAccountStatus.approved) &&
    (user.accountStatus == null || user.accountStatus == 'active');

/// Opens the counselor college assignment editor for one counselor.
/// Returns true when the assignments were saved.
Future<bool> showCollegeAssignmentDialog(
  BuildContext context, {
  required AdminPortalRepository repository,
  required UserModel user,
  List<UserModel> allUsers = const [],
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => CollegeAssignmentDialog(
        repository: repository,
        user: user,
        allUsers: allUsers,
      ),
    ) ==
    true;

/// Opens the authorized college-level counselor assignment / transfer /
/// conflict resolution dialog for one college.
Future<bool> showCollegeCounselorTransferDialog(
  BuildContext context, {
  required AdminPortalRepository repository,
  required College college,
  required List<UserModel> currentOwners,
  required List<UserModel> eligibleCounselors,
  bool readOnly = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => CollegeCounselorTransferDialog(
        repository: repository,
        college: college,
        currentOwners: currentOwners,
        eligibleCounselors: eligibleCounselors,
        readOnly: readOnly,
      ),
    ) ==
    true;

/// Edits the colleges a PACC counselor serves. Uses the existing college
/// catalogue; authorization, one-counselor-per-college uniqueness, and
/// revision checks happen in the `setStaffCollegeAssignments` callable.
class CollegeAssignmentDialog extends StatefulWidget {
  const CollegeAssignmentDialog({
    super.key,
    required this.repository,
    required this.user,
    this.allUsers = const [],
  });

  final AdminPortalRepository repository;
  final UserModel user;
  final List<UserModel> allUsers;

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

  late final Map<String, List<UserModel>> _otherOwnersByCollege = (() {
    final map = <String, List<UserModel>>{};
    for (final candidate in widget.allUsers) {
      if (candidate.id == widget.user.id ||
          candidate.accessRole != AccessRole.counselor) {
        continue;
      }
      for (final cid in candidate.assignedCollegeIds) {
        (map[cid] ??= []).add(candidate);
      }
    }
    return map;
  })();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSave =>
      widget.user.accessRole == AccessRole.counselor &&
      !_saving &&
      _reason.text.trim().length >= 3;

  Future<void> _save() async {
    if (widget.user.accessRole != AccessRole.counselor) {
      setState(() {
        _error = 'Only counselor accounts can be assigned to colleges.';
      });
      return;
    }
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
            ? 'Only the configured super-administrator can change counselor '
                  'college assignments.'
            : (error.message?.trim().isNotEmpty == true
                  ? error.message!
                  : 'Counselor college assignments could not be saved '
                        '(${error.code}).'),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Counselor college assignments could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCounselor = widget.user.accessRole == AccessRole.counselor;
    return AlertDialog(
      title: Text('Counselor college assignments · ${widget.user.displayName}'),
      content: SizedBox(
        width: 540,
        child: !isCounselor
            ? const Text('Only counselor accounts can be assigned to colleges.')
            : StreamBuilder<List<College>>(
                stream: _colleges,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('The college list could not be loaded.');
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final byId = {for (final c in snapshot.data!) c.id: c};
                  // Active colleges are visible; archived ones appear only
                  // while still assigned so they can be removed.
                  final visible = [
                    for (final c in snapshot.data!)
                      if (c.active ||
                          widget.user.assignedCollegeIds.contains(c.id))
                        c,
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
                          _collegeOptionTile(college),
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
        if (isCounselor)
          FilledButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save assignments'),
          ),
      ],
    );
  }

  Widget _collegeOptionTile(College college) {
    final otherOwners = _otherOwnersByCollege[college.id] ?? const [];
    final isCurrentlyHeldByTarget = _selected.contains(college.id);
    final blockedByOther = !isCurrentlyHeldByTarget && otherOwners.isNotEmpty;
    final ownerNames = otherOwners.map((u) => u.displayName).join(', ');
    final subtitleParts = <String>[
      if (college.code.isNotEmpty) 'Code ${college.code}',
      if (otherOwners.isNotEmpty)
        otherOwners.length > 1
            ? 'Conflict: assigned to $ownerNames'
            : 'Assigned to $ownerNames (transfer required)',
    ];
    return InkWell(
      onTap: blockedByOther && !_saving
          ? () => setState(() => _error = collegeAlreadyAssignedMessage)
          : null,
      child: CheckboxListTile(
        dense: true,
        value: _selected.contains(college.id),
        title: Text(
          college.active ? college.name : '${college.name} (archived)',
        ),
        subtitle: subtitleParts.isEmpty
            ? null
            : Text(subtitleParts.join(' • ')),
        onChanged: _saving || blockedByOther
            ? null
            : (checked) => setState(() {
                _error = null;
                if (checked == true) {
                  _selected.add(college.id);
                } else {
                  _selected.remove(college.id);
                }
              }),
      ),
    );
  }
}

/// Authorized college-level dialog for assigning an unassigned college,
/// transferring ownership to another eligible counselor, unassigning, or
/// resolving a duplicate-counselor conflict.
class CollegeCounselorTransferDialog extends StatefulWidget {
  const CollegeCounselorTransferDialog({
    super.key,
    required this.repository,
    required this.college,
    required this.currentOwners,
    required this.eligibleCounselors,
    this.readOnly = false,
  });

  final AdminPortalRepository repository;
  final College college;
  final List<UserModel> currentOwners;
  final List<UserModel> eligibleCounselors;
  final bool readOnly;

  @override
  State<CollegeCounselorTransferDialog> createState() =>
      _CollegeCounselorTransferDialogState();
}

class _CollegeCounselorTransferDialogState
    extends State<CollegeCounselorTransferDialog> {
  static const String _unassignValue = '__unassign__';

  late String? _selectedCounselorId = widget.currentOwners.length == 1
      ? widget.currentOwners.first.id
      : null;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _hasConflict => widget.currentOwners.length > 1;
  bool get _hasOwner => widget.currentOwners.isNotEmpty;

  String get _titlePrefix {
    if (widget.readOnly) return 'College details';
    if (_hasConflict) return 'Resolve conflict';
    if (_hasOwner) return 'Change counselor';
    return 'Assign counselor';
  }

  List<UserModel> get _pickerCandidates {
    final byId = <String, UserModel>{
      for (final c in widget.eligibleCounselors)
        if (isEligibleCounselorAccount(c) &&
            (widget.college.active ||
                widget.currentOwners.any((o) => o.id == c.id)))
          c.id: c,
    };
    return byId.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  bool get _canSubmit {
    if (widget.readOnly || _saving) return false;
    if (_reason.text.trim().length < 3) return false;
    if (_selectedCounselorId == _unassignValue) {
      return widget.currentOwners.isNotEmpty;
    }
    if (_selectedCounselorId == null || _selectedCounselorId!.isEmpty) {
      return false;
    }
    if (widget.currentOwners.length == 1 &&
        widget.currentOwners.first.id == _selectedCounselorId) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final targetId = _selectedCounselorId == _unassignValue
        ? null
        : _selectedCounselorId;
    final expectedOwnerIds = widget.currentOwners.map((u) => u.id).toList()
      ..sort();
    final expectedRevisions = <String, int>{
      for (final o in widget.currentOwners) o.id: o.collegeAssignmentRevision,
    };
    if (targetId != null) {
      final candidate = widget.eligibleCounselors
          .where((u) => u.id == targetId)
          .firstOrNull;
      if (candidate != null) {
        expectedRevisions[targetId] = candidate.collegeAssignmentRevision;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.reassignCollegeCounselor(
        collegeId: widget.college.id,
        toCounselorId: targetId,
        expectedOwnerIds: expectedOwnerIds,
        expectedRevisions: expectedRevisions,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.code == 'permission-denied'
            ? 'Only the configured super-administrator can change counselor '
                  'college assignments.'
            : (error.message?.trim().isNotEmpty == true
                  ? error.message!
                  : 'Counselor college assignment could not be updated '
                        '(${error.code}).'),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Counselor college assignment could not be updated. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _pickerCandidates;
    final currentNames = widget.currentOwners.isEmpty
        ? 'Unassigned'
        : widget.currentOwners.map((u) => u.displayName).join(', ');
    final statusLabel = _hasConflict
        ? 'Conflict'
        : _hasOwner
        ? (widget.college.active ? 'Assigned' : 'Assigned (Inactive)')
        : (widget.college.active ? 'Unassigned' : 'Inactive');

    return AlertDialog(
      title: Text('$_titlePrefix · ${widget.college.name}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.college.code.isEmpty
                    ? 'Status: $statusLabel'
                    : 'Code ${widget.college.code} • Status: $statusLabel',
                style: const TextStyle(
                  color: AdminColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Current counselor: $currentNames',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (_hasConflict) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Multiple counselors are currently assigned to this college. '
                    'Select the single counselor who should keep this college, '
                    'or unassign it, with a documented reason.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (!widget.college.active && !_hasOwner) ...[
                const SizedBox(height: 10),
                const Text(
                  'This college is inactive and cannot receive new counselor assignments.',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13),
                ),
              ],
              if (!widget.readOnly) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue:
                      _selectedCounselorId != null &&
                          (_selectedCounselorId == _unassignValue ||
                              candidates.any(
                                (c) => c.id == _selectedCounselorId,
                              ))
                      ? _selectedCounselorId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Assigned counselor',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final counselor in candidates)
                      DropdownMenuItem(
                        value: counselor.id,
                        child: Text(
                          counselor.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_hasOwner)
                      const DropdownMenuItem(
                        value: _unassignValue,
                        child: Text('Unassign (No counselor)'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _selectedCounselorId = value;
                          _error = null;
                        }),
                ),
                if (candidates.isEmpty && !_hasOwner) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No eligible active counselors are currently available.',
                    style: TextStyle(color: AdminColors.muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reason for change',
                    helperText:
                        'Minimum 3 characters; recorded in audit history.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.readOnly ? 'Close' : 'Cancel'),
        ),
        if (!widget.readOnly)
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(
              _hasConflict
                  ? 'Resolve conflict'
                  : _selectedCounselorId == _unassignValue
                  ? 'Remove counselor'
                  : _hasOwner
                  ? 'Transfer college'
                  : 'Assign counselor',
            ),
          ),
      ],
    );
  }
}
