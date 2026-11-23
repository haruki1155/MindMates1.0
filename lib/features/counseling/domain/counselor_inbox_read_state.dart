import 'package:cloud_firestore/cloud_firestore.dart';

/// Conversation-level read state for the authenticated counselor.
enum CounselorReadStatus {
  /// Initial streams for the active UID have not resolved yet, or errored.
  unknown,

  /// No qualifying student message is newer than the confirmed read receipt.
  read,

  /// A mark-read write is pending server timestamp resolution and covers all
  /// currently known student messages in the thread.
  pendingRead,

  /// A qualifying incoming student message is newer than the effective receipt.
  unread,
}

class CounselorThreadReadState {
  const CounselorThreadReadState({
    required this.studentId,
    required this.collegeId,
    required this.studentName,
    required this.updatedAt,
    required this.lastStudentMessageAt,
    required this.lastStudentMessageId,
    required this.lastCounselorMessageAt,
    required this.serverReadAt,
    required this.receiptHasPendingWrites,
    required this.status,
  });

  final String studentId;
  final String? collegeId;
  final String? studentName;
  final Timestamp? updatedAt;
  final Timestamp? lastStudentMessageAt;
  final String? lastStudentMessageId;
  final Timestamp? lastCounselorMessageAt;
  final Timestamp? serverReadAt;
  final bool receiptHasPendingWrites;
  final CounselorReadStatus status;

  bool get isUnread => status == CounselorReadStatus.unread;
  bool get isRead =>
      status == CounselorReadStatus.read ||
      status == CounselorReadStatus.pendingRead;
  bool get isPendingSync => status == CounselorReadStatus.pendingRead;
  bool get hasStudentMessage => lastStudentMessageAt != null;
}

Timestamp? maxTimestamp(Timestamp? a, Timestamp? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.compareTo(b) >= 0 ? a : b;
}

CounselorReadStatus resolveCounselorReadStatus({
  required bool streamsReady,
  required bool hasError,
  required Timestamp? lastStudentMessageAt,
  required Timestamp? serverReadAt,
  required Timestamp? lastConfirmedReadAt,
  required Timestamp? pendingStudentMessageWatermark,
  required bool receiptExists,
  required bool receiptHasPendingWrites,
  required bool writeInFlight,
  bool awaitingReceiptConfirmation = false,
}) {
  if (hasError || !streamsReady) {
    return CounselorReadStatus.unknown;
  }
  if (lastStudentMessageAt == null) {
    return CounselorReadStatus.read;
  }

  final effectiveConfirmed = maxTimestamp(serverReadAt, lastConfirmedReadAt);
  if (effectiveConfirmed != null &&
      lastStudentMessageAt.compareTo(effectiveConfirmed) <= 0) {
    return CounselorReadStatus.read;
  }

  if (writeInFlight || receiptHasPendingWrites || awaitingReceiptConfirmation) {
    if (pendingStudentMessageWatermark != null &&
        lastStudentMessageAt.compareTo(pendingStudentMessageWatermark) <= 0) {
      return CounselorReadStatus.pendingRead;
    }
    // Offline queued receipt from a prior session: rules enforce readAt == request.time.
    if (receiptExists &&
        receiptHasPendingWrites &&
        serverReadAt == null &&
        pendingStudentMessageWatermark == null) {
      return CounselorReadStatus.pendingRead;
    }
  }

  return CounselorReadStatus.unread;
}

int countUnreadCounselorThreads(
  Iterable<CounselorThreadReadState> states, {
  String? collegeId,
}) {
  final filterCollege =
      collegeId != null && collegeId.isNotEmpty && collegeId != 'all';
  var count = 0;
  for (final state in states) {
    if (filterCollege && state.collegeId != collegeId) {
      continue;
    }
    if (state.isUnread) {
      count++;
    }
  }
  return count;
}

int compareCounselorThreadReadStates(
  CounselorThreadReadState a,
  CounselorThreadReadState b,
) {
  final aTime = maxTimestamp(
    a.updatedAt,
    maxTimestamp(a.lastStudentMessageAt, a.lastCounselorMessageAt),
  );
  final bTime = maxTimestamp(
    b.updatedAt,
    maxTimestamp(b.lastStudentMessageAt, b.lastCounselorMessageAt),
  );
  if (aTime != null && bTime != null) {
    final cmp = bTime.compareTo(aTime);
    if (cmp != 0) return cmp;
  } else if (aTime != null) {
    return -1;
  } else if (bTime != null) {
    return 1;
  }
  return a.studentId.compareTo(b.studentId);
}

bool counselorThreadUnread(Map<String, dynamic> data, dynamic readAt) {
  final last = data['lastStudentMessageAt'];
  return last is Timestamp &&
      (readAt is! Timestamp || last.compareTo(readAt) > 0);
}
