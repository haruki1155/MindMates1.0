import 'student_personal_info.dart';

enum RosterPreviewKind {
  newRow,
  update,
  link,
  error;

  static RosterPreviewKind parse(Object? value) => switch (value) {
    'new' => RosterPreviewKind.newRow,
    'update' => RosterPreviewKind.update,
    'link' => RosterPreviewKind.link,
    _ => RosterPreviewKind.error,
  };
}

class RosterPreviewRow {
  const RosterPreviewRow({
    required this.index,
    required this.studentNo,
    required this.kind,
    this.changes = const {},
    this.errors = const [],
  });

  final int index;
  final String studentNo;
  final RosterPreviewKind kind;
  final Map<String, ({String from, String to})> changes;
  final List<String> errors;

  factory RosterPreviewRow.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    return RosterPreviewRow(
      index: (map['index'] as num?)?.toInt() ?? 0,
      studentNo: asText(map['studentNo']),
      kind: RosterPreviewKind.parse(map['kind']),
      changes: {
        for (final e in asStringMap(map['changes']).entries)
          e.key: (
            from: asText(asStringMap(e.value)['from']),
            to: asText(asStringMap(e.value)['to']),
          ),
      },
      errors: [for (final e in asList(map['errors'])) asText(e)],
    );
  }
}

class IssuedActivationCode {
  const IssuedActivationCode({
    required this.studentNo,
    required this.name,
    required this.college,
    required this.course,
    required this.yearLevel,
    required this.code,
    required this.expiresAt,
  });

  final String studentNo;
  final String name;
  final String college;
  final String course;
  final String yearLevel;
  final String code;
  final DateTime expiresAt;

  factory IssuedActivationCode.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    return IssuedActivationCode(
      studentNo: asText(map['studentNo']),
      name: asText(map['name']),
      college: asText(map['college']),
      course: asText(map['course']),
      yearLevel: asText(map['yearLevel']),
      code: asText(map['code']),
      expiresAt: parseIso(map['expiresAt']),
    );
  }
}

class RosterRowView {
  const RosterRowView({
    required this.studentNo,
    required this.name,
    required this.college,
    required this.course,
    required this.yearLevel,
    required this.activated,
    required this.status,
    required this.personalInfoComplete,
    required this.userId,
  });

  final String studentNo;
  final String name;
  final String college;
  final String course;
  final String yearLevel;
  final bool activated;

  /// `active` or `deactivated`.
  final String status;
  final bool personalInfoComplete;
  final String? userId;

  factory RosterRowView.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    final userId = asText(map['userId']);
    return RosterRowView(
      studentNo: asText(map['studentNo']),
      name: asText(map['name']),
      college: asText(map['college']),
      course: asText(map['course']),
      yearLevel: asText(map['yearLevel']),
      activated: map['activated'] == true,
      status: asText(map['status']),
      personalInfoComplete: map['personalInfoComplete'] == true,
      userId: userId.isEmpty ? null : userId,
    );
  }
}

class LegacyStudent {
  const LegacyStudent({
    required this.userId,
    required this.schoolId,
    required this.name,
  });

  final String userId;
  final String schoolId;
  final String name;

  factory LegacyStudent.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    return LegacyStudent(
      userId: asText(map['userId']),
      schoolId: asText(map['schoolId']),
      name: asText(map['name']),
    );
  }
}

class RosterImportRecord {
  const RosterImportRecord({
    required this.id,
    required this.fileName,
    required this.counts,
    required this.importedByName,
    required this.importedAt,
  });

  final String id;
  final String fileName;

  /// Keys: `new`, `updated`, `linked`.
  final Map<String, int> counts;
  final String importedByName;
  final DateTime importedAt;

  factory RosterImportRecord.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    return RosterImportRecord(
      id: asText(map['id']),
      fileName: asText(map['fileName']),
      counts: intMap(map['counts']),
      importedByName: asText(map['importedByName']),
      importedAt: parseIso(map['importedAt']),
    );
  }
}

Map<String, int> intMap(Object? value) => {
  for (final e in asStringMap(value).entries)
    e.key: (e.value as num?)?.toInt() ?? 0,
};

enum RosterImportStatus { complete, partial }

class RosterFailedRow {
  const RosterFailedRow({required this.index, required this.studentNo});

  final int index;
  final String studentNo;
}

class RosterImportResult {
  const RosterImportResult({
    required this.status,
    required this.importId,
    required this.counts,
    required this.codes,
    this.failedRows = const [],
    this.message,
  });

  final RosterImportStatus status;
  final String importId;
  final Map<String, int> counts;
  final List<IssuedActivationCode> codes;
  final List<RosterFailedRow> failedRows;
  final String? message;

  bool get isPartial => status == RosterImportStatus.partial;
}

class SkippedActivation {
  const SkippedActivation({required this.studentNo, required this.reason});

  final String studentNo;
  final String reason;
}

class BackfillResult {
  const BackfillResult({required this.flagged, required this.notInRoster});

  final int flagged;
  final int notInRoster;
}

enum StudentActivationFailure {
  mismatch,
  expired,
  alreadyActivated,
  emailInUse,
  invalidInput,
  unknown;

  static StudentActivationFailure parse(Object? reason) => switch (reason) {
    'mismatch' => StudentActivationFailure.mismatch,
    'expired' => StudentActivationFailure.expired,
    'already-activated' => StudentActivationFailure.alreadyActivated,
    'email-in-use' => StudentActivationFailure.emailInUse,
    'invalid-input' => StudentActivationFailure.invalidInput,
    _ => StudentActivationFailure.unknown,
  };
}

class StudentActivationException implements Exception {
  const StudentActivationException(this.reason, {this.message});

  final StudentActivationFailure reason;

  /// Server-provided, user-displayable message.
  final String? message;

  @override
  String toString() => message ?? 'StudentActivationException($reason)';
}
