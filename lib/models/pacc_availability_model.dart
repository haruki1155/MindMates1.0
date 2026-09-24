import '../core/utils/firestore_mapper.dart';

enum CounselorPresence {
  inOffice,
  outOfOffice,
  onLeave;

  String get storedValue => switch (this) {
    inOffice => 'in_office',
    outOfOffice => 'out_of_office',
    onLeave => 'on_leave',
  };

  String get label => switch (this) {
    inOffice => 'Counselor is in the office',
    outOfOffice => 'Counselor is out of the office',
    onLeave => 'Counselor is on leave',
  };

  static CounselorPresence parse(Object? value) => switch (value?.toString()) {
    'out_of_office' => outOfOffice,
    'on_leave' => onLeave,
    _ => inOffice,
  };
}

class PaccAvailabilityModel {
  const PaccAvailabilityModel({
    required this.openDays,
    required this.opensAt,
    required this.closesAt,
    required this.presence,
    required this.acceptsWalkIns,
    this.notice = '',
    this.blackoutDates = const [],
    this.updatedAt,
  });

  final List<int> openDays;
  final String opensAt;
  final String closesAt;
  final CounselorPresence presence;
  final bool acceptsWalkIns;
  final String notice;
  final List<String> blackoutDates;
  final DateTime? updatedAt;

  factory PaccAvailabilityModel.fromJson(Map<String, dynamic> json) =>
      PaccAvailabilityModel(
        openDays: (json['openDays'] as List? ?? const [1, 2, 3, 4, 5])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(),
        opensAt: json['opensAt']?.toString() ?? '08:00',
        closesAt: json['closesAt']?.toString() ?? '17:00',
        presence: CounselorPresence.parse(json['presence']),
        acceptsWalkIns: json['acceptsWalkIns'] == true,
        notice: json['notice']?.toString().trim() ?? '',
        blackoutDates: (json['blackoutDates'] as List? ?? const [])
            .map((value) => value.toString().trim())
            .where((value) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value))
            .toList(),
        updatedAt: dateTimeFromFirestore(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
    'openDays': openDays,
    'opensAt': opensAt,
    'closesAt': closesAt,
    'presence': presence.storedValue,
    'acceptsWalkIns': acceptsWalkIns,
    'notice': notice,
    'blackoutDates': blackoutDates,
  };

  bool isOpenAt(DateTime now) {
    if (presence != CounselorPresence.inOffice ||
        !openDays.contains(now.weekday)) {
      return false;
    }
    int minutes(String value) {
      final parts = value.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final current = now.hour * 60 + now.minute;
    return current >= minutes(opensAt) && current < minutes(closesAt);
  }

  String statusLabel(DateTime now) => isOpenAt(now) ? 'OPEN NOW' : 'CLOSED';
}
