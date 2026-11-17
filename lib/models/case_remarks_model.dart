/// Optional counselor transcript / remarks for one case, as returned by the
/// `getCaseRemarks` / `saveCaseRemarks` callables. Only counselors entitled
/// to the student receive it; author IDs never leave the server.
class CaseRemarks {
  const CaseRemarks({
    required this.appointmentId,
    required this.text,
    required this.revision,
    required this.updatedAt,
    required this.authorName,
    required this.versions,
  });

  factory CaseRemarks.fromJson(Map<String, dynamic> json) {
    final versions = json['versions'];
    return CaseRemarks(
      appointmentId: _text(json['appointmentId']),
      text: json['text'] is String ? json['text'] as String : '',
      revision: _revision(json['revision']),
      updatedAt: _date(json['updatedAt']),
      authorName: _text(json['authorName']),
      versions: versions is List
          ? versions
                .map((item) => CaseRemarksVersion.fromJson(_map(item)))
                .toList(growable: false)
          : const [],
    );
  }

  final String appointmentId;
  final String text;

  /// 0 when nothing was ever saved. Sent back as `expectedRevision`.
  final int revision;
  final DateTime? updatedAt;
  final String authorName;

  /// Newest first; the server returns at most 20.
  final List<CaseRemarksVersion> versions;

  bool get hasRemarks => text.trim().isNotEmpty;
}

class CaseRemarksVersion {
  const CaseRemarksVersion({
    required this.revision,
    required this.text,
    required this.authorName,
    required this.savedAt,
  });

  factory CaseRemarksVersion.fromJson(Map<String, dynamic> json) =>
      CaseRemarksVersion(
        revision: _revision(json['revision']),
        text: json['text'] is String ? json['text'] as String : '',
        authorName: _text(json['authorName']),
        savedAt: _date(json['savedAt']),
      );

  final int revision;
  final String text;
  final String authorName;
  final DateTime? savedAt;
}

String _text(Object? value) => value is String ? value.trim() : '';

int _revision(Object? value) => value is int && value >= 0 ? value : 0;

DateTime? _date(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
