import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/admin_management_models.dart';
import '../theme/admin_theme.dart';

/// Short routing state for inquiry lists.
class InquiryRoutingBadge extends StatelessWidget {
  const InquiryRoutingBadge({super.key, required this.inquiry});

  final AdminInquiryModel inquiry;

  @override
  Widget build(BuildContext context) {
    final (label, color) = inquiry.isEscalated
        ? ('Escalated', const Color(0xFFFDE2E1))
        : switch (inquiry.routingStatus) {
            InquiryRoutingStatus.routed => ('Routed', const Color(0xFFE3F1E6)),
            InquiryRoutingStatus.needsTriage => (
              'Needs triage',
              const Color(0xFFFFF1D6),
            ),
            InquiryRoutingStatus.unrouted => (
              'Not yet routed',
              AdminColors.surfaceMuted,
            ),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AdminColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String routingReasonLabel(String? reason) => switch (reason) {
  'missing_college' => 'No verified college on the student profile',
  'unverified_profile' => 'Student profile is not verified',
  'unknown_college' => 'College not found in the catalogue',
  'no_eligible_staff' => 'No eligible staff assigned to this college',
  _ => 'Waiting for routing',
};

String _errorText(Object error, String fallback) =>
    error is FirebaseFunctionsException
    ? (error.message?.trim().isNotEmpty == true
          ? error.message!
          : '$fallback (${error.code}).')
    : '$fallback.';

/// Routing details and the actions this session may take on them. Every
/// action is a server callable; the server re-checks authorization.
class InquiryRoutingPanel extends StatelessWidget {
  const InquiryRoutingPanel({
    super.key,
    required this.inquiry,
    required this.repository,
    this.onChanged,
  });

  final AdminInquiryModel inquiry;
  final AdminPortalRepository repository;
  final VoidCallback? onChanged;

  bool get _isAssignee {
    final role = repository.currentAccessRole;
    final uid = repository.currentUserId;
    return !repository.isSuperAdmin &&
        (role == AccessRole.portalStaff || role == AccessRole.counselor) &&
        uid != null &&
        inquiry.assigneeIds.contains(uid);
  }

  String _name(String uid) =>
      inquiry.assigneeLabels[uid]?.trim().isNotEmpty == true
      ? inquiry.assigneeLabels[uid]!
      : 'Staff member';

  @override
  Widget build(BuildContext context) {
    final status = switch (inquiry.routingStatus) {
      InquiryRoutingStatus.routed =>
        'Routed (${inquiry.isManuallyRouted ? 'manual' : 'automatic'})',
      InquiryRoutingStatus.needsTriage =>
        'Needs triage — ${routingReasonLabel(inquiry.routingReason)}',
      InquiryRoutingStatus.unrouted => 'Not yet routed',
    };
    final canEscalate =
        _isAssignee &&
        !inquiry.isEscalated &&
        !inquiry.isTakenOver &&
        inquiry.status != InquiryStatus.resolved;
    final canTakeOver =
        repository.isSuperAdmin &&
        !inquiry.isTakenOver &&
        inquiry.status != InquiryStatus.resolved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Routing', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        _row(
          'College',
          inquiry.collegeId.isEmpty ? 'Not identified' : inquiry.collegeId,
        ),
        _row('Status', status),
        _row(
          'Assigned to',
          inquiry.assigneeIds.isEmpty
              ? 'No one assigned'
              : inquiry.assigneeIds.map(_name).join(', '),
        ),
        if (inquiry.ownerId != null)
          _row('Responsible', _name(inquiry.ownerId!)),
        if (inquiry.isEscalated)
          _row('Escalation', 'Requested — ${inquiry.escalationReason ?? ''}'),
        if (inquiry.isTakenOver)
          _row(
            'Taken over',
            '${inquiry.takeoverByName} — ${inquiry.takeoverReason ?? ''}',
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (canEscalate)
              OutlinedButton.icon(
                onPressed: () => _escalate(context),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Escalate to administrator'),
              ),
            if (canTakeOver)
              OutlinedButton.icon(
                onPressed: () => _takeOver(context),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Take over'),
              ),
            if (repository.isSuperAdmin)
              OutlinedButton.icon(
                onPressed: () => _reassign(context),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Reassign'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );

  Future<void> _escalate(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Escalate to administrator',
        actionLabel: 'Escalate',
        onSubmit: (reason) =>
            repository.escalateInquiry(inquiry.id, reason: reason),
      ),
    );
    if (done == true) onChanged?.call();
  }

  Future<void> _takeOver(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Take over inquiry',
        actionLabel: 'Take over',
        onSubmit: (reason) => repository.takeOverInquiry(
          inquiry.id,
          expectedRevision: inquiry.routingRevision,
          reason: reason,
        ),
      ),
    );
    if (done == true) onChanged?.call();
  }

  Future<void> _reassign(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ReassignDialog(inquiry: inquiry, repository: repository),
    );
    if (done == true) onChanged?.call();
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.actionLabel,
    required this.onSubmit,
  });
  final String title;
  final String actionLabel;
  final Future<void> Function(String reason) onSubmit;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_reason.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _errorText(error, 'The request failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _reason,
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: !_busy && _reason.text.trim().length >= 3 ? _submit : null,
        child: Text(widget.actionLabel),
      ),
    ],
  );
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({required this.inquiry, required this.repository});
  final AdminInquiryModel inquiry;
  final AdminPortalRepository repository;
  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  late final Set<String> _selected = {...widget.inquiry.assigneeIds};
  late final Stream<List<UserModel>> _users = widget.repository.watchUsers();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Mirrors the server's eligibility gate so ineligible accounts are not offered.
  static bool _eligible(UserModel user) =>
      (user.accessRole == AccessRole.portalStaff ||
          user.accessRole == AccessRole.counselor) &&
      (user.staffAccountStatus == null ||
          user.staffAccountStatus == StaffAccountStatus.approved) &&
      (user.accountStatus == null || user.accountStatus == 'active');

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.reassignInquiry(
        widget.inquiry.id,
        assigneeIds: (_selected.toList()..sort()),
        expectedRevision: widget.inquiry.routingRevision,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = _errorText(error, 'The inquiry could not be reassigned'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reassign inquiry'),
    content: SizedBox(
      width: 520,
      child: StreamBuilder<List<UserModel>>(
        stream: _users,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Staff accounts could not be loaded.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final staff = snapshot.data!.where(_eligible).toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.inquiry.collegeId.isEmpty
                      ? 'College not identified. Any eligible staff member may be assigned.'
                      : 'College ${widget.inquiry.collegeId}. Staff outside this college are allowed and recorded in the audit log.',
                  style: const TextStyle(color: AdminColors.muted),
                ),
                for (final user in staff)
                  CheckboxListTile(
                    dense: true,
                    value: _selected.contains(user.id),
                    title: Text(user.displayName),
                    subtitle: Text(
                      user.assignedCollegeIds.contains(widget.inquiry.collegeId)
                          ? 'Serves this college'
                          : 'Other college',
                    ),
                    onChanged: _busy
                        ? null
                        : (checked) => setState(
                            () => checked == true
                                ? _selected.add(user.id)
                                : _selected.remove(user.id),
                          ),
                  ),
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reason for change',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
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
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            !_busy && _selected.isNotEmpty && _reason.text.trim().length >= 3
            ? _save
            : null,
        child: const Text('Save assignment'),
      ),
    ],
  );
}

/// Super-administrator action that routes inquiries created before routing.
class InquiryBackfillButton extends StatefulWidget {
  const InquiryBackfillButton({super.key, required this.repository});
  final AdminPortalRepository repository;
  @override
  State<InquiryBackfillButton> createState() => _InquiryBackfillButtonState();
}

class _InquiryBackfillButtonState extends State<InquiryBackfillButton> {
  bool _busy = false;
  String? _message;

  /// Where the previous batch stopped; null starts a fresh pass.
  String? _cursor;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.repository.routeExistingInquiries(
        cursor: _cursor,
      );
      if (mounted) {
        setState(() {
          final summary =
              '${result.routed} routed, ${result.needsTriage} need triage.';
          if (result.done) {
            _cursor = null;
            _message = '$summary All existing inquiries have been checked.';
          } else {
            _cursor = result.nextCursor;
            _message = '$summary More inquiries remain.';
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _message = _errorText(error, 'Routing existing inquiries failed'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isSuperAdmin) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _run,
          icon: const Icon(Icons.alt_route),
          label: Text(
            _cursor == null ? 'Route existing inquiries' : 'Continue routing',
          ),
        ),
        if (_message != null) Text(_message!),
      ],
    );
  }
}
