/// One appointment in a student's case history, as returned by the
/// `getStudentCaseHistory` callable. Contains no contact details and no
/// clinical notes; the server decides which fields are included.
class StudentCaseHistoryEntry {
  const StudentCaseHistoryEntry({
    required this.id,
    required this.status,
    required this.scheduledAt,
    required this.scheduledTime,
    required this.createdAt,
    required this.completedAt,
    required this.archived,
    required this.archivedAt,
    required this.counselorName,
    required this.location,
    required this.concern,
    required this.followUpStatus,
  });

  factory StudentCaseHistoryEntry.fromJson(Map<String, dynamic> json) =>
      StudentCaseHistoryEntry(
        id: _text(json['id']),
        status: _text(json['status']),
        scheduledAt: _date(json['scheduledAt']),
        scheduledTime: _text(json['scheduledTime']),
        createdAt: _date(json['createdAt']),
        completedAt: _date(json['completedAt']),
        archived: json['archived'] == true,
        archivedAt: _date(json['archivedAt']),
        counselorName: _text(json['counselorName']),
        location: _text(json['location']),
        concern: _text(json['concern']),
        followUpStatus: _text(json['followUpStatus']),
      );

  final String id;
  final String status;
  final DateTime? scheduledAt;
  final String scheduledTime;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final bool archived;
  final DateTime? archivedAt;
  final String counselorName;
  final String location;
  final String concern;
  final String followUpStatus;

  /// The date the server sorted by: the schedule, else the request date.
  DateTime? get sortDate => scheduledAt ?? createdAt;
}

/// One page of a student's case history.
class StudentCaseHistoryResult {
  const StudentCaseHistoryResult({
    required this.studentId,
    required this.displayName,
    required this.collegeId,
    required this.items,
    required this.nextCursor,
    required this.truncated,
  });

  factory StudentCaseHistoryResult.fromJson(Map<String, dynamic> json) {
    final student = _map(json['student']);
    final items = json['items'];
    return StudentCaseHistoryResult(
      studentId: _text(student['id']),
      displayName: _text(student['displayName']),
      collegeId: _text(student['collegeId']),
      items: items is List
          ? items
                .map((item) => StudentCaseHistoryEntry.fromJson(_map(item)))
                .toList(growable: false)
          : const [],
      nextCursor: json['nextCursor'] is String
          ? json['nextCursor'] as String
          : null,
      truncated: json['truncated'] == true,
    );
  }

  final String studentId;
  final String displayName;
  final String collegeId;
  final List<StudentCaseHistoryEntry> items;
  final String? nextCursor;

  /// The student has more records than the server reads in one view.
  final bool truncated;

  bool get hasMore => nextCursor != null;
}

String _text(Object? value) => value is String ? value.trim() : '';

DateTime? _date(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
