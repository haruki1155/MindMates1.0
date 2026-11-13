// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
    StandardMessageCodec(),
  );
  final requests = <Map<Object?, Object?>>[];
  String? failure;
  setUpAll(() async {
    await Firebase.initializeApp();
  });
  setUp(() {
    requests.clear();
    failure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (message) async {
          requests.add((message as List).single as Map<Object?, Object?>);
          if (failure != null) {
            return [
              failure,
              'Refresh and retry',
              {'code': failure, 'message': 'Refresh and retry'},
            ];
          }
          return [<String, Object?>{}];
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null),
  );
  final original = DateTime.utc(2027, 1, 5, 1);
  Future<void> submit({String requestId = 'edit-original', int offset = 1}) =>
      AppointmentRepository().rescheduleAppointment(
        appointmentId: 'actual-appointment',
        expectedScheduledAt: original,
        expectedScheduleRevision: 7,
        scheduledAt: original.add(Duration(hours: offset)),
        requestId: requestId,
      );
  test(
    'invokes student callable with opened schedule and authoritative revision',
    () async {
      await submit();
      expect(requests.single['functionName'], 'rescheduleStudentAppointment');
      expect(requests.single['parameters'], {
        'appointmentId': 'actual-appointment',
        'expectedScheduledAt': original.millisecondsSinceEpoch,
        'expectedScheduleRevision': 7,
        'scheduledAt': original
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        'requestId': 'edit-original',
      });
    },
  );
  for (final code in [
    'aborted',
    'already-exists',
    'permission-denied',
    'unauthenticated',
    'unavailable',
    'deadline-exceeded',
  ]) {
    test('propagates $code without losing retry identity', () async {
      failure = code;
      await expectLater(
        submit(),
        throwsA(
          isA<FirebaseFunctionsException>().having((e) => e.code, 'code', code),
        ),
      );
      failure = null;
      await submit();
      expect(requests[0]['parameters'], requests[1]['parameters']);
      await submit(requestId: 'edit-new-selection', offset: 2);
      expect(
        (requests.last['parameters'] as Map)['requestId'],
        'edit-new-selection',
      );
      expect(
        (requests.last['parameters'] as Map)['scheduledAt'],
        original.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
    });
  }
}
