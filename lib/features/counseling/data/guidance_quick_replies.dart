/// A fixed answer an app user can send in Guidance Assistance.
class GuidanceQuickReply {
  const GuidanceQuickReply(this.id, this.text);

  /// Stable internal identifier.
  final String id;

  /// Canonical message text. `firestore.rules` (`guidanceQuickReplyTexts`)
  /// holds the same strings; a test keeps the two identical.
  final String text;
}

const List<GuidanceQuickReply> guidanceQuickReplies = [
  GuidanceQuickReply('understand', 'I understand.'),
  GuidanceQuickReply('noted', 'Noted.'),
  GuidanceQuickReply('thank_you', 'Thank you for your guidance.'),
  GuidanceQuickReply('clarification', 'I need clarification.'),
  GuidanceQuickReply('available', 'I am available.'),
  GuidanceQuickReply('unavailable', 'I am not available.'),
  GuidanceQuickReply('follow_up', 'I would like a follow-up session.'),
  GuidanceQuickReply('further_assistance', 'I need further assistance.'),
  GuidanceQuickReply('resolved', 'My concern has been addressed.'),
];

/// Exact match only: the rules compare the stored text byte for byte.
bool isGuidanceQuickReplyText(String text) =>
    guidanceQuickReplies.any((reply) => reply.text == text);
