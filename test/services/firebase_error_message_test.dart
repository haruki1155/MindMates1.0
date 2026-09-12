import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/services/firebase/firebase_error_message.dart';
import 'package:flutter/foundation.dart';

void main() {
  test('App Check instructions are platform-specific', () {
    expect(
      FirebaseErrorMessage.appCheckMessage(
        web: true,
        webHost: 'mind-mates-cd2cf.web.app',
      ),
      contains('reCAPTCHA Enterprise'),
    );
    expect(
      FirebaseErrorMessage.appCheckMessage(web: true, webHost: 'localhost'),
      contains('debug token'),
    );
    expect(
      FirebaseErrorMessage.appCheckMessage(
        web: false,
        platform: TargetPlatform.android,
        debugMode: true,
      ),
      contains('debug token'),
    );
    expect(
      FirebaseErrorMessage.appCheckMessage(
        web: false,
        platform: TargetPlatform.iOS,
        debugMode: false,
      ),
      contains('DeviceCheck'),
    );
  });

  test('App Check throttling gives localhost recovery steps', () {
    expect(
      FirebaseErrorMessage.appCheckThrottleMessage(
        web: true,
        webHost: '127.0.0.1',
      ),
      allOf(contains('throttled'), contains('clear localhost site data')),
    );
  });
  test('maps Firestore permission errors to an actionable message', () {
    final message = FirebaseErrorMessage.describe(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      fallback: 'fallback',
    );

    expect(message, 'You do not have permission to complete this action.');
    expect(message, isNot(contains('Firestore')));
    expect(message, isNot(contains('rules')));
    expect(message, isNot('fallback'));
  });

  test('maps callable App Check errors to an actionable message', () {
    final message = FirebaseErrorMessage.describe(
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Firebase App Check token was rejected.',
      ),
      fallback: 'fallback',
    );

    expect(message, contains('App Check'));
  });

  test(
    'keeps unauthenticated errors distinct when App Check is configured',
    () {
      final message = FirebaseErrorMessage.describe(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Authentication expired.',
        ),
        fallback: 'fallback',
      );

      expect(message, 'Please sign in again to continue.');
    },
  );

  test('preserves a feature fallback for unknown errors', () {
    expect(
      FirebaseErrorMessage.describe(
        StateError('unknown'),
        fallback: 'Unable to save journal.',
      ),
      'Unable to save journal.',
    );
  });
}
