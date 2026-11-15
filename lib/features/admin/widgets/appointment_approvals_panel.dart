import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/appointment_approvals.dart';
import '../theme/admin_theme.dart';

/// Counselors: "My College's Approvals" (appointments for students in the
/// colleges they serve). Super-administrator: "Approval exceptions"
/// (appointments whose college cannot be confirmed or has no counselor).
/// The list comes from the server; every action is re-authorised there.
class AppointmentApprovalsPanel extends StatefulWidget {
  const AppointmentApprovalsPanel({
    super.key,
    required this.repository,
    required this.appointments,
    required this.onOpen,
  });

  final AdminPortalRepository repository;

  /// Appointments the page already streams; used for names and to open one.
  final List<AppointmentModel> appointments;
  final ValueChanged<AppointmentModel> onOpen;

  @override
  State<AppointmentApprovalsPanel> createState() =>
      _AppointmentApprovalsPanelState();
}

class _AppointmentApprovalsPanelState extends State<AppointmentApprovalsPanel> {
  Future<List<AppointmentApprovalItem>>? _items;

  bool get _isCounselor =>
      widget.repository.currentAccessRole == AccessRole.counselor;
  bool get _isSuperAdmin =>
      widget.repository.currentAccessRole == AccessRole.admin &&
      widget.repository.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    if (_isCounselor || _isSuperAdmin) {
      _items = widget.repository.listAppointmentApprovals();
    }
  }

  void _load() {
    final next = widget.repository.listAppointmentApprovals();
    setState(() {
      _items = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCounselor && !_isSuperAdmin) return const SizedBox.shrink();
    final title = _isCounselor
        ? "My College's Approvals"
        : 'Approval exceptions';
    return Material(
      color: AdminColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<AppointmentApprovalItem>>(
          future: _items,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <AppointmentApprovalItem>[];
            final byId = {for (final a in widget.appointments) a.id: a};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        snapshot.hasData ? '$title (${items.length})' : title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh approvals',
                      onPressed:
                          snapshot.connectionState == ConnectionState.waiting
                          ? null
                          : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_isSuperAdmin)
                  const Text(
                    'Appointments whose college cannot be confirmed or has no '
                    'eligible counselor. Acting on an appointment that a '
                    'counselor is assigned to requires an exception reason.',
                    style: TextStyle(color: AdminColors.muted),
                  ),
                const SizedBox(height: 8),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  const Text(
                    'Approvals could not be loaded. Refresh to try again.',
                  )
                else if (items.isEmpty)
                  const Text(
                    'No appointments are waiting for a decision.',
                    style: TextStyle(color: AdminColors.muted),
                  )
                else
                  for (final item in items)
                    _ApprovalRow(
                      item: item,
                      appointment: byId[item.appointmentId],
                      showReason: _isSuperAdmin,
                      onOpen: widget.onOpen,
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({
    required this.item,
    required this.appointment,
    required this.showReason,
    required this.onOpen,
  });

  final AppointmentApprovalItem item;
  final AppointmentModel? appointment;
  final bool showReason;
  final ValueChanged<AppointmentModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final when = item.scheduledAt?.toLocal();
    final details = [
      if (when != null)
        '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
      if (item.pendingStudentProposal) 'Student proposed a new time',
      if (item.collegeId.isNotEmpty) 'College ${item.collegeId}',
      if (showReason) item.reasonLabel,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(appointment?.fullName ?? 'Appointment ${item.appointmentId}'),
      subtitle: Text(details),
      trailing: OutlinedButton(
        onPressed: appointment == null ? null : () => onOpen(appointment!),
        child: const Text('Review'),
      ),
    );
  }
}
