import '../../../core/utils/firestore_mapper.dart';

/// Status of a server-managed Firestore export job.
enum BackupJobStatus {
  running,
  completed,
  failed;

  String get label => switch (this) {
    BackupJobStatus.running => 'Running',
    BackupJobStatus.completed => 'Completed',
    BackupJobStatus.failed => 'Failed',
  };

  /// Unknown values are shown as failed rather than as a silent success.
  static BackupJobStatus parse(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'running' => BackupJobStatus.running,
        'completed' => BackupJobStatus.completed,
        _ => BackupJobStatus.failed,
      };
}

enum BackupVerificationStatus {
  pending,
  verified,
  missing;

  String get label => switch (this) {
    BackupVerificationStatus.pending => 'Not yet verified',
    BackupVerificationStatus.verified => 'Verified',
    BackupVerificationStatus.missing => 'Output missing',
  };

  static BackupVerificationStatus parse(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'verified' => BackupVerificationStatus.verified,
        'missing' => BackupVerificationStatus.missing,
        _ => BackupVerificationStatus.pending,
      };
}

/// One `backup_jobs` record. Holds status, timing, counts and a sanitised
/// error only; never database contents or bucket links.
class BackupJob {
  const BackupJob({
    required this.id,
    required this.status,
    required this.trigger,
    required this.requestedBy,
    required this.requestedAt,
    required this.verification,
    required this.coverage,
    required this.retentionDays,
    this.startedAt,
    this.completedAt,
    this.documentsCompleted,
    this.documentsEstimated,
    this.errorCode,
    this.errorMessage,
    this.expiresAt,
  });

  final String id;
  final BackupJobStatus status;
  final String trigger;
  final String requestedBy;
  final DateTime requestedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? documentsCompleted;
  final int? documentsEstimated;
  final BackupVerificationStatus verification;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, String> coverage;
  final int retentionDays;
  final DateTime? expiresAt;

  bool get isTerminal => status != BackupJobStatus.running;

  factory BackupJob.fromJson(Map<String, dynamic> json, {String? id}) {
    final progress = json['progress'] is Map
        ? Map<String, dynamic>.from(json['progress'] as Map)
        : null;
    final documents = progress?['documents'] is Map
        ? Map<String, dynamic>.from(progress!['documents'] as Map)
        : null;
    final verification = json['verification'] is Map
        ? Map<String, dynamic>.from(json['verification'] as Map)
        : null;
    final error = json['error'] is Map
        ? Map<String, dynamic>.from(json['error'] as Map)
        : null;
    final coverage = json['coverage'] is Map
        ? Map<String, dynamic>.from(json['coverage'] as Map)
        : const <String, dynamic>{};
    return BackupJob(
      id: (json['id'] ?? id ?? '').toString(),
      status: BackupJobStatus.parse(json['status']),
      trigger: json['trigger']?.toString() ?? 'manual',
      requestedBy: json['requestedBy']?.toString() ?? '',
      requestedAt: dateTimeFromFirestoreOrNow(json['requestedAt']),
      startedAt: dateTimeFromFirestore(json['startedAt']),
      completedAt: dateTimeFromFirestore(json['completedAt']),
      documentsCompleted: _int(documents?['completed']),
      documentsEstimated: _int(documents?['estimated']),
      verification: BackupVerificationStatus.parse(verification?['status']),
      errorCode: _text(error?['code']),
      errorMessage: _text(error?['message']),
      coverage: {
        for (final entry in coverage.entries)
          entry.key: entry.value?.toString() ?? '',
      },
      retentionDays: _int(json['retentionDays']) ?? 0,
      expiresAt: dateTimeFromFirestore(json['expiresAt']),
    );
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

/// Headline numbers for the Back-up Data page.
class BackupSummary {
  const BackupSummary({
    required this.latest,
    required this.hasRunning,
    required this.lastVerifiedAt,
  });

  final BackupJob? latest;
  final bool hasRunning;
  final DateTime? lastVerifiedAt;

  factory BackupSummary.fromJobs(List<BackupJob> jobs) {
    BackupJob? latest;
    DateTime? lastVerifiedAt;
    for (final job in jobs) {
      if (latest == null || job.requestedAt.isAfter(latest.requestedAt)) {
        latest = job;
      }
      final completedAt = job.completedAt;
      if (job.status == BackupJobStatus.completed &&
          job.verification == BackupVerificationStatus.verified &&
          completedAt != null &&
          (lastVerifiedAt == null || completedAt.isAfter(lastVerifiedAt))) {
        lastVerifiedAt = completedAt;
      }
    }
    return BackupSummary(
      latest: latest,
      hasRunning: jobs.any((job) => job.status == BackupJobStatus.running),
      lastVerifiedAt: lastVerifiedAt,
    );
  }
}
