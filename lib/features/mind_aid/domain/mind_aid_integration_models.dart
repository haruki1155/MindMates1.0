enum MindAidActionType {
  logMood,
  startBreathing,
  openAssessment,
  openInsights,
  openCounselingServices,
  bookAppointment,
  viewAppointments,
  dismissPending;

  static MindAidActionType? fromWire(String value) {
    for (final item in values) {
      if (item.name == value) {
        return item;
      }
    }
    return null;
  }
}

class MindAidAction {
  const MindAidAction({
    required this.type,
    required this.label,
    this.payload = const {},
  });

  final MindAidActionType type;
  final String label;
  final Map<String, dynamic> payload;

  factory MindAidAction.fromMap(Map<Object?, Object?> map) {
    final type = MindAidActionType.fromWire((map['type'] ?? '').toString());
    if (type == null) {
      throw const FormatException('Unsupported MindAid action.');
    }
    final rawPayload = map['payload'];
    return MindAidAction(
      type: type,
      label: (map['label'] ?? 'Open').toString(),
      payload: rawPayload is Map
          ? rawPayload.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
  }
}

class MindAidLaunchContext {
  const MindAidLaunchContext({
    required this.source,
    this.openingPrompt,
    this.appointmentConcern,
  });

  final String source;
  final String? openingPrompt;
  final String? appointmentConcern;
}

class MindAidPreferences {
  const MindAidPreferences({
    required this.hasDecision,
    required this.cloudConsent,
    required this.personalizationEnabled,
    required this.conversationId,
    this.consentVersion,
  });

  static const currentConsentVersion = '2026-07-13';

  final bool hasDecision;
  final bool cloudConsent;
  final bool personalizationEnabled;
  final String conversationId;
  final String? consentVersion;

  factory MindAidPreferences.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return MindAidPreferences(
      hasDecision: data['hasDecision'] == true,
      cloudConsent:
          data['cloudConsent'] == true &&
          data['consentVersion'] == currentConsentVersion,
      personalizationEnabled: data['personalizationEnabled'] == true,
      conversationId: (data['conversationId'] ?? '').toString(),
      consentVersion: data['consentVersion']?.toString(),
    );
  }
}

class MindAidCloudResponse {
  const MindAidCloudResponse({
    required this.messageId,
    required this.text,
    required this.intent,
    required this.confidence,
    required this.safetyLevel,
    required this.source,
    required this.suggestions,
    required this.actions,
    required this.requiresEscalation,
    required this.fallbackReason,
  });

  final String messageId;
  final String text;
  final String intent;
  final double confidence;
  final String safetyLevel;
  final String source;
  final List<String> suggestions;
  final List<MindAidAction> actions;
  final bool requiresEscalation;
  final String fallbackReason;

  factory MindAidCloudResponse.fromMap(Map<Object?, Object?> map) {
    final rawActions = map['actions'];
    final actions = <MindAidAction>[];
    if (rawActions is List) {
      for (final item in rawActions.whereType<Map>()) {
        try {
          actions.add(MindAidAction.fromMap(item));
        } on FormatException {
          // Unknown server actions are intentionally ignored.
        }
      }
    }
    return MindAidCloudResponse(
      messageId: (map['messageId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      intent: (map['intent'] ?? 'general_support').toString(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      safetyLevel: (map['safetyLevel'] ?? 'safeSupport').toString(),
      source: (map['source'] ?? 'dialogflow').toString(),
      suggestions: (map['suggestions'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .take(5)
          .toList(growable: false),
      actions: actions,
      requiresEscalation: map['requiresEscalation'] == true,
      fallbackReason: (map['fallbackReason'] ?? '').toString(),
    );
  }
}
