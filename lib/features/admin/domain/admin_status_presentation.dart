import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import '../theme/admin_theme.dart';
import 'backup_job.dart';

enum AdminStatusDomain {
  appointment,
  inquiry,
  account,
  assessment,
  appointmentType,
  backup,
  followUp,
}

enum AdminSemanticTone { amber, blue, green, violet, red, neutral }

/// Accessible semantic presentation for a stored status value.
///
/// Presentation-only: never computes clinical scores or alters stored states.
class AdminStatusPresentation {
  const AdminStatusPresentation({
    required this.tone,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final AdminSemanticTone tone;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;

  factory AdminStatusPresentation.fromTone({
    required AdminSemanticTone tone,
    required String label,
    required IconData icon,
  }) => switch (tone) {
    AdminSemanticTone.amber => AdminStatusPresentation(
      tone: tone,
      label: label,
      icon: icon,
      backgroundColor: AdminColors.amberBg,
      foregroundColor: AdminColors.amberFg,
      borderColor: AdminColors.amberBorder,
    ),
    AdminSemanticTone.blue => AdminStatusPresentation(
      tone: tone,
      label: label,
      icon: icon,
      backgroundColor: AdminColors.blueBg,
      foregroundColor: AdminColors.blueFg,
      borderColor: AdminColors.blueBorder,
    ),
    AdminSemanticTone.green => AdminStatusPresentation(
      tone: tone,
      label: label,
      icon: icon,
      backgroundColor: AdminColors.greenBg,
      foregroundColor: AdminColors.greenFg,
      borderColor: AdminColors.greenBorder,
    ),
    AdminSemanticTone.violet => AdminStatusPresentation(
      tone: tone,
      label: label,
      icon: icon,
      backgroundColor: AdminColors.violetBg,
      foregroundColor: AdminColors.violetFg,
      borderColor: AdminColors.violetBorder,
    ),
    AdminSemanticTone.red => AdminStatusPresentation(
      tone: tone,
      label: label,
      icon: icon,
      backgroundColor: AdminColors.redBg,
      foregroundColor: AdminColors.redFg,
      borderColor: AdminColors.redBorder,
    ),
    AdminSemanticTone.neutral => AdminStatusPresentation(
      tone: tone,
      label: label,
      icon: icon,
      backgroundColor: AdminColors.neutralBg,
      foregroundColor: AdminColors.neutralFg,
      borderColor: AdminColors.neutralBorder,
    ),
  };
}

String _normalizeKey(String? raw) =>
    (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

String _normalizeAssessmentKey(String? raw) =>
    (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

AdminStatusPresentation resolveAdminStatus(
  AdminStatusDomain domain,
  String? rawStatus, {
  String? labelOverride,
}) {
  final raw = (rawStatus ?? '').trim();
  final key = _normalizeKey(raw);

  final resolved = switch (domain) {
    AdminStatusDomain.appointment => _resolveAppointment(key),
    AdminStatusDomain.inquiry => _resolveInquiry(key),
    AdminStatusDomain.account => _resolveAccount(key),
    AdminStatusDomain.assessment => _resolveAssessment(
      _normalizeAssessmentKey(raw),
      raw,
    ),
    AdminStatusDomain.appointmentType => _resolveAppointmentType(key),
    AdminStatusDomain.backup => _resolveBackup(key),
    AdminStatusDomain.followUp => _resolveFollowUp(key),
  };

  if (labelOverride != null && labelOverride.trim().isNotEmpty) {
    return AdminStatusPresentation.fromTone(
      tone: resolved.tone,
      label: labelOverride.trim(),
      icon: resolved.icon,
    );
  }
  return resolved;
}

/// Returns whether a completed backup job's retention window has ended.
bool isBackupJobExpired(BackupJob job, {DateTime? now}) {
  if (job.status != BackupJobStatus.completed) return false;
  if (job.verification == BackupVerificationStatus.missing) return false;
  final expiresAt = job.expiresAt;
  if (expiresAt == null) return false;
  return !expiresAt.isAfter(now ?? DateTime.now());
}

/// Maps a [BackupJob] and current timestamp into a semantic badge presentation.
AdminStatusPresentation resolveBackupJobStatus(BackupJob job, {DateTime? now}) {
  if (isBackupJobExpired(job, now: now)) {
    return resolveAdminStatus(AdminStatusDomain.backup, 'expired');
  }
  return switch (job.status) {
    BackupJobStatus.running => resolveAdminStatus(
      AdminStatusDomain.backup,
      'running',
    ),
    BackupJobStatus.completed => switch (job.verification) {
      BackupVerificationStatus.verified => resolveAdminStatus(
        AdminStatusDomain.backup,
        'verified',
      ),
      BackupVerificationStatus.pending => resolveAdminStatus(
        AdminStatusDomain.backup,
        'pending',
      ),
      BackupVerificationStatus.missing => resolveAdminStatus(
        AdminStatusDomain.backup,
        'output_missing',
      ),
    },
    BackupJobStatus.failed => resolveAdminStatus(
      AdminStatusDomain.backup,
      job.verification == BackupVerificationStatus.missing
          ? 'output_missing'
          : 'failed',
    ),
  };
}

AdminStatusPresentation _resolveBackup(String key) => switch (key) {
  'running' || 'inprogress' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.blue,
    label: 'Running',
    icon: Icons.sync_outlined,
  ),
  'verified' || 'successful' || 'completed' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.green,
    label: 'Successful · Verified',
    icon: Icons.check_circle_outline,
  ),
  'pending' || 'pendingverification' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.amber,
    label: 'Pending verification',
    icon: Icons.hourglass_top_outlined,
  ),
  'outputmissing' ||
  'missing' ||
  'failedoutputmissing' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.red,
    label: 'Failed · Output missing',
    icon: Icons.error_outline,
  ),
  'failed' || 'error' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.red,
    label: 'Failed',
    icon: Icons.error_outline,
  ),
  'expired' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Expired',
    icon: Icons.timer_off_outlined,
  ),
  _ => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Unknown',
    icon: Icons.help_outline,
  ),
};

AdminStatusPresentation _resolveAppointment(String key) => switch (key) {
  'pending' ||
  'requested' ||
  'legacyrequested' ||
  'awaitingreview' ||
  'needsreview' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.amber,
    label: 'Pending review',
    icon: Icons.schedule_outlined,
  ),
  'rescheduleproposed' ||
  'reschedulerequired' ||
  'rescheduled' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.amber,
    label: 'Reschedule proposed',
    icon: Icons.update_outlined,
  ),
  'confirmed' || 'approved' || 'scheduled' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.blue,
    label: 'Confirmed',
    icon: Icons.event_available_outlined,
  ),
  'completed' || 'complete' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.green,
    label: 'Completed',
    icon: Icons.check_circle_outline,
  ),
  'cancelled' || 'canceled' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Cancelled',
    icon: Icons.cancel_outlined,
  ),
  'declined' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Declined',
    icon: Icons.cancel_outlined,
  ),
  'noshow' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.red,
    label: 'No-show',
    icon: Icons.person_off_outlined,
  ),
  'expired' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Expired',
    icon: Icons.timer_off_outlined,
  ),
  _ => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Unknown',
    icon: Icons.help_outline,
  ),
};

AdminStatusPresentation _resolveInquiry(String key) => switch (key) {
  'pending' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.amber,
    label: 'Pending',
    icon: Icons.hourglass_top_outlined,
  ),
  'inprogress' || 'acknowledged' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.blue,
    label: 'In progress',
    icon: Icons.sync_outlined,
  ),
  'resolved' || 'closed' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.green,
    label: 'Resolved',
    icon: Icons.check_circle_outline,
  ),
  _ => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Unknown',
    icon: Icons.help_outline,
  ),
};

AdminStatusPresentation _resolveAccount(String key) => switch (key) {
  'active' || 'enabled' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.green,
    label: 'Active',
    icon: Icons.check_circle_outline,
  ),
  'pending' ||
  'invited' ||
  'pendinginvitation' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.amber,
    label: 'Pending invitation',
    icon: Icons.mail_outline,
  ),
  'disabled' || 'inactive' || 'suspended' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Inactive',
    icon: Icons.block_outlined,
  ),
  _ => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Unknown',
    icon: Icons.help_outline,
  ),
};

AdminStatusPresentation _resolveAppointmentType(String key) => switch (key) {
  'followup' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.violet,
    label: 'Follow-up',
    icon: Icons.event_repeat_outlined,
  ),
  'initial' || 'first' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.blue,
    label: 'Initial',
    icon: Icons.event_note_outlined,
  ),
  _ => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Standard',
    icon: Icons.event_outlined,
  ),
};

AdminStatusPresentation _resolveAssessment(String key, String raw) =>
    switch (key) {
      'low' || 'normal' || 'healthy' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.green,
        label: key == 'low'
            ? 'Low'
            : key == 'normal'
            ? 'Normal'
            : 'Healthy',
        icon: Icons.check_circle_outline,
      ),
      'supported' ||
      'generallysupported' ||
      'wellbeingsupported' ||
      'stable' ||
      'thriving' ||
      'thrivingpatterns' ||
      'supportedatpresent' ||
      'wellbeingappearsgenerallysupported' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.green,
        label: 'Supported',
        icon: Icons.check_circle_outline,
      ),
      'mild' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.blue,
        label: 'Mild',
        icon: Icons.info_outline,
      ),
      'mostlysupported' ||
      'generallysteady' ||
      'balancedpatterns' ||
      'mostlysupportedwithanareatoexplore' ||
      'mostlysupportedsomeareastoexplore' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.blue,
        label: 'Mostly supported',
        icon: Icons.info_outline,
      ),
      'moderate' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.amber,
        label: 'Moderate',
        icon: Icons.warning_amber_outlined,
      ),
      'somestrain' ||
      'someareasneedattention' ||
      'needsattention' ||
      'needsimprovement' ||
      'watchful' ||
      'areastostrengthen' ||
      'somestrainindicated' ||
      'someareasmaybenefitfromattention' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.amber,
        label: 'Some areas need attention',
        icon: Icons.warning_amber_outlined,
      ),
      'high' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.red,
        label: 'High',
        icon: Icons.priority_high_rounded,
      ),
      'veryhigh' ||
      'severe' ||
      'extremelysevere' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.red,
        label: key == 'veryhigh'
            ? 'Very high'
            : key == 'severe'
            ? 'Severe'
            : 'Extremely severe',
        icon: Icons.priority_high_rounded,
      ),
      'supportmayhelp' ||
      'elevated' ||
      'highsupport' ||
      'prioritysupport' ||
      'atrisk' ||
      'supportmaybeuseful' ||
      'supportmaybehelpful' ||
      'supportmaybehelpfulrightnow' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.red,
        label: 'Support may help',
        icon: Icons.priority_high_rounded,
      ),
      'completed' || 'submitted' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.violet,
        label: key == 'completed' ? 'Completed' : 'Submitted',
        icon: Icons.assignment_turned_in_outlined,
      ),
      'insufficientresponses' ||
      'insufficient' ||
      'moreresponsesneeded' ||
      'moreresponsesareneededforacompleteprofile' =>
        AdminStatusPresentation.fromTone(
          tone: AdminSemanticTone.neutral,
          label: 'Insufficient responses',
          icon: Icons.help_outline,
        ),
      'resultunavailable' ||
      'statusunavailable' ||
      'notclassified' ||
      '' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.neutral,
        label: 'Result unavailable',
        icon: Icons.help_outline,
      ),
      _ => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.neutral,
        label: raw.replaceAll('_', ' '),
        icon: Icons.help_outline,
      ),
    };

/// Presentation details for a counselor follow-up offer or linked follow-up booking.
class FollowUpOfferPresentation {
  const FollowUpOfferPresentation({
    required this.presentation,
    required this.supportingText,
    required this.isAwaitingClientResponse,
  });

  final AdminStatusPresentation presentation;
  final String supportingText;
  final bool isAwaitingClientResponse;
}

/// Resolves the semantic badge, supporting copy, and pending state for a
/// post-session follow-up record without mutating stored appointment data.
FollowUpOfferPresentation resolveFollowUpOfferStatus(
  AppointmentModel appointment, {
  AppointmentModel? linkedAppointment,
}) {
  if (linkedAppointment != null) {
    return _followUpFromAppointmentStatus(linkedAppointment.lifecycleStatus);
  }
  if (appointment.hasAvailableFollowUpOffer) {
    return FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'offered'),
      supportingText:
          'Pending follow-up offer — client has not booked a session yet.',
      isAwaitingClientResponse: true,
    );
  }

  final key = _normalizeKey(appointment.followUpStatus);
  if (key == 'offered') {
    return switch (appointment.lifecycleStatus) {
      AppointmentStatus.declined ||
      AppointmentStatus.cancelled ||
      AppointmentStatus.expired ||
      AppointmentStatus.noShow => _followUpFromAppointmentStatus(
        appointment.lifecycleStatus,
      ),
      _ => FollowUpOfferPresentation(
        presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'none'),
        supportingText: 'Follow-up offer is not active.',
        isAwaitingClientResponse: false,
      ),
    };
  }

  return switch (key) {
    'booked' => FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'booked'),
      supportingText: 'Client booked a follow-up session.',
      isAwaitingClientResponse: false,
    ),
    'completed' || 'complete' => FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'completed'),
      supportingText: 'Follow-up session completed.',
      isAwaitingClientResponse: false,
    ),
    'declined' => FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'declined'),
      supportingText: 'Follow-up session was declined.',
      isAwaitingClientResponse: false,
    ),
    'cancelled' || 'canceled' => FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'cancelled'),
      supportingText: 'Follow-up session was cancelled.',
      isAwaitingClientResponse: false,
    ),
    'expired' => FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'expired'),
      supportingText: 'Follow-up offer or booking expired.',
      isAwaitingClientResponse: false,
    ),
    'noshow' => FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'no_show'),
      supportingText: 'Client did not attend the follow-up session.',
      isAwaitingClientResponse: false,
    ),
    _ => FollowUpOfferPresentation(
      presentation: resolveAdminStatus(AdminStatusDomain.followUp, key),
      supportingText: 'No active follow-up offer.',
      isAwaitingClientResponse: false,
    ),
  };
}

FollowUpOfferPresentation _followUpFromAppointmentStatus(
  AppointmentStatus status,
) => switch (status) {
  AppointmentStatus.completed => FollowUpOfferPresentation(
    presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'completed'),
    supportingText: 'Follow-up session completed.',
    isAwaitingClientResponse: false,
  ),
  AppointmentStatus.declined => FollowUpOfferPresentation(
    presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'declined'),
    supportingText: 'Follow-up session was declined.',
    isAwaitingClientResponse: false,
  ),
  AppointmentStatus.cancelled => FollowUpOfferPresentation(
    presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'cancelled'),
    supportingText: 'Follow-up session was cancelled.',
    isAwaitingClientResponse: false,
  ),
  AppointmentStatus.expired => FollowUpOfferPresentation(
    presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'expired'),
    supportingText: 'Follow-up offer or booking expired.',
    isAwaitingClientResponse: false,
  ),
  AppointmentStatus.noShow => FollowUpOfferPresentation(
    presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'no_show'),
    supportingText: 'Client did not attend the follow-up session.',
    isAwaitingClientResponse: false,
  ),
  AppointmentStatus.confirmed => FollowUpOfferPresentation(
    presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'booked'),
    supportingText: 'Follow-up session booked and confirmed.',
    isAwaitingClientResponse: false,
  ),
  AppointmentStatus.requested ||
  AppointmentStatus.legacyRequested ||
  AppointmentStatus.rescheduleProposed ||
  AppointmentStatus.unknown => FollowUpOfferPresentation(
    presentation: resolveAdminStatus(AdminStatusDomain.followUp, 'booked'),
    supportingText: 'Client booked a follow-up session.',
    isAwaitingClientResponse: false,
  ),
};

AdminStatusPresentation _resolveFollowUp(String key) => switch (key) {
  'offered' ||
  'awaitingclientresponse' ||
  'followupoffered' ||
  'pending' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.amber,
    label: 'Awaiting Client Response',
    icon: Icons.hourglass_top_outlined,
  ),
  'booked' ||
  'requested' ||
  'legacyrequested' ||
  'rescheduleproposed' ||
  'confirmed' ||
  'approved' ||
  'scheduled' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.blue,
    label: 'Booked',
    icon: Icons.event_available_outlined,
  ),
  'completed' || 'complete' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.green,
    label: 'Completed',
    icon: Icons.check_circle_outline,
  ),
  'declined' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Declined',
    icon: Icons.cancel_outlined,
  ),
  'cancelled' || 'canceled' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Cancelled',
    icon: Icons.cancel_outlined,
  ),
  'expired' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Expired',
    icon: Icons.timer_off_outlined,
  ),
  'noshow' => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.red,
    label: 'No-show',
    icon: Icons.person_off_outlined,
  ),
  _ => AdminStatusPresentation.fromTone(
    tone: AdminSemanticTone.neutral,
    label: 'Unknown',
    icon: Icons.help_outline,
  ),
};
