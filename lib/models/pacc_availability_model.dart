import '../core/utils/firestore_mapper.dart';

enum CounselorPresence {
  inOffice, outOfOffice, onLeave;
  String get storedValue => switch (this) {inOffice => 'in_office', outOfOffice => 'out_of_office', onLeave => 'on_leave'};
  String get label => switch (this) {inOffice => 'Counselor is in the office', outOfOffice => 'Counselor is out of the office', onLeave => 'Counselor is on leave'};
  static CounselorPresence parse(Object? value) => switch (value?.toString()) {'out_of_office' => outOfOffice, 'on_leave' => onLeave, _ => inOffice};
}

class PaccDaySchedule {
  const PaccDaySchedule({required this.enabled, required this.opensAt, required this.closesAt, required this.presence, required this.appointmentsEnabled, required this.acceptsWalkIns});
  final bool enabled; final String opensAt; final String closesAt; final CounselorPresence presence; final bool appointmentsEnabled; final bool acceptsWalkIns;
  factory PaccDaySchedule.fromJson(Map<String, dynamic> json) => PaccDaySchedule(enabled: json['enabled'] == true, opensAt: json['opensAt']?.toString() ?? '08:00', closesAt: json['closesAt']?.toString() ?? '17:00', presence: CounselorPresence.parse(json['presence']), appointmentsEnabled: json['appointmentsEnabled'] == true, acceptsWalkIns: json['acceptsWalkIns'] == true);
  Map<String, dynamic> toJson() => {'enabled': enabled, 'opensAt': opensAt, 'closesAt': closesAt, 'presence': presence.storedValue, 'appointmentsEnabled': appointmentsEnabled, 'acceptsWalkIns': acceptsWalkIns};
  PaccDaySchedule copyWith({bool? enabled, String? opensAt, String? closesAt, CounselorPresence? presence, bool? appointmentsEnabled, bool? acceptsWalkIns}) => PaccDaySchedule(enabled: enabled ?? this.enabled, opensAt: opensAt ?? this.opensAt, closesAt: closesAt ?? this.closesAt, presence: presence ?? this.presence, appointmentsEnabled: appointmentsEnabled ?? this.appointmentsEnabled, acceptsWalkIns: acceptsWalkIns ?? this.acceptsWalkIns);
  static const closed = PaccDaySchedule(enabled: false, opensAt: '08:00', closesAt: '17:00', presence: CounselorPresence.outOfOffice, appointmentsEnabled: false, acceptsWalkIns: false);
}

class PaccDateOverride {
  const PaccDateOverride({required this.date, required this.closedAllDay, this.schedule, this.reason = ''});
  final String date; final bool closedAllDay; final PaccDaySchedule? schedule; final String reason;
  factory PaccDateOverride.fromJson(Map<String, dynamic> json) { final schedule = json['schedule']; return PaccDateOverride(date: json['date']?.toString() ?? '', closedAllDay: json['closedAllDay'] == true, schedule: schedule is Map ? PaccDaySchedule.fromJson(Map<String, dynamic>.from(schedule)) : null, reason: json['reason']?.toString().trim() ?? ''); }
  Map<String, dynamic> toJson() => {'date': date, 'closedAllDay': closedAllDay, if (schedule != null) 'schedule': schedule!.toJson(), 'reason': reason};
  PaccDateOverride copyWith({String? date, bool? closedAllDay, PaccDaySchedule? schedule, String? reason}) => PaccDateOverride(date: date ?? this.date, closedAllDay: closedAllDay ?? this.closedAllDay, schedule: schedule ?? this.schedule, reason: reason ?? this.reason);
}

enum PaccScheduleSource { weekly, override }

class ResolvedPaccSchedule {
  const ResolvedPaccSchedule({required this.schedule, required this.source, required this.date, required this.weekday, required this.isOfficeOpen, required this.canBookAppointments, required this.acceptsWalkIns, this.closureReason});
  final PaccDaySchedule schedule; final PaccScheduleSource source; final String date; final int weekday; final bool isOfficeOpen; final bool canBookAppointments; final bool acceptsWalkIns; final String? closureReason;
}

class PaccAvailabilityModel {
  /// Legacy constructor retained for existing callers while they move to [v2].
  const PaccAvailabilityModel({required this.openDays, required this.opensAt, required this.closesAt, required this.presence, required this.acceptsWalkIns, this.notice = '', this.blackoutDates = const [], this.updatedAt, this.revision = 0, this.weekdays = const {}, this.overrides = const [], this.schemaVersion = 2});
  const PaccAvailabilityModel.v2({required this.weekdays, required this.overrides, this.notice = '', this.revision = 0, this.updatedAt}) : schemaVersion = 2, openDays = const [], opensAt = '08:00', closesAt = '17:00', presence = CounselorPresence.inOffice, acceptsWalkIns = false, blackoutDates = const [];

  final int schemaVersion;
  final Map<int, PaccDaySchedule> weekdays;
  final List<PaccDateOverride> overrides;
  final int revision;
  final List<int> openDays;
  final String opensAt;
  final String closesAt;
  final CounselorPresence presence;
  final bool acceptsWalkIns;
  final String notice;
  final List<String> blackoutDates;
  final DateTime? updatedAt;

  factory PaccAvailabilityModel.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] == 2 && json['weekdays'] is Map) {
      final rawDays = Map<String, dynamic>.from(json['weekdays'] as Map);
      final days = <int, PaccDaySchedule>{for (var day = 1; day <= 7; day++) day: PaccDaySchedule.fromJson(Map<String, dynamic>.from(rawDays['$day'] as Map? ?? const {}))};
      final rawOverrides = json['overrides'] as List? ?? const [];
      return PaccAvailabilityModel.v2(weekdays: _withClosedWeekends(days), overrides: rawOverrides.whereType<Map>().map((value) => PaccDateOverride.fromJson(Map<String, dynamic>.from(value))).toList(), notice: json['notice']?.toString().trim() ?? '', revision: (json['revision'] as num?)?.toInt() ?? 0, updatedAt: dateTimeFromFirestore(json['updatedAt']));
    }
    final openDays = (json['openDays'] as List? ?? const [1, 2, 3, 4, 5]).whereType<num>().map((value) => value.toInt()).where((day) => day >= 1 && day <= 7).toList();
    final opensAt = json['opensAt']?.toString() ?? '08:00'; final closesAt = json['closesAt']?.toString() ?? '17:00'; final presence = CounselorPresence.parse(json['presence']); final walks = json['acceptsWalkIns'] == true;
    final days = <int, PaccDaySchedule>{for (var day = 1; day <= 7; day++) day: day <= 5 && openDays.contains(day) ? PaccDaySchedule(enabled: true, opensAt: opensAt, closesAt: closesAt, presence: presence, appointmentsEnabled: true, acceptsWalkIns: walks) : PaccDaySchedule.closed};
    final dates = (json['blackoutDates'] as List? ?? const []).map((value) => value.toString().trim()).where((value) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)).toList();
    return PaccAvailabilityModel.v2(weekdays: days, overrides: dates.map((date) => PaccDateOverride(date: date, closedAllDay: true)).toList(), notice: json['notice']?.toString().trim() ?? '', revision: (json['revision'] as num?)?.toInt() ?? 0, updatedAt: dateTimeFromFirestore(json['updatedAt']));
  }

  Map<int, PaccDaySchedule> get _effectiveWeekdays {
    if (weekdays.length == 7) return _withClosedWeekends(weekdays);
    return {for (var day = 1; day <= 7; day++) day: day <= 5 && openDays.contains(day) ? PaccDaySchedule(enabled: true, opensAt: opensAt, closesAt: closesAt, presence: presence, appointmentsEnabled: true, acceptsWalkIns: acceptsWalkIns) : PaccDaySchedule.closed};
  }
  Map<int, PaccDaySchedule> get effectiveWeekdays => Map.unmodifiable(_effectiveWeekdays);
  List<PaccDateOverride> get _effectiveOverrides => overrides.isNotEmpty ? overrides : blackoutDates.map((date) => PaccDateOverride(date: date, closedAllDay: true)).toList();

  Map<String, dynamic> toJson() => {'schemaVersion': 2, 'timezone': 'Asia/Manila', 'weekdays': {for (var day = 1; day <= 7; day++) '$day': _effectiveWeekdays[day]!.toJson()}, 'overrides': _effectiveOverrides.map((override) => override.toJson()).toList(), 'notice': notice.trim()};

  ResolvedPaccSchedule resolveScheduleAt(DateTime now) {
    final manila = now.toUtc().add(const Duration(hours: 8));
    final date = '${manila.year.toString().padLeft(4, '0')}-${manila.month.toString().padLeft(2, '0')}-${manila.day.toString().padLeft(2, '0')}';
    final override = _effectiveOverrides.where((item) => item.date == date).cast<PaccDateOverride?>().firstWhere((item) => item != null, orElse: () => null);
    final schedule = override?.closedAllDay == true ? PaccDaySchedule.closed : override?.schedule ?? _effectiveWeekdays[manila.weekday]!;
    final parts = (String value) { final split = value.split(':'); return int.parse(split[0]) * 60 + int.parse(split[1]); };
    final withinHours = manila.hour * 60 + manila.minute >= parts(schedule.opensAt) && manila.hour * 60 + manila.minute < parts(schedule.closesAt);
    final isOfficeOpen = schedule.enabled && withinHours;
    final canBook = isOfficeOpen && schedule.presence == CounselorPresence.inOffice && schedule.appointmentsEnabled;
    final walks = isOfficeOpen && schedule.acceptsWalkIns;
    final reason = !schedule.enabled ? (override?.reason.isNotEmpty == true ? override!.reason : 'Office is closed.') : !withinHours ? 'Office is closed at the selected time.' : schedule.presence != CounselorPresence.inOffice ? 'Counselor is unavailable.' : !schedule.appointmentsEnabled ? 'Appointments are unavailable.' : null;
    return ResolvedPaccSchedule(schedule: schedule, source: override == null ? PaccScheduleSource.weekly : PaccScheduleSource.override, date: date, weekday: manila.weekday, isOfficeOpen: isOfficeOpen, canBookAppointments: canBook, acceptsWalkIns: walks, closureReason: reason);
  }
  bool isOpenAt(DateTime now) => resolveScheduleAt(now).isOfficeOpen;
  String statusLabel(DateTime now) => isOpenAt(now) ? 'OPEN NOW' : 'CLOSED';

  static Map<int, PaccDaySchedule> _withClosedWeekends(Map<int, PaccDaySchedule> source) => {
    for (var day = 1; day <= 5; day++) day: source[day] ?? PaccDaySchedule.closed,
    6: PaccDaySchedule.closed,
    7: PaccDaySchedule.closed,
  };
}
