import 'package:flutter/material.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../domain/inquiry_sla.dart';
import '../theme/admin_theme.dart';

String _failure(Object error, String fallback) =>
    FirebaseErrorMessage.describe(error, fallback: '$fallback.');

String _lastAction(AdminInquiryModel inquiry) {
  if (inquiry.lastResponseByName != null) {
    return 'Last reply by ${inquiry.lastResponseByName}';
  }
  if (inquiry.isAcknowledged) return 'Receipt confirmed, no reply';
  return 'No action yet';
}

/// Super-administrator view of inquiries past the response target. It is a
/// projection of inquiries the super-admin already reads; it grants nothing.
class InquiryOverduePanel extends StatelessWidget {
  const InquiryOverduePanel({
    super.key,
    required this.repository,
    required this.inquiries,
    required this.onOpen,
    this.now = DateTime.now,
  });

  final AdminPortalRepository repository;
  final List<AdminInquiryModel> inquiries;
  final ValueChanged<AdminInquiryModel> onOpen;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    if (!repository.isSuperAdmin) return const SizedBox.shrink();
    return StreamBuilder<InquirySla>(
      stream: repository.watchInquirySla(),
      builder: (context, snapshot) {
        final sla = snapshot.data ?? const InquirySla(hours: null);
        final current = now();
        final overdue = sla.overdue(inquiries, current);
        // A Material surface (not a decorated box) so row ink is visible.
        return Material(
          color: AdminColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AdminColors.border),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      sla.isConfigured
                          ? 'Unanswered past target: ${overdue.length} overdue'
                          : 'Unanswered inquiries',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    _TargetSelector(repository: repository, hours: sla.hours),
                  ],
                ),
                const SizedBox(height: 8),
                if (!sla.isConfigured)
                  const Text(
                    'Set a response target to see overdue inquiries. Nothing is '
                    'flagged until PACC chooses one.',
                    style: TextStyle(color: AdminColors.muted),
                  )
                else if (overdue.isEmpty)
                  const Text(
                    'No inquiry is past the response target.',
                    style: TextStyle(color: AdminColors.muted),
                  )
                else
                  for (final inquiry in overdue)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => onOpen(inquiry),
                      title: Text(inquiry.subject),
                      subtitle: Text(
                        [
                          inquiry.collegeId.isEmpty
                              ? 'College not identified'
                              : 'College assigned',
                          inquiry.assigneeIds.isEmpty
                              ? 'No one assigned'
                              : inquiry.assigneeIds
                                    .map(
                                      (id) =>
                                          inquiry.assigneeLabels[id] ??
                                          'Staff member',
                                    )
                                    .join(', '),
                          '${sla.ageOf(inquiry, current).inHours} h old',
                          _lastAction(inquiry),
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TargetSelector extends StatefulWidget {
  const _TargetSelector({required this.repository, required this.hours});
  final AdminPortalRepository repository;
  final int? hours;
  @override
  State<_TargetSelector> createState() => _TargetSelectorState();
}

class _TargetSelectorState extends State<_TargetSelector> {
  bool _saving = false;
  String? _error;

  Future<void> _save(int? hours) async {
    if (hours == null || hours == widget.hours) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.setInquirySla(hours);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _failure(error, 'The response target was not saved'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text('Response target:'),
      DropdownButton<int>(
        value: widget.hours,
        hint: const Text('Not set'),
        onChanged: _saving ? null : _save,
        items: [
          for (final hours in inquirySlaHourOptions)
            DropdownMenuItem(value: hours, child: Text('$hours hours')),
        ],
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

/// Authored replies on an inquiry and, for those allowed to act, a composer.
/// The server re-checks authorization, revision and resolution.
class InquiryReplyThread extends StatefulWidget {
  const InquiryReplyThread({
    super.key,
    required this.inquiry,
    required this.repository,
  });

  final AdminInquiryModel inquiry;
  final AdminPortalRepository repository;

  @override
  State<InquiryReplyThread> createState() => _InquiryReplyThreadState();
}

class _InquiryReplyThreadState extends State<InquiryReplyThread> {
  final _draft = TextEditingController();
  late final Stream<List<InquiryReply>> _replies = _isOperationalOnly
      ? Stream<List<InquiryReply>>.value(const <InquiryReply>[])
      : widget.repository.watchInquiryReplies(widget.inquiry.id);

  /// Kept until the reply is confirmed, so a retry cannot post it twice.
  String? _requestId;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  bool get _isOperationalOnly =>
      widget.inquiry.isOperationalProjection ||
      (!widget.repository.isSuperAdmin &&
          widget.repository.currentAccessRole == AccessRole.portalStaff);

  bool get _canReply {
    if (_isOperationalOnly) return false;
    final inquiry = widget.inquiry;
    if (inquiry.status == InquiryStatus.resolved) return false;
    if (widget.repository.isSuperAdmin) return true;
    final role = widget.repository.currentAccessRole;
    final uid = widget.repository.currentUserId;
    return role == AccessRole.counselor &&
        uid != null &&
        inquiry.assigneeIds.contains(uid) &&
        !inquiry.isTakenOver;
  }

  Future<void> _send() async {
    _requestId ??= newInquiryRequestId();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.replyToInquiry(
        widget.inquiry.id,
        message: _draft.text.trim(),
        expectedRevision: widget.inquiry.routingRevision,
        requestId: _requestId!,
      );
      if (!mounted) return;
      setState(() {
        _draft.clear();
        _requestId = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _failure(error, 'The reply was not sent'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isOperationalOnly) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Replies', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        StreamBuilder<List<InquiryReply>>(
          stream: _replies,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Replies could not be loaded.');
            }
            final replies = snapshot.data ?? const <InquiryReply>[];
            if (replies.isEmpty) {
              return const Text(
                'No reply has been sent yet.',
                style: TextStyle(color: AdminColors.muted),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reply in replies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${reply.authorName}${reply.isAdministrator ? ' (administrator)' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(reply.message),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        if (widget.inquiry.isTakenOver && !widget.repository.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${widget.inquiry.takeoverByName} took over this inquiry. '
              'You can still read it but cannot reply.',
              style: const TextStyle(color: AdminColors.muted),
            ),
          ),
        if (_canReply) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _draft,
            enabled: !_sending,
            minLines: 2,
            maxLines: 6,
            maxLength: 2000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Reply to the student',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: !_sending && _draft.text.trim().isNotEmpty
                ? _send
                : null,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send reply'),
          ),
        ],
      ],
    );
  }
}
