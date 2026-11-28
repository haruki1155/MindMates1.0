import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../database/firestore_collections.dart';
import '../../routes/route_names.dart';
import 'firestore_service.dart';

class AppNotificationService {
  AppNotificationService({this.messaging, FirestoreService? firestoreService})
    : _firestoreService = firestoreService ?? FirestoreService();

  FirebaseMessaging? messaging;
  final FirestoreService _firestoreService;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  FirebaseMessaging get _instance => messaging ??= FirebaseMessaging.instance;

  Future<void> initializeForUser(
    String userId, {
    void Function(String appointmentId)? onAppointmentOpened,
    void Function(String inquiryId)? onInquiryOpened,
    void Function(String reminderType)? onSelfCareReminderOpened,
    void Function(RemoteMessage message)? onForegroundMessage,
  }) async {
    final settings = await _instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final vapidKey = const String.fromEnvironment('FCM_VAPID_KEY');
    final token = await _instance.getToken(
      vapidKey: vapidKey.isEmpty ? null : vapidKey,
    );
    if (token != null && token.isNotEmpty) await _saveToken(userId, token);

    await _tokenSubscription?.cancel();
    _tokenSubscription = _instance.onTokenRefresh.listen(
      (token) => _saveToken(userId, token),
    );
    await _openedSubscription?.cancel();
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      dispatchOpenedMessage(
        message,
        onAppointmentOpened: onAppointmentOpened,
        onInquiryOpened: onInquiryOpened,
        onSelfCareReminderOpened: onSelfCareReminderOpened,
      );
    });
    final initial = await _instance.getInitialMessage();
    if (initial != null) {
      dispatchOpenedMessage(
        initial,
        onAppointmentOpened: onAppointmentOpened,
        onInquiryOpened: onInquiryOpened,
        onSelfCareReminderOpened: onSelfCareReminderOpened,
      );
    }
    await _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      onForegroundMessage,
    );
  }

  @visibleForTesting
  static void dispatchOpenedMessage(
    RemoteMessage message, {
    void Function(String appointmentId)? onAppointmentOpened,
    void Function(String inquiryId)? onInquiryOpened,
    void Function(String reminderType)? onSelfCareReminderOpened,
  }) {
    final inquiryId = message.data['inquiryId']?.toString().trim() ?? '';
    if (inquiryId.isNotEmpty) {
      onInquiryOpened?.call(inquiryId);
      return;
    }
    final appointmentId =
        message.data['appointmentId']?.toString().trim() ?? '';
    if (appointmentId.isNotEmpty) {
      onAppointmentOpened?.call(appointmentId);
      return;
    }
    final type = message.data['type']?.toString().trim().toLowerCase() ?? '';
    if (RouteNames.selfCareReminderRoute(type) != null) {
      onSelfCareReminderOpened?.call(type);
    }
  }

  Future<void> _saveToken(String userId, String token) {
    return _firestoreService.setDocument(
      '${FirestoreCollections.userDevices}/$userId/tokens',
      token,
      {
        'token': token,
        'fcmToken': token,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
        'lastActiveAt': DateTime.now(),
      },
      merge: true,
    );
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
  }
}
