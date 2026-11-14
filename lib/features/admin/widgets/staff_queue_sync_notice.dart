import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';

/// Reports a failed staff-queue catch-up as a backend problem, so an empty
/// `appointment_queue` is not mistaken for "no appointments exist".
///
/// Renders nothing while the last catch-up succeeded or has not run.
class StaffQueueSyncNotice extends StatelessWidget {
  const StaffQueueSyncNotice({super.key, required this.repository});

  final AdminPortalRepository repository;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: repository.portalQueueSyncError,
    builder: (context, code, _) {
      if (code == null) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminColors.accentFaint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The staff schedule sync service is unavailable ($code). '
                'Staff schedules cannot populate until the '
                'refreshPortalAppointmentQueue and syncPortalAppointmentQueue '
                'Functions are deployed and this account is approved. '
                'Appointments may exist that are not shown here.',
              ),
            ),
          ],
        ),
      );
    },
  );
}
