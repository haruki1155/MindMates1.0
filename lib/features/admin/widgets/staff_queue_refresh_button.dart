import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';

/// Manually requests a privileged refresh of the staff-safe schedule only.
/// The user sees failures instead of an apparently empty calendar.
class StaffQueueRefreshButton extends StatefulWidget {
  const StaffQueueRefreshButton({super.key, required this.repository});

  final AdminPortalRepository repository;

  @override
  State<StaffQueueRefreshButton> createState() =>
      _StaffQueueRefreshButtonState();
}

class _StaffQueueRefreshButtonState extends State<StaffQueueRefreshButton> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final count = await widget.repository.refreshPortalAppointmentQueue();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Refresh completed for $count source appointments. '
          'Staff schedule records will update when the queue syncs.',
        ),
      ));
    } catch (error) {
      if (!mounted) return;
      final detail = error is FirebaseFunctionsException
          ? ' (${error.code})'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Could not refresh staff schedules$detail. '
          'Verify the staging Function deployment and Staff account access.',
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _busy ? null : _refresh,
    icon: _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.sync),
    label: Text(_busy ? 'Refreshing…' : 'Refresh schedules'),
  );
}
