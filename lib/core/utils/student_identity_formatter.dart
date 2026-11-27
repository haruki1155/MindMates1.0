/// Utilities for stripping synthetic authentication alias emails and rendering
/// student-facing and admin-facing identity text safely.
library;

const List<String> _syntheticEmailSuffixes = <String>[
  '@students.mindmate.local',
  '@student.mindmate.local',
  '@mindmate.local',
];

/// Returns true when [email] is an internal Firebase Auth alias generated for
/// Student ID login and never meant to be displayed in the UI or copied into
/// inquiry contact fields.
bool isSyntheticStudentEmail(String? email) {
  final normalized = (email ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return false;
  for (final suffix in _syntheticEmailSuffixes) {
    if (normalized.endsWith(suffix)) {
      return true;
    }
  }
  return false;
}

/// Extracts the student number prefix from [email] when it is a synthetic alias
/// like `20220367@students.mindmate.local`, or returns an empty string.
String extractStudentNumberFromSyntheticEmail(String? email) {
  final normalized = (email ?? '').trim();
  if (!isSyntheticStudentEmail(normalized)) return '';
  final atIndex = normalized.indexOf('@');
  if (atIndex <= 0) return '';
  return normalized.substring(0, atIndex).trim();
}

/// Returns [email] if it is a real contact email, or an empty string when blank
/// or synthetic.
String visibleContactEmail(String? email) {
  final trimmed = (email ?? '').trim();
  if (trimmed.isEmpty || isSyntheticStudentEmail(trimmed)) {
    return '';
  }
  return trimmed;
}

/// Formats a display line for a student using [studentNumber] if available (or
/// extracted from synthetic [email]), otherwise falling back to real [email]
/// when present.
String formatStudentIdentifier({
  String? studentNumber,
  String? email,
  String fallback = 'Student',
}) {
  final explicitNo = (studentNumber ?? '').trim();
  final extractedNo = extractStudentNumberFromSyntheticEmail(email);
  final resolvedNo = explicitNo.isNotEmpty ? explicitNo : extractedNo;
  final realEmail = visibleContactEmail(email);

  if (resolvedNo.isNotEmpty && realEmail.isNotEmpty) {
    return 'Student No. $resolvedNo · $realEmail';
  }
  if (resolvedNo.isNotEmpty) {
    return 'Student No. $resolvedNo';
  }
  if (realEmail.isNotEmpty) {
    return realEmail;
  }
  return fallback;
}
