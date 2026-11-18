/// One appointment awaiting a clinical decision, as returned by the
/// `listAppointmentApprovals` callable. Holds identifiers, schedule and
/// approval scope only, never clinical text.
class AppointmentApprovalItem {
  const AppointmentApprovalItem({
    required this.appointmentId,
    required this.status,
    required this.scheduledAt,
    required this.pendingStudentProposal,
    required this.collegeId,
    required this.scope,
    required this.reason,
  });

  final String appointmentId;
  final String status;
  final DateTime? scheduledAt;
  final bool pendingStudentProposal;
  final String collegeId;

  /// `college` (assigned counselors decide) or `exception` (super-admin triage).
  final String scope;
  final String? reason;

  bool get isException => scope == 'exception';

  String get reasonLabel => switch (reason) {
    'missing_college' => 'Student has no verified college',
    'unverified_profile' => 'Student profile is not verified',
    'unknown_college' => 'College not found in the catalogue',
    'no_eligible_counselor' =>
      'No eligible counselor is assigned to this college',
    _ => 'Assigned college counselors decide',
  };

  factory AppointmentApprovalItem.fromJson(Map<String, dynamic> json) {
    final millis = json['scheduledAt'];
    return AppointmentApprovalItem(
      appointmentId: json['appointmentId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      scheduledAt: millis is num
          ? DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true)
          : null,
      pendingStudentProposal: json['pendingStudentProposal'] == true,
      collegeId: json['collegeId']?.toString() ?? '',
      scope: json['scope']?.toString() ?? 'exception',
      reason: json['reason']?.toString(),
    );
  }
}

/// Paginated response from `listAppointmentApprovals`.
class AppointmentApprovalsPage {
  const AppointmentApprovalsPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
    required this.done,
    required this.truncated,
    this.scanned = 0,
  });

  final List<AppointmentApprovalItem> items;
  final String? nextCursor;
  final bool hasMore;
  final bool done;
  final bool truncated;
  final int scanned;

  factory AppointmentApprovalsPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => AppointmentApprovalItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => item.appointmentId.isNotEmpty)
              .toList(growable: false)
        : const <AppointmentApprovalItem>[];
    final rawCursor = json['nextCursor']?.toString().trim() ?? '';
    final nextCursor = rawCursor.isEmpty ? null : rawCursor;
    final hasMore =
        json['hasMore'] == true ||
        (json['done'] == false && nextCursor != null);
    final done = json['done'] is bool ? json['done'] as bool : !hasMore;
    final truncated = json['truncated'] == true || hasMore;
    final scanned = json['scanned'] is num
        ? (json['scanned'] as num).toInt()
        : 0;
    return AppointmentApprovalsPage(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
      done: done,
      truncated: truncated,
      scanned: scanned,
    );
  }
}
