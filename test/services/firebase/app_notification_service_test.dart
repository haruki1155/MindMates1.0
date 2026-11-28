import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/firebase/app_notification_service.dart';

void main() {
  for (final type in ['mood_reminder', 'breathing_reminder']) {
    test('opened $type FCM messages dispatch the recognized reminder type', () {
      String? openedType;
      AppNotificationService.dispatchOpenedMessage(
        RemoteMessage(data: {'type': type}),
        onSelfCareReminderOpened: (value) => openedType = value,
      );

      expect(openedType, type);
    });
  }

  test('unknown FCM types do not dispatch a self-care destination', () {
    var opened = false;
    AppNotificationService.dispatchOpenedMessage(
      const RemoteMessage(data: {'type': 'unknown_reminder'}),
      onSelfCareReminderOpened: (_) => opened = true,
    );
    expect(opened, isFalse);
    expect(RouteNames.selfCareReminderRoute('unknown_reminder'), isNull);
  });

  test('existing inquiry and appointment dispatch keeps its precedence', () {
    final opened = <String>[];
    AppNotificationService.dispatchOpenedMessage(
      const RemoteMessage(
        data: {
          'type': 'mood_reminder',
          'inquiryId': ' inquiry-1 ',
          'appointmentId': 'appointment-1',
        },
      ),
      onInquiryOpened: (value) => opened.add('inquiry:$value'),
      onAppointmentOpened: (value) => opened.add('appointment:$value'),
      onSelfCareReminderOpened: (value) => opened.add('reminder:$value'),
    );
    expect(opened, ['inquiry:inquiry-1']);

    AppNotificationService.dispatchOpenedMessage(
      const RemoteMessage(
        data: {'type': 'breathing_reminder', 'appointmentId': 'appointment-2'},
      ),
      onAppointmentOpened: (value) => opened.add('appointment:$value'),
      onSelfCareReminderOpened: (value) => opened.add('reminder:$value'),
    );
    expect(opened.last, 'appointment:appointment-2');
  });
}
