/// Removes the response-completeness sentence from student-facing summaries.
/// Saved counselor data is intentionally left untouched.
String withoutResponseCompleteness(String summary) {
  final trailingCompleteness = RegExp(
    r'\s*You answered\b[^.!?]*\bresponse completeness\.\s*$',
    caseSensitive: false,
  );
  if (!trailingCompleteness.hasMatch(summary)) return summary;
  return summary.replaceFirst(trailingCompleteness, '').trimRight();
}
