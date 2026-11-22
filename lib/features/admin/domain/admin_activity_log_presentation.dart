import 'package:flutter/material.dart';

import 'admin_dashboard_analytics.dart';
import 'admin_management_models.dart';
import 'admin_status_presentation.dart';

enum ActivityActorRoleFilter {
  all('', 'All roles'),
  admin('admin', 'Administrator'),
  counselor('counselor', 'Counselor'),
  portalStaff('portalStaff', 'PAACC Staff');

  const ActivityActorRoleFilter(this.code, this.label);
  final String code;
  final String label;
}

enum ActivityDateRangePreset {
  last30Days('Last 30 days'),
  today('Today'),
  last7Days('Last 7 days'),
  thisMonth('This month'),
  allTime('All time'),
  custom('Custom range');

  const ActivityDateRangePreset(this.label);
  final String label;
}

class ActivityCategoryOption {
  const ActivityCategoryOption(this.code, this.label);
  final String code;
  final String label;
}

const List<ActivityCategoryOption> kActivityCategoryOptions = [
  ActivityCategoryOption('', 'All categories'),
  ActivityCategoryOption('AUTHENTICATION', 'Authentication'),
  ActivityCategoryOption('USER_MANAGEMENT', 'User Management'),
  ActivityCategoryOption('PROFILING', 'Profiling & Roster'),
  ActivityCategoryOption('APPOINTMENTS', 'Appointments'),
  ActivityCategoryOption('SCHEDULE', 'Schedule & Availability'),
  ActivityCategoryOption('INQUIRIES', 'Inquiries'),
  ActivityCategoryOption('REPORTS', 'Reports'),
  ActivityCategoryOption('SYSTEM', 'System & Backups'),
  ActivityCategoryOption('SECURITY', 'Security & Clinical Access'),
];

final RegExp _sensitiveAuditMetadataKeyPattern = RegExp(
  r'password|token|secret|authcode|activationcode|passcode|verificationcode|otp|pin|message|reply|remark|concern|content|base64|email|phone|contact|personal|studentname|fullname',
  caseSensitive: false,
);

/// Normalizes stored `actorRoleSnapshot` / `actorAccessRole` into one of the
/// three monitored staff roles (`admin`, `counselor`, `portalStaff`) or `other`
/// (e.g., `appUser` / `student`).
String normalizeAuditActorRole(String rawRole) {
  final key = rawRole.trim().toLowerCase();
  if (key.isEmpty) {
    // Legacy admin-only audit records without actorRoleSnapshot were written by
    // super-admin callables.
    return 'admin';
  }
  return switch (key) {
    'admin' || 'super_admin' || 'administrator' => 'admin',
    'counselor' || 'counsellor' => 'counselor',
    'portalstaff' ||
    'portal_staff' ||
    'staff' ||
    'pacc_staff' ||
    'paacc_staff' => 'portalStaff',
    _ => 'other',
  };
}

String auditActorRoleLabel(String rawRole) =>
    switch (normalizeAuditActorRole(rawRole)) {
      'admin' => 'Administrator',
      'counselor' => 'Counselor',
      'portalStaff' => 'PAACC Staff',
      _ => 'Portal User',
    };

AdminSemanticTone auditActorRoleTone(String rawRole) =>
    switch (normalizeAuditActorRole(rawRole)) {
      'admin' => AdminSemanticTone.violet,
      'counselor' => AdminSemanticTone.blue,
      'portalStaff' => AdminSemanticTone.green,
      _ => AdminSemanticTone.neutral,
    };

String auditCategoryLabel(String category) =>
    switch (category.trim().toUpperCase()) {
      'AUTHENTICATION' => 'Authentication',
      'USER_MANAGEMENT' => 'User Management',
      'PROFILING' => 'Profiling & Roster',
      'APPOINTMENTS' => 'Appointments',
      'SCHEDULE' => 'Schedule & Availability',
      'INQUIRIES' => 'Inquiries',
      'REPORTS' => 'Reports',
      'SYSTEM' => 'System & Backups',
      'SECURITY' => 'Security & Clinical Access',
      _ => category.trim().isEmpty ? 'User Management' : category.trim(),
    };

String auditActionLabel(String action) {
  final trimmed = action.trim();
  if (trimmed.isEmpty) return 'Activity recorded';
  return switch (trimmed) {
    'STAFF_SIGNED_IN' => 'Staff signed in',
    'STAFF_SIGNED_OUT' => 'Staff signed out',
    'PASSWORD_CHANGED' => 'Password changed',
    'SESSION_REVOKED' => 'Session revoked',
    'STAFF_ACCOUNT_VIEWED' => 'Staff account viewed',
    'STAFF_ROLE_CHANGED' || 'accessRoleAssigned' => 'Staff role changed',
    'STAFF_ROLE_ASSIGNED' => 'Staff role assigned',
    'STAFF_ACCESS_REVOKED' => 'Portal access revoked',
    'STAFF_ACCOUNT_SUSPENDED' ||
    'staffAccountDisabled' => 'Staff account suspended',
    'STAFF_ACCOUNT_REACTIVATED' ||
    'staffAccountEnabled' => 'Staff account reactivated',
    'STAFF_ACCOUNT_ACTIVATED' => 'Staff account activated',
    'STAFF_REGISTRATION_APPROVED' ||
    'staffRegistrationApproved' => 'Staff registration approved',
    'STAFF_REGISTRATION_REJECTED' ||
    'staffRegistrationRejected' => 'Staff registration rejected',
    'STAFF_ACCESS_REQUEST_SUBMITTED' => 'Staff access request submitted',
    'STAFF_ACCESS_REQUEST_VIEWED' => 'Staff access request viewed',
    'STAFF_ACCESS_REQUEST_MORE_INFO_REQUIRED' =>
      'More info requested on staff registration',
    'STAFF_ACCESS_REQUEST_APPROVED' => 'Staff access request approved',
    'STAFF_COLLEGE_ASSIGNMENTS_UPDATED' =>
      'Counselor college assignments updated',
    'COLLEGE_COUNSELOR_TRANSFERRED' => 'College counselor transferred',
    'staffOrganizationUpdated' => 'Staff organization assignment updated',
    'STUDENT_PROFILE_VIEWED' => 'Student profile viewed',
    'STUDENT_PERSONAL_INFO_VIEWED' => 'Student personal information viewed',
    'COUNSELING_HISTORY_VIEWED' => 'Counseling case history viewed',
    'CASE_REMARKS_VIEWED' => 'Clinical case remarks viewed',
    'CASE_REMARKS_UPDATED' => 'Clinical case remarks updated',
    'CLINICAL_ATTACHMENT_DOWNLOADED' =>
      'Clinical session attachment downloaded',
    'ASSESSMENT_SUMMARY_VIEWED' => 'Assessment summary viewed',
    'ASSESSMENT_HISTORY_VIEWED' => 'Assessment history viewed',
    'APPOINTMENT_VIEWED' => 'Appointment viewed',
    'APPOINTMENT_ADJUSTMENT_REQUESTED' => 'Appointment adjustment requested',
    'APPOINTMENT_SCHEDULE_PROPOSED' => 'Appointment schedule proposed',
    'APPOINTMENT_SCHEDULE_AGREED' => 'Appointment schedule agreed',
    'APPOINTMENT_CONFIRMED' => 'Appointment confirmed',
    'APPOINTMENT_RESCHEDULED' => 'Appointment rescheduled',
    'APPOINTMENT_COMPLETED' => 'Appointment completed',
    'APPOINTMENT_MARKED_NO_SHOW' => 'Appointment marked no-show',
    'APPOINTMENT_CANCELLED' => 'Appointment cancelled',
    'APPOINTMENTS_ARCHIVED' => 'Appointments archived',
    'SCHEDULE_CREATED' => 'Counseling schedule created',
    'SCHEDULE_UPDATED' => 'Counseling schedule updated',
    'SCHEDULE_SLOT_CREATED' => 'Schedule slot created',
    'SCHEDULE_SLOT_UPDATED' => 'Schedule slot updated',
    'SCHEDULE_SLOT_REMOVED' => 'Schedule slot removed',
    'COUNSELOR_AVAILABILITY_CHANGED' => 'Counselor availability changed',
    'INQUIRY_VIEWED' => 'Inquiry viewed',
    'INQUIRY_RESPONDED' => 'Inquiry reply sent',
    'INQUIRY_STATUS_CHANGED' => 'Inquiry status updated',
    'INQUIRY_RESOLVED' => 'Inquiry resolved',
    'INQUIRY_ROUTED' => 'Inquiry routed',
    'INQUIRY_ACKNOWLEDGED' => 'Inquiry acknowledged',
    'INQUIRY_REASSIGNED' => 'Inquiry reassigned',
    'INQUIRY_ESCALATED' => 'Inquiry escalated to counselor',
    'INQUIRY_TAKEN_OVER' => 'Inquiry taken over',
    'INQUIRY_SLA_UPDATED' => 'Inquiry SLA updated',
    'REPORT_VIEWED' => 'Report viewed',
    'REPORT_GENERATED' => 'Report generated',
    'REPORT_EXPORTED_PDF' => 'Report exported (PDF)',
    'REPORT_EXPORTED_CSV' => 'Report exported (CSV)',
    'REPORT_EXPORTED_XLSX' => 'Report exported (Excel)',
    'REPORT_PRINTED' => 'Report print requested',
    'ACADEMIC_YEAR_CREATED' => 'Academic year created',
    'ACADEMIC_YEAR_CLOSED' => 'Academic year closed',
    'ACADEMIC_YEAR_CHANGED' => 'Active academic year changed',
    'ACADEMIC_YEAR_VOIDED' => 'Academic year voided',
    'ACADEMIC_YEAR_REINSTATED' => 'Academic year reinstated',
    'POPULATION_SNAPSHOT_CREATED' => 'Population snapshot created',
    'POPULATION_SNAPSHOT_UPDATED' => 'Population snapshot updated',
    'STUDENT_ROSTER_IMPORTED' => 'Student roster imported',
    'STUDENT_ACCOUNT_ACTIVATED' => 'Student account activated',
    'STUDENT_CORRECTION_APPROVED' => 'Student correction request approved',
    'STUDENT_CORRECTION_REJECTED' => 'Student correction request rejected',
    'STUDENT_ROSTER_RECORD_UPDATED' => 'Student roster record updated',
    'STUDENT_ROSTER_STATUS_CHANGED' => 'Student roster status changed',
    'STUDENT_ACTIVATION_LOCK_RESET' => 'Student activation lock reset',
    'STUDENT_ACTIVATION_CODES_ISSUED' => 'Student activation codes issued',
    'STUDENT_ACTIVATION_REVOKED' => 'Student activation revoked',
    'STUDENT_INFO_REQUIREMENT_BACKFILLED' =>
      'Student info requirement backfilled',
    'ACADEMIC_CATALOGUE_IMPORTED' => 'Academic catalogue imported',
    'ACADEMIC_STRUCTURE_INITIALIZED' => 'Academic structure initialized',
    'COLLEGE_CREATED' => 'College created',
    'COLLEGE_UPDATED' => 'College updated',
    'COLLEGE_ARCHIVED' => 'College archived',
    'COLLEGE_RESTORED' => 'College restored',
    'DEPARTMENT_CREATED' => 'Department created',
    'DEPARTMENT_UPDATED' => 'Department updated',
    'DEPARTMENT_ARCHIVED' => 'Department archived',
    'DEPARTMENT_RESTORED' => 'Department restored',
    'COURSE_CREATED' => 'Course created',
    'COURSE_UPDATED' => 'Course updated',
    'COURSE_ARCHIVED' => 'Course archived',
    'COURSE_RESTORED' => 'Course restored',
    'BACKUP_REQUESTED' => 'Database backup requested',
    'BACKUP_COMPLETED' => 'Database backup completed',
    'BACKUP_FAILED' => 'Database backup failed',
    'BACKUP_SKIPPED' => 'Database backup skipped',
    'BACKUP_EXPORT_STARTED' => 'Backup export started',
    'BACKUP_EXPORT_COMPLETED' => 'Backup export completed',
    'WALK_IN_APPOINTMENTS_IMPORTED' => 'Walk-in appointments imported',
    'WALK_IN_IMPORT_DELETED' => 'Walk-in import deleted',
    'WALK_IN_IMPORT_ARCHIVED' => 'Walk-in import archived',
    'EMERGENCY_ALERT_ACKNOWLEDGED' => 'Emergency alert acknowledged',
    'EMERGENCY_ALERT_RESOLVED' => 'Emergency alert resolved',
    _ => _humanizeActionCode(trimmed),
  };
}

String _humanizeActionCode(String raw) {
  final words = raw
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m.group(1)}_${m.group(2)}',
      )
      .split(RegExp(r'[_\s-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.toLowerCase())
      .toList();
  if (words.isEmpty) return 'Activity recorded';
  final first = words.first;
  words[0] = '${first[0].toUpperCase()}${first.substring(1)}';
  return words.join(' ');
}

AdminSemanticTone resolveActivityEventTone(AdminAuditEvent event) {
  final action = event.action.trim().toUpperCase();
  final category = event.category.trim().toUpperCase();
  if (action.contains('FAILED') ||
      action.contains('REVOKED') ||
      action.contains('REJECTED') ||
      action.contains('SUSPENDED') ||
      action.contains('DISABLED') ||
      action.contains('DELETED') ||
      action.contains('VOIDED') ||
      action.contains('NO_SHOW') ||
      action.contains('CANCELLED')) {
    return AdminSemanticTone.red;
  }
  if (action.contains('ESCALATED') ||
      action.contains('EMERGENCY') ||
      action.contains('MORE_INFO') ||
      action.contains('RESCHEDULE') ||
      action.contains('PROPOSED') ||
      action.contains('ADJUSTMENT') ||
      category == 'SECURITY') {
    return AdminSemanticTone.amber;
  }
  if (action.contains('APPROVED') ||
      action.contains('CONFIRMED') ||
      action.contains('COMPLETED') ||
      action.contains('RESOLVED') ||
      action.contains('ACTIVATED') ||
      action.contains('REACTIVATED') ||
      action.contains('REINSTATED') ||
      action.contains('PUBLISHED') ||
      action.contains('AGREED') ||
      action.contains('RESTORED')) {
    return AdminSemanticTone.green;
  }
  if (category == 'APPOINTMENTS' ||
      category == 'INQUIRIES' ||
      category == 'SCHEDULE' ||
      category == 'REPORTS') {
    return AdminSemanticTone.blue;
  }
  if (category == 'SYSTEM' || category == 'USER_MANAGEMENT') {
    return AdminSemanticTone.violet;
  }
  return AdminSemanticTone.neutral;
}

IconData resolveActivityEventIcon(AdminAuditEvent event) {
  final category = event.category.trim().toUpperCase();
  final action = event.action.trim().toUpperCase();
  if (action.contains('EMERGENCY')) return Icons.warning_amber_rounded;
  if (action.contains('BACKUP')) return Icons.backup_outlined;
  return switch (category) {
    'AUTHENTICATION' => Icons.login_outlined,
    'USER_MANAGEMENT' => Icons.manage_accounts_outlined,
    'PROFILING' => Icons.badge_outlined,
    'APPOINTMENTS' => Icons.calendar_month_outlined,
    'SCHEDULE' => Icons.schedule_outlined,
    'INQUIRIES' => Icons.chat_bubble_outline_rounded,
    'REPORTS' => Icons.analytics_outlined,
    'SYSTEM' => Icons.settings_suggest_outlined,
    'SECURITY' => Icons.shield_outlined,
    _ => Icons.history_rounded,
  };
}

/// Formats an audit timestamp deterministically in Asia/Manila (UTC+8) with
/// an explicit timezone indicator.
String formatActivityManilaTimestamp(
  DateTime? timestamp, {
  bool use24Hour = false,
}) {
  if (timestamp == null) return 'Pending timestamp (Asia/Manila, UTC+8)';
  final manila = toManilaDateTime(timestamp);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[manila.month - 1];
  final minute = manila.minute.toString().padLeft(2, '0');
  final timePart = use24Hour
      ? '${manila.hour.toString().padLeft(2, '0')}:$minute'
      : '${manila.hour == 0
            ? 12
            : manila.hour > 12
            ? manila.hour - 12
            : manila.hour}:$minute ${manila.hour >= 12 ? 'PM' : 'AM'}';
  return '$month ${manila.day}, ${manila.year} · $timePart (Asia/Manila, UTC+8)';
}

/// Computes Manila UTC DateTime bounds for a preset or custom date range.
({DateTime? after, DateTime? before}) resolveActivityDateBounds({
  required ActivityDateRangePreset preset,
  required DateTime now,
  DateTime? customStartManilaDay,
  DateTime? customEndManilaDay,
}) {
  final manilaNow = toManilaDateTime(now);
  // Midnight Manila time in UTC is Manila Y-M-D 00:00 minus 8 hours.
  DateTime manilaStartOfDayUtc(int year, int month, int day) =>
      DateTime.utc(year, month, day).subtract(const Duration(hours: 8));
  DateTime manilaEndOfDayUtc(int year, int month, int day) => DateTime.utc(
    year,
    month,
    day,
    23,
    59,
    59,
    999,
  ).subtract(const Duration(hours: 8));

  return switch (preset) {
    ActivityDateRangePreset.allTime => (after: null, before: null),
    ActivityDateRangePreset.today => (
      after: manilaStartOfDayUtc(
        manilaNow.year,
        manilaNow.month,
        manilaNow.day,
      ),
      before: null,
    ),
    ActivityDateRangePreset.last7Days => (
      after: now.subtract(const Duration(days: 7)),
      before: null,
    ),
    ActivityDateRangePreset.last30Days => (
      after: now.subtract(const Duration(days: 30)),
      before: null,
    ),
    ActivityDateRangePreset.thisMonth => (
      after: manilaStartOfDayUtc(manilaNow.year, manilaNow.month, 1),
      before: null,
    ),
    ActivityDateRangePreset.custom => (
      after: customStartManilaDay == null
          ? null
          : manilaStartOfDayUtc(
              customStartManilaDay.year,
              customStartManilaDay.month,
              customStartManilaDay.day,
            ),
      before: customEndManilaDay == null
          ? null
          : manilaEndOfDayUtc(
              customEndManilaDay.year,
              customEndManilaDay.month,
              customEndManilaDay.day,
            ),
    ),
  };
}

/// Redacts student identifiers and strips confidential/PII metadata keys so
/// the Admin Activity Logs feed never leaks student identities or secrets.
AdminAuditEvent sanitizeAuditEventForDisplay(AdminAuditEvent event) {
  final normRole = normalizeAuditActorRole(event.actorRoleSnapshot);
  final rawTargetType = (event.targetType ?? '').trim().toLowerCase();
  final rawTargetId = (event.targetId ?? '').trim();
  String? safeTargetId = rawTargetId.isEmpty ? null : rawTargetId;
  if (safeTargetId != null &&
      (rawTargetType == 'student' ||
          rawTargetType == 'student_personal_info')) {
    final suffix = safeTargetId.length > 4
        ? safeTargetId.substring(safeTargetId.length - 4)
        : safeTargetId;
    safeTargetId = 'student••••$suffix';
  }

  final safeMeta = <String, dynamic>{};
  for (final entry in event.metadata.entries) {
    if (_sensitiveAuditMetadataKeyPattern.hasMatch(entry.key)) continue;
    final val = entry.value;
    if (val is String || val is num || val is bool) {
      safeMeta[entry.key] = val;
    } else if (val is Map) {
      final nested = <String, dynamic>{};
      for (final nEntry in val.entries) {
        final nKey = '${nEntry.key}';
        if (_sensitiveAuditMetadataKeyPattern.hasMatch(nKey)) continue;
        final nVal = nEntry.value;
        if (nVal is String || nVal is num || nVal is bool) {
          nested[nKey] = nVal;
        }
      }
      if (nested.isNotEmpty) safeMeta[entry.key] = nested;
    }
  }

  final actorName = event.actorNameSnapshot.trim().isNotEmpty
      ? event.actorNameSnapshot.trim()
      : auditActorRoleLabel(normRole);

  return AdminAuditEvent(
    id: event.id,
    action: event.action,
    actorId: event.actorId,
    targetUserId: rawTargetType == 'staff' ? event.targetUserId : '',
    reason: event.reason,
    category: event.category.trim().isEmpty
        ? 'USER_MANAGEMENT'
        : event.category.trim(),
    actorNameSnapshot: actorName,
    actorRoleSnapshot: normRole,
    targetType: event.targetType,
    targetId: safeTargetId,
    metadata: safeMeta,
    createdAt: event.createdAt,
  );
}

/// Pure, deterministic filter and sort for Activity Logs events.
/// Excludes non-staff (`appUser`/`student`) events and applies role, actor,
/// category, action, search, and date-range filters.
List<AdminAuditEvent> filterActivityLogEvents(
  Iterable<AdminAuditEvent> source, {
  ActivityActorRoleFilter roleFilter = ActivityActorRoleFilter.all,
  String actorIdFilter = '',
  String categoryFilter = '',
  String actionFilter = '',
  String searchQuery = '',
  DateTime? after,
  DateTime? before,
}) {
  final normCategory = categoryFilter.trim().toUpperCase();
  final normAction = actionFilter.trim();
  final normActorId = actorIdFilter.trim();
  final normSearch = searchQuery.trim().toLowerCase();

  final results = <AdminAuditEvent>[];
  for (final raw in source) {
    final normRole = normalizeAuditActorRole(raw.actorRoleSnapshot);
    if (normRole == 'other') continue;
    if (roleFilter != ActivityActorRoleFilter.all &&
        normRole != roleFilter.code) {
      continue;
    }
    if (normActorId.isNotEmpty && raw.actorId.trim() != normActorId) {
      continue;
    }

    final event = sanitizeAuditEventForDisplay(raw);
    if (normCategory.isNotEmpty &&
        event.category.toUpperCase() != normCategory) {
      continue;
    }
    if (normAction.isNotEmpty && event.action != normAction) {
      continue;
    }

    final createdAt = event.createdAt;
    if (after != null && (createdAt == null || createdAt.isBefore(after))) {
      continue;
    }
    if (before != null && (createdAt == null || createdAt.isAfter(before))) {
      continue;
    }

    if (normSearch.isNotEmpty) {
      final haystack = [
        event.actorNameSnapshot,
        auditActorRoleLabel(event.actorRoleSnapshot),
        event.action,
        auditActionLabel(event.action),
        event.category,
        auditCategoryLabel(event.category),
        event.targetType ?? '',
        event.targetId ?? '',
        event.reason,
      ].join(' ').toLowerCase();
      if (!haystack.contains(normSearch)) continue;
    }

    results.add(event);
  }

  results.sort(
    (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
  return results;
}
