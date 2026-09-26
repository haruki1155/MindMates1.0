import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/repositories/pacc_availability_repository.dart';

const _openDay = PaccDaySchedule(
  enabled: true,
  opensAt: '09:00',
  closesAt: '17:00',
  presence: CounselorPresence.inOffice,
  appointmentsEnabled: true,
  acceptsWalkIns: false,
);

PaccAvailabilityModel _schedule({int revision = 7}) =>
    PaccAvailabilityModel.v2(
      weekdays: {for (var day = 1; day <= 7; day++) day: _openDay},
      overrides: const [],
      notice: 'Office hours',
      revision: revision,
    );

void main() {
  test('reads V2 and legacy V1 schedule documents without mutating either', () async {
    final repository = PaccAvailabilityRepository(
      watchCurrentSource: () => Stream.fromIterable([
        {
          'schemaVersion': 2,
          'weekdays': {for (var day = 1; day <= 7; day++) '$day': _openDay.toJson()},
          'overrides': const [],
          'notice': 'V2',
          'revision': 4,
        },
        {
          'openDays': [1, 2, 3, 4, 5],
          'opensAt': '08:00',
          'closesAt': '16:00',
          'presence': 'in_office',
          'acceptsWalkIns': true,
          'blackoutDates': ['2027-01-04'],
          'revision': 0,
        },
      ]),
    );

    final schedules = await repository
        .watchCurrent()
        .where((schedule) => schedule != null)
        .map((schedule) => schedule!)
        .toList();

    expect(schedules[0].revision, 4);
    expect(schedules[0].notice, 'V2');
    expect(schedules[1].weekdays[1]!.opensAt, '08:00');
    expect(schedules[1].overrides.single.date, '2027-01-04');
  });

  test('sends a V2-only callable payload with revision and confirmed conflicts', () async {
    Map<String, dynamic>? sent;
    final repository = PaccAvailabilityRepository(
      saveCallable: (payload) async {
        sent = payload;
        return {
          'ok': true,
          'revision': 8,
          'conflicts': [
            {
              'appointmentId': 'appointment-1',
              'status': 'confirmed',
              'timestamp': 1,
              'reason': 'Office is closed.',
            },
          ],
        };
      },
    );

    final result = await repository.savePaccAvailability(
      _schedule(),
      confirmConflicts: true,
    );

    expect(sent!['expectedRevision'], 7);
    expect(sent!['confirmConflicts'], true);
    expect((sent!['availability'] as Map).keys, {
      'schemaVersion',
      'timezone',
      'weekdays',
      'overrides',
      'notice',
    });
    expect(result.revision, 8);
    expect(result.conflicts.single.appointmentId, 'appointment-1');
  });

  test('propagates callable save errors', () async {
    final repository = PaccAvailabilityRepository(
      saveCallable: (_) => Future<Map<String, dynamic>>.error(
        StateError('Schedule revision is stale.'),
      ),
    );

    await expectLater(
      repository.savePaccAvailability(_schedule()),
      throwsA(isA<StateError>()),
    );
  });
}
