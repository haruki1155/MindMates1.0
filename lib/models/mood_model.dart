import '../core/utils/firestore_mapper.dart';

class MoodModel {
  const MoodModel({
    required this.id,
    required this.level,
    required this.createdAt,
    this.userId,
    this.label,
    this.note,
    this.dateKey,
    this.timezone,
    this.entryMethod,
    this.expressionAssistUsed,
    this.expressionSuggestionAccepted,
    this.expressionModelVersion,
  });

  final String id;
  final int level;
  final DateTime createdAt;
  final String? userId;
  final String? label;
  final String? note;
  final String? dateKey;
  final String? timezone;
  final String? entryMethod;
  final bool? expressionAssistUsed;
  final bool? expressionSuggestionAccepted;
  final String? expressionModelVersion;

  factory MoodModel.fromJson(Map<String, dynamic> json, {String? id}) {
    return MoodModel(
      id: (json['id'] ?? id ?? '').toString(),
      userId: json['userId']?.toString(),
      level: intFromFirestore(json['level']),
      label: json['label']?.toString(),
      note: json['note']?.toString(),
      dateKey: json['dateKey']?.toString(),
      timezone: json['timezone']?.toString(),
      entryMethod: json['entryMethod']?.toString(),
      expressionAssistUsed: json['expressionAssistUsed'] as bool?,
      expressionSuggestionAccepted:
          json['expressionSuggestionAccepted'] as bool?,
      expressionModelVersion: json['expressionModelVersion']?.toString(),
      createdAt: dateTimeFromFirestoreOrNow(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson({String? userId}) {
    return {
      'userId': userId ?? this.userId,
      'level': level,
      'label': label ?? '',
      'note': note ?? '',
      'dateKey': dateKey ?? '',
      'timezone': timezone ?? '',
      if (entryMethod != null) 'entryMethod': entryMethod,
      if (expressionAssistUsed != null)
        'expressionAssistUsed': expressionAssistUsed,
      if (expressionSuggestionAccepted != null)
        'expressionSuggestionAccepted': expressionSuggestionAccepted,
      if (expressionModelVersion != null)
        'expressionModelVersion': expressionModelVersion,
      'createdAt': createdAt,
    };
  }
}
