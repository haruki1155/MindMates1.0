import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';

void main() {
  const monday = PaccDaySchedule(
    enabled: true,
    opensAt: '08:00',
    closesAt: '17:00',
    presence: CounselorPresence.inOffice,
    appointmentsEnabled: true,
    acceptsWalkIns: true,
  );

  test('V2 model serializes seven weekdays without legacy fields', () {
    final model = PaccAvailabilityModel.v2(
      weekdays: {for (var day = 1; day <= 7; day++) day: monday},
      overrides: const [],
      notice: ' Office hours ',
      revision: 4,
    );

    final json = model.toJson();

    expect(json['schemaVersion'], 2);
    expect((json['weekdays'] as Map).length, 7);
    expect(json.containsKey('openDays'), isFalse);
    expect(json['notice'], 'Office hours');
  });

  test('serialization forces Saturday and Sunday closed', () {
    final model = PaccAvailabilityModel.v2(
      weekdays: {for (var day = 1; day <= 7; day++) day: monday},
      overrides: const [],
    );

    final weekdays = (model.toJson()['weekdays'] as Map).cast<String, dynamic>();

    expect(weekdays['6']['enabled'], isFalse);
    expect(weekdays['6']['appointmentsEnabled'], isFalse);
    expect(weekdays['7']['enabled'], isFalse);
    expect(weekdays['7']['acceptsWalkIns'], isFalse);
  });

  test('V1 model normalizes blackout dates and ignores server metadata', () {
    final model = PaccAvailabilityModel.fromJson({
      'openDays': [1, 2, 3, 4, 5],
      'opensAt': '08:00',
      'closesAt': '17:00',
      'presence': 'in_office',
      'acceptsWalkIns': true,
      'blackoutDates': ['2026-09-24'],
      'updatedAt': {'seconds': 1},
      'revision': 9,
    });

    expect(model.schemaVersion, 2);
    expect(model.weekdays[1]!.appointmentsEnabled, isTrue);
    expect(model.overrides.single.closedAllDay, isTrue);
  });

  test('effective status uses Manila-local override and separates services', () {
    final model = PaccAvailabilityModel.v2(
      weekdays: {for (var day = 1; day <= 7; day++) day: monday},
      overrides: const [
        PaccDateOverride(
          date: '2026-09-24',
          closedAllDay: false,
          schedule: PaccDaySchedule(
            enabled: true,
            opensAt: '10:00',
            closesAt: '12:00',
            presence: CounselorPresence.inOffice,
            appointmentsEnabled: false,
            acceptsWalkIns: true,
          ),
          reason: 'Reduced hours',
        ),
      ],
    );

    final status = model.resolveScheduleAt(DateTime.utc(2026, 9, 24, 3));

    expect(status.source, PaccScheduleSource.override);
    expect(status.isOfficeOpen, isTrue);
    expect(status.canBookAppointments, isFalse);
    expect(status.acceptsWalkIns, isTrue);
  });

  test('custom special-date schedule controls student appointment availability', () {
    final availability = PaccAvailabilityModel.v2(
      weekdays: {for (var day = 1; day <= 7; day++) day: PaccDaySchedule.closed},
      overrides: const [
        PaccDateOverride(
          date: '2026-10-01',
          closedAllDay: false,
          reason: 'University event schedule',
          schedule: PaccDaySchedule(
            enabled: true,
            opensAt: '08:00',
            closesAt: '12:00',
            presence: CounselorPresence.inOffice,
            appointmentsEnabled: true,
            acceptsWalkIns: true,
          ),
        ),
      ],
    );

    final resolved = availability.resolveScheduleAt(DateTime.utc(2026, 10, 1));
    expect(resolved.source, PaccScheduleSource.override);
    expect(resolved.canBookAppointments, isTrue);
    expect(resolved.acceptsWalkIns, isTrue);
    expect(resolved.schedule.opensAt, '08:00');
  });
}
