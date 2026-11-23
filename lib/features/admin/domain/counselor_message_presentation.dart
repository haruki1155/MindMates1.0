import 'package:cloud_firestore/cloud_firestore.dart';

import '../../counseling/domain/counselor_inbox_read_state.dart';
import 'admin_dashboard_analytics.dart';

const double kCounselorNearBottomThreshold = 96.0;
const int kCounselorMessagesPageSize = 30;

const List<String> _shortMonths = [
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

enum CounselorOutgoingStatus { sending, failed }

enum CounselorMessageDeliveryState { confirmed, sending, failed }

enum CounselorScrollAction {
  none,
  scrollToBottom,
  deferAndPreserveAnchor,
  preserveAnchor,
}

class LocalCounselorOutgoingMessage {
  const LocalCounselorOutgoingMessage({
    required this.localId,
    required this.uid,
    required this.studentId,
    required this.text,
    required this.queuedAt,
    required this.knownServerIdsAtSend,
    required this.status,
  });

  final String localId;
  final String uid;
  final String studentId;
  final String text;
  final DateTime queuedAt;
  final Set<String> knownServerIdsAtSend;
  final CounselorOutgoingStatus status;

  LocalCounselorOutgoingMessage copyWith({
    CounselorOutgoingStatus? status,
    DateTime? queuedAt,
    Set<String>? knownServerIdsAtSend,
  }) => LocalCounselorOutgoingMessage(
    localId: localId,
    uid: uid,
    studentId: studentId,
    text: text,
    queuedAt: queuedAt ?? this.queuedAt,
    knownServerIdsAtSend: knownServerIdsAtSend ?? this.knownServerIdsAtSend,
    status: status ?? this.status,
  );
}

class CounselorTimelineMessage {
  const CounselorTimelineMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderRole,
    required this.createdAt,
    this.sortHint,
    this.hasPendingWrites = false,
    this.outgoingStatus,
    this.localId,
  });

  final String id;
  final String text;
  final String senderId;
  final String senderRole;
  final DateTime? createdAt;
  final DateTime? sortHint;
  final bool hasPendingWrites;
  final CounselorOutgoingStatus? outgoingStatus;
  final String? localId;

  bool get isCounselor => senderRole == 'counselor';
  bool get isStudent => !isCounselor;

  CounselorMessageDeliveryState get deliveryState {
    if (outgoingStatus == CounselorOutgoingStatus.failed) {
      return CounselorMessageDeliveryState.failed;
    }
    if (outgoingStatus == CounselorOutgoingStatus.sending || hasPendingWrites) {
      return CounselorMessageDeliveryState.sending;
    }
    return CounselorMessageDeliveryState.confirmed;
  }
}

/// Converts Firestore message document data into a timeline item.
/// Only reads `counselor_threads/{studentId}/messages` fields; never merges
/// MindAid/chatbot history or per-message read receipts.
CounselorTimelineMessage counselorTimelineMessageFromMap({
  required String id,
  required Map<String, dynamic> data,
  required bool hasPendingWrites,
}) {
  final rawCreatedAt = data['createdAt'];
  DateTime? createdAt;
  if (rawCreatedAt is Timestamp) {
    createdAt = rawCreatedAt.toDate();
  } else if (rawCreatedAt is DateTime) {
    createdAt = rawCreatedAt;
  }
  return CounselorTimelineMessage(
    id: id,
    text: data['text'] as String? ?? '',
    senderId: data['senderId'] as String? ?? '',
    senderRole: data['senderRole'] as String? ?? 'user',
    createdAt: createdAt,
    hasPendingWrites: hasPendingWrites,
  );
}

/// Merges confirmed/pending Firestore messages with local outgoing overlay
/// items (`sending` / `failed`), deduplicating in-flight sends against newly
/// emitted server docs and sorting chronologically with unresolved timestamps last.
List<CounselorTimelineMessage> mergeAndSortCounselorMessages({
  required List<CounselorTimelineMessage> serverMessages,
  required List<LocalCounselorOutgoingMessage> localOutgoing,
}) {
  final sortedServer = List<CounselorTimelineMessage>.from(serverMessages)
    ..sort(_compareTimelineMessages);

  final matchedServerIds = <String>{};
  final combined = <CounselorTimelineMessage>[...sortedServer];

  for (final local in localOutgoing) {
    if (local.status == CounselorOutgoingStatus.sending) {
      CounselorTimelineMessage? match;
      for (final candidate in sortedServer) {
        if (matchedServerIds.contains(candidate.id)) continue;
        if (local.knownServerIdsAtSend.contains(candidate.id)) continue;
        if (candidate.isCounselor &&
            candidate.senderId == local.uid &&
            candidate.text == local.text) {
          match = candidate;
          break;
        }
      }
      if (match != null) {
        matchedServerIds.add(match.id);
        continue;
      }
    }

    combined.add(
      CounselorTimelineMessage(
        id: 'local:${local.localId}',
        text: local.text,
        senderId: local.uid,
        senderRole: 'counselor',
        createdAt: null,
        sortHint: local.queuedAt,
        hasPendingWrites: local.status == CounselorOutgoingStatus.sending,
        outgoingStatus: local.status,
        localId: local.localId,
      ),
    );
  }

  combined.sort(_compareTimelineMessages);
  return combined;
}

/// Returns localIds of `sending` overlay entries that are already confirmed in
/// [serverMessages] (`!hasPendingWrites && createdAt != null`) so callers can
/// prune completed local placeholders cleanly.
Set<String> resolvedLocalOutgoingIds({
  required List<CounselorTimelineMessage> serverMessages,
  required List<LocalCounselorOutgoingMessage> localOutgoing,
}) {
  final sortedServer = List<CounselorTimelineMessage>.from(serverMessages)
    ..sort(_compareTimelineMessages);
  final matchedServerIds = <String>{};
  final resolved = <String>{};
  for (final local in localOutgoing) {
    if (local.status != CounselorOutgoingStatus.sending) continue;
    for (final candidate in sortedServer) {
      if (matchedServerIds.contains(candidate.id)) continue;
      if (local.knownServerIdsAtSend.contains(candidate.id)) continue;
      if (candidate.isCounselor &&
          candidate.senderId == local.uid &&
          candidate.text == local.text) {
        matchedServerIds.add(candidate.id);
        if (!candidate.hasPendingWrites && candidate.createdAt != null) {
          resolved.add(local.localId);
        }
        break;
      }
    }
  }
  return resolved;
}

int _compareTimelineMessages(
  CounselorTimelineMessage a,
  CounselorTimelineMessage b,
) {
  final aAt = a.createdAt;
  final bAt = b.createdAt;
  if (aAt != null && bAt != null) {
    final cmp = aAt.compareTo(bAt);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  }
  if (aAt != null) return -1;
  if (bAt != null) return 1;

  final aHint = a.sortHint;
  final bHint = b.sortHint;
  if (aHint != null && bHint != null) {
    final cmp = aHint.compareTo(bHint);
    if (cmp != 0) return cmp;
  } else if (aHint != null) {
    return 1;
  } else if (bHint != null) {
    return -1;
  }
  return a.id.compareTo(b.id);
}

String formatManilaTimeOfDay(DateTime value, {bool use24HourFormat = false}) {
  final manila = toManilaDateTime(value);
  final minute = manila.minute.toString().padLeft(2, '0');
  if (use24HourFormat) {
    final hour = manila.hour.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final isPm = manila.hour >= 12;
  final hour12 = manila.hour % 12 == 0 ? 12 : manila.hour % 12;
  return '$hour12:$minute ${isPm ? 'PM' : 'AM'}';
}

String formatCounselorMessageTimestamp(
  DateTime? createdAt, {
  bool use24HourFormat = false,
  bool isSending = false,
}) {
  if (createdAt == null) {
    return isSending ? 'Sending…' : 'Time pending';
  }
  return formatManilaTimeOfDay(createdAt, use24HourFormat: use24HourFormat);
}

String counselorMessageDayLabel(DateTime createdAt, {DateTime? now}) {
  final day = manilaDateOnly(createdAt);
  final today = manilaDateOnly(now ?? DateTime.now());
  final yesterday = DateTime.utc(today.year, today.month, today.day - 1);
  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  return '${_shortMonths[day.month - 1]} ${day.day}, ${day.year}';
}

bool isSameCounselorMessageDay(DateTime a, DateTime b) =>
    manilaDateOnly(a) == manilaDateOnly(b);

Timestamp? counselorThreadLastActivityAt(CounselorThreadReadState state) =>
    maxTimestamp(
      state.updatedAt,
      maxTimestamp(state.lastStudentMessageAt, state.lastCounselorMessageAt),
    );

String formatCounselorThreadActivityTime(
  Timestamp? timestamp, {
  DateTime? now,
  bool use24HourFormat = false,
}) {
  if (timestamp == null) return 'No activity';
  final dt = timestamp.toDate();
  final day = manilaDateOnly(dt);
  final today = manilaDateOnly(now ?? DateTime.now());
  final yesterday = DateTime.utc(today.year, today.month, today.day - 1);
  if (day == today) {
    return formatManilaTimeOfDay(dt, use24HourFormat: use24HourFormat);
  }
  if (day == yesterday) return 'Yesterday';
  if (day.year == today.year) {
    return '${_shortMonths[day.month - 1]} ${day.day}';
  }
  return '${_shortMonths[day.month - 1]} ${day.day}, ${day.year}';
}

/// Conversation-level read status label derived strictly from Task 4
/// [CounselorThreadReadState]. Never used for per-message read receipts.
String counselorThreadStatusLabel(CounselorThreadReadState state) =>
    switch (state.status) {
      CounselorReadStatus.unread => 'Unread',
      CounselorReadStatus.pendingRead => 'Syncing…',
      CounselorReadStatus.read => 'Read',
      CounselorReadStatus.unknown => 'Checking…',
    };

bool isCounselorTimelineNearBottom({
  required bool hasClients,
  required double pixels,
  double threshold = kCounselorNearBottomThreshold,
}) => !hasClients || pixels <= threshold;

CounselorScrollAction resolveCounselorTimelineScrollAction({
  required bool hasNewAtEnd,
  required bool hasAnyAdditions,
  required bool ownSendStarted,
  required bool newAtEndContainsCounselor,
  required bool nearBottom,
}) {
  if (ownSendStarted ||
      newAtEndContainsCounselor ||
      (hasNewAtEnd && nearBottom)) {
    return CounselorScrollAction.scrollToBottom;
  }
  if (!nearBottom && hasNewAtEnd) {
    return CounselorScrollAction.deferAndPreserveAnchor;
  }
  if (!nearBottom && hasAnyAdditions) {
    return CounselorScrollAction.preserveAnchor;
  }
  return CounselorScrollAction.none;
}
