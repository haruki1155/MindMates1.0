import 'package:flutter/material.dart';

import '../theme/admin_theme.dart';

enum AdminStatusDomain {
  appointment,
  inquiry,
  account,
  assessment,
  appointmentType,
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
    AdminStatusDomain.assessment => _resolveAssessment(key, raw),
    AdminStatusDomain.appointmentType => _resolveAppointmentType(key),
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
      'stable' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.green,
        label: 'Supported',
        icon: Icons.check_circle_outline,
      ),
      'mostlysupported' ||
      'generallysteady' ||
      'mild' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.blue,
        label: key == 'mild' ? 'Mild' : 'Mostly supported',
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
      'watchful' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.amber,
        label: 'Some areas need attention',
        icon: Icons.warning_amber_outlined,
      ),
      'high' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.red,
        label: 'High',
        icon: Icons.priority_high_rounded,
      ),
      'veryhigh' || 'severe' || 'extremelysevere' =>
        AdminStatusPresentation.fromTone(
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
      'atrisk' => AdminStatusPresentation.fromTone(
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
      'resultunavailable' ||
      'statusunavailable' ||
      'notclassified' ||
      '' => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.neutral,
        label: 'Status unavailable',
        icon: Icons.help_outline,
      ),
      _ => AdminStatusPresentation.fromTone(
        tone: AdminSemanticTone.neutral,
        label: raw.replaceAll('_', ' '),
        icon: Icons.help_outline,
      ),
    };
