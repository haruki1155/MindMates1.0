import 'package:cloud_firestore/cloud_firestore.dart';

import 'mind_aid_integration_models.dart';

class MindAidDialogueState {
  const MindAidDialogueState({
    required this.conversationId,
    this.sourceMessageId,
    this.action,
    this.expiresAt,
  });

  final String conversationId;
  final String? sourceMessageId;
  final MindAidAction? action;
  final DateTime? expiresAt;

  bool isPendingAt(DateTime now) =>
      action != null &&
      sourceMessageId != null &&
      expiresAt != null &&
      now.isBefore(expiresAt!);

  bool matches(String messageId, MindAidAction candidate, DateTime now) =>
      isPendingAt(now) &&
      sourceMessageId == messageId &&
      action!.type == candidate.type &&
      action!.label == candidate.label;

  factory MindAidDialogueState.fromMap(
    String conversationId,
    Map<String, dynamic>? data,
  ) {
    final pending = data?['pending'];
    if (pending is! Map) {
      return MindAidDialogueState(conversationId: conversationId);
    }
    final rawAction = pending['action'];
    MindAidAction? action;
    if (rawAction is Map) {
      try {
        action = MindAidAction.fromMap(rawAction);
      } on FormatException {
        // Treat an unknown action as no pending confirmation.
      }
    }
    final expiry = pending['expiresAt'];
    return MindAidDialogueState(
      conversationId: conversationId,
      sourceMessageId: pending['sourceMessageId']?.toString(),
      action: action,
      expiresAt: expiry is DateTime
          ? expiry
          : expiry is Timestamp
          ? expiry.toDate()
          : null,
    );
  }

  Map<String, dynamic> toPendingMap() => {
    'sourceMessageId': sourceMessageId,
    'action': {
      'type': action!.type.name,
      'label': action!.label,
      'payload': action!.payload,
    },
    'expiresAt': expiresAt,
  };
}
