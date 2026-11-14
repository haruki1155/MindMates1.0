import 'dart:math';
import 'dart:typed_data';

const int maxSessionEvidenceFiles = 5;
const int maxSessionEvidenceFileBytes = 5 * 1024 * 1024;

const _mimeTypes = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

String? sessionEvidenceMimeType(String fileName) {
  final period = fileName.lastIndexOf('.');
  if (period < 1) return null;
  final extension = fileName.substring(period + 1).toLowerCase();
  return _mimeTypes[extension];
}

bool validSessionEvidenceFileName(String fileName) =>
    fileName.trim().isNotEmpty &&
    fileName.length <= 120 &&
    !RegExp(r'[/\\\x00-\x1f]').hasMatch(fileName);

String buildSessionEvidencePath(
  String appointmentId,
  String uploaderUid,
  String fileName, {
  String? nonce,
}) {
  final extension = fileName.split('.').last.toLowerCase();
  if (!RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(appointmentId) ||
      !RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(uploaderUid) ||
      sessionEvidenceMimeType(fileName) == null) {
    throw const FormatException('Invalid private attachment path.');
  }
  final token = nonce ?? List.generate(16, (_) {
    final random = _nonceGenerator.nextInt(256);
    return random.toRadixString(16).padLeft(2, '0');
  }).join();
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(token)) {
    throw const FormatException('Invalid attachment ID.');
  }
  return 'counseling_session_files/$appointmentId/$uploaderUid/$token.$extension';
}

final Random _nonceGenerator = Random.secure();

class PendingSessionEvidenceFile {
  const PendingSessionEvidenceFile({
    required this.name,
    required this.contentType,
    required this.bytes,
  });
  final String name;
  final String contentType;
  final Uint8List bytes;

  int get size => bytes.length;
}

class SessionEvidenceAttachment {
  const SessionEvidenceAttachment({
    required this.path,
    required this.name,
    required this.contentType,
    required this.size,
  });
  final String path;
  final String name;
  final String contentType;
  final int size;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'contentType': contentType,
    'size': size,
  };

  factory SessionEvidenceAttachment.fromJson(Map<String, dynamic> json) =>
      SessionEvidenceAttachment(
        path: json['path']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        contentType: json['contentType']?.toString() ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class SessionEvidenceRecord {
  const SessionEvidenceRecord({
    required this.summary,
    required this.interviewQuestions,
    required this.requirementsChecked,
    required this.materialsUsed,
    required this.attachments,
  });

  final String summary;
  final String interviewQuestions;
  final String requirementsChecked;
  final String materialsUsed;
  final List<SessionEvidenceAttachment> attachments;

  factory SessionEvidenceRecord.fromJson(Map<String, dynamic> json) {
    final raw = json['attachments'];
    return SessionEvidenceRecord(
      summary: json['summary']?.toString() ?? '',
      interviewQuestions: json['interviewQuestions']?.toString() ?? '',
      requirementsChecked: json['requirementsChecked']?.toString() ?? '',
      materialsUsed: json['materialsUsed']?.toString() ?? '',
      attachments: raw is List
          ? raw.whereType<Map>().map((entry) =>
              SessionEvidenceAttachment.fromJson(
                Map<String, dynamic>.from(entry),
              ),
            ).toList(growable: false)
          : const [],
    );
  }
}
