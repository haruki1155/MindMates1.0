import '../../../core/utils/firestore_mapper.dart';

class ReminderPreferences {
  const ReminderPreferences({
    this.appointment24HourEnabled = true,
    this.appointment1HourEnabled = true,
    this.moodDailyEnabled = false,
    this.moodDailyTime = '20:00',
    this.moodDailyUpdatedAt,
    this.breathingDailyEnabled = false,
    this.breathingDailyTime = '21:00',
    this.breathingDailyUpdatedAt,
    this.updatedAt,
  });

  final bool appointment24HourEnabled;
  final bool appointment1HourEnabled;
  final bool moodDailyEnabled;
  final String moodDailyTime;
  final DateTime? moodDailyUpdatedAt;
  final bool breathingDailyEnabled;
  final String breathingDailyTime;
  final DateTime? breathingDailyUpdatedAt;
  final DateTime? updatedAt;

  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    const defaults = ReminderPreferences();
    final moodTime = json['moodDailyTime'];
    final breathingTime = json['breathingDailyTime'];
    return ReminderPreferences(
      appointment24HourEnabled: _bool(
        json['appointment24HourEnabled'],
        defaults.appointment24HourEnabled,
      ),
      appointment1HourEnabled: _bool(
        json['appointment1HourEnabled'],
        defaults.appointment1HourEnabled,
      ),
      moodDailyEnabled: _bool(json['moodDailyEnabled'], false),
      moodDailyTime: moodTime is String && isValidTime(moodTime)
          ? moodTime
          : defaults.moodDailyTime,
      moodDailyUpdatedAt: dateTimeFromFirestore(json['moodDailyUpdatedAt']),
      breathingDailyEnabled: _bool(json['breathingDailyEnabled'], false),
      breathingDailyTime:
          breathingTime is String && isValidTime(breathingTime)
          ? breathingTime
          : defaults.breathingDailyTime,
      breathingDailyUpdatedAt: dateTimeFromFirestore(
        json['breathingDailyUpdatedAt'],
      ),
      updatedAt: dateTimeFromFirestore(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'appointment24HourEnabled': appointment24HourEnabled,
    'appointment1HourEnabled': appointment1HourEnabled,
    'moodDailyEnabled': moodDailyEnabled,
    'moodDailyTime': moodDailyTime,
    'moodDailyUpdatedAt': moodDailyUpdatedAt,
    'breathingDailyEnabled': breathingDailyEnabled,
    'breathingDailyTime': breathingDailyTime,
    'breathingDailyUpdatedAt': breathingDailyUpdatedAt,
    'updatedAt': updatedAt,
  };

  ReminderPreferences copyWith({
    bool? appointment24HourEnabled,
    bool? appointment1HourEnabled,
    bool? moodDailyEnabled,
    String? moodDailyTime,
    DateTime? moodDailyUpdatedAt,
    bool? breathingDailyEnabled,
    String? breathingDailyTime,
    DateTime? breathingDailyUpdatedAt,
    DateTime? updatedAt,
  }) => ReminderPreferences(
    appointment24HourEnabled:
        appointment24HourEnabled ?? this.appointment24HourEnabled,
    appointment1HourEnabled:
        appointment1HourEnabled ?? this.appointment1HourEnabled,
    moodDailyEnabled: moodDailyEnabled ?? this.moodDailyEnabled,
    moodDailyTime: moodDailyTime ?? this.moodDailyTime,
    moodDailyUpdatedAt: moodDailyUpdatedAt ?? this.moodDailyUpdatedAt,
    breathingDailyEnabled: breathingDailyEnabled ?? this.breathingDailyEnabled,
    breathingDailyTime: breathingDailyTime ?? this.breathingDailyTime,
    breathingDailyUpdatedAt:
        breathingDailyUpdatedAt ?? this.breathingDailyUpdatedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static bool isValidTime(String value) =>
      RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value);

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;
}
