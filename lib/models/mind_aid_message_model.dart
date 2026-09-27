import '../core/utils/firestore_mapper.dart';
import '../features/mind_aid/domain/mind_aid_integration_models.dart';

class MindAidMessageModel {
  final String id;
  final String conversationId;
  final String sender; // user | assistant
  final String text;
  final DateTime createdAt;
  final String status;
  final String? safetyLevel;
  final String? primaryIntent;
  final bool requiresEscalation;
  final String source;
  final double confidence;
  final String fallbackReason;
  final List<MindAidAction> actions;
  final bool hasPaaccDisplay;

  MindAidMessageModel({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.text,
    required this.createdAt,
    required this.status,
    this.safetyLevel,
    this.primaryIntent,
    this.requiresEscalation = false,
    this.source = 'local',
    this.confidence = 0,
    this.fallbackReason = '',
    this.actions = const [],
    this.hasPaaccDisplay = false,
  });

  factory MindAidMessageModel.fromMap(Map<String, dynamic> map) {
    return MindAidMessageModel(
      id: (map['id'] ?? '').toString(),
      conversationId: (map['conversationId'] ?? '').toString(),
      sender: (map['sender'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      createdAt: dateTimeFromFirestoreOrNow(map['createdAt']),
      status: (map['status'] ?? '').toString(),
      safetyLevel: map['safetyLevel']?.toString(),
      primaryIntent: map['primaryIntent']?.toString(),
      requiresEscalation: boolFromFirestore(map['requiresEscalation']),
      source: (map['source'] ?? 'local').toString(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      fallbackReason: (map['fallbackReason'] ?? '').toString(),
      actions: _actionsFrom(map['actions']),
      hasPaaccDisplay: map['hasPaaccDisplay'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'sender': sender,
      'text': text,
      'createdAt': createdAt,
      'status': status,
      'safetyLevel': safetyLevel,
      'primaryIntent': primaryIntent,
      'requiresEscalation': requiresEscalation,
      'source': source,
      'confidence': confidence,
      'fallbackReason': fallbackReason,
      'actions': actions
          .map(
            (action) => {
              'type': action.type.name,
              'label': action.label,
              'payload': action.payload,
            },
          )
          .toList(growable: false),
    };
  }

  static List<MindAidAction> _actionsFrom(Object? value) {
    if (value is! List) return const [];
    final actions = <MindAidAction>[];
    for (final item in value.whereType<Map>()) {
      try {
        actions.add(MindAidAction.fromMap(item));
      } on FormatException {
        // Ignore unrecognized actions from older or newer records.
      }
    }
    return actions;
  }
}
