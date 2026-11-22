import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/services/firebase/firebase_error_message.dart';
import 'package:mind_mates/services/firebase/firebase_runtime_diagnostics.dart';
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

  test(
    'maps Storage unauthorized and object-not-found safely without App Check confusion',
    () {
      final unauthorized = FirebaseErrorMessage.describe(
        FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
        fallback: 'Unable to download this private file.',
      );
      expect(
        unauthorized,
        'You do not have permission to complete this action.',
      );
      expect(unauthorized, isNot(contains('App Check')));

      final missing = FirebaseErrorMessage.describe(
        FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
        fallback: 'Unable to download this private file.',
      );
      expect(missing, isNot(contains('App Check')));
      expect(missing.toLowerCase(), anyOf(contains('not'), contains('unable')));
    },
  );

  test(
    'never exposes raw INTERNAL messages from FirebaseFunctionsException',
    () {
      final message = FirebaseErrorMessage.describe(
        FirebaseFunctionsException(code: 'internal', message: 'INTERNAL'),
        fallback: 'Something went wrong. Please try again.',
      );
      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot('INTERNAL'));
    },
  );

  test(
    'suppresses all internal error variants, paths, tokens, and stack details',
    () {
      const fallback = 'Unable to mark inquiry as resolved.';
      for (final rawMessage in const [
        'internal',
        'Internal error encountered.',
        'INTERNAL: Cannot read properties of undefined',
        'projects/mindmate-staging/databases/(default)/documents/inquiries/i1 token=secret',
      ]) {
        final result = FirebaseErrorMessage.describe(
          FirebaseFunctionsException(code: 'internal', message: rawMessage),
          fallback: fallback,
        );
        expect(result, fallback, reason: 'Failed for rawMessage="$rawMessage"');
        expect(result.toLowerCase(), isNot(contains('internal')));
        expect(result, isNot(contains('projects/')));
        expect(result, isNot(contains('token=')));
      }
    },
  );

  test('normalizes uppercase Firebase error codes', () {
    const fallback = 'Unable to mark inquiry as resolved.';
    expect(
      FirebaseErrorMessage.describe(
        FirebaseFunctionsException(code: 'INTERNAL', message: 'boom'),
        fallback: fallback,
      ),
      fallback,
    );
    expect(
      FirebaseErrorMessage.describe(
        FirebaseFunctionsException(code: 'UNAVAILABLE', message: 'UNAVAILABLE'),
        fallback: fallback,
      ),
      'The connection to MindMates is unavailable. Check your internet connection and try again.',
    );
  });

  test(
    'maps generic unavailable messages to connection help while keeping safe specific messages',
    () {
      const fallback = 'Unable to send verification.';
      for (final rawMessage in const ['unavailable', 'UNAVAILABLE']) {
        expect(
          FirebaseErrorMessage.describe(
            FirebaseFunctionsException(
              code: 'unavailable',
              message: rawMessage,
            ),
            fallback: fallback,
          ),
          'The connection to MindMates is unavailable. Check your internet connection and try again.',
        );
      }

      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The verification email could not be delivered.',
          ),
          fallback: fallback,
        ),
        'The verification email could not be delivered.',
      );
    },
  );

  test(
    'suppresses generic SDK code names and sensitive details for failed-precondition, invalid-argument, and not-found while preserving actionable messages',
    () {
      const fallback = 'Unable to mark inquiry as resolved.';
      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'FAILED_PRECONDITION',
          ),
          fallback: fallback,
        ),
        'This action cannot be completed yet. Check your profile and try again.',
      );
      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'),
          fallback: fallback,
        ),
        fallback,
      );
      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: 'invalid-argument',
            message:
                'Exception: https://example.test/projects/mindmate-staging/databases/(default)/documents/inquiries/i1 Bearer abc token=xyz',
          ),
          fallback: fallback,
        ),
        'Some information is invalid or missing. Check your entries and try again.',
      );

      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message:
                'Acknowledge receipt before marking this inquiry as resolved.',
          ),
          fallback: fallback,
        ),
        'Acknowledge receipt before marking this inquiry as resolved.',
      );
      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message:
                'This inquiry was updated by someone else. Reload and try again.',
          ),
          fallback: fallback,
        ),
        'This inquiry was updated by someone else. Reload and try again.',
      );
      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: 'not-found',
            message: 'Inquiry not found.',
          ),
          fallback: fallback,
        ),
        'Inquiry not found.',
      );
    },
  );

  test('maps deadline-exceeded to the timeout recovery message', () {
    expect(
      FirebaseErrorMessage.describe(
        FirebaseFunctionsException(
          code: 'deadline-exceeded',
          message: 'DEADLINE_EXCEEDED',
        ),
        fallback: 'Unable to mark inquiry as resolved.',
      ),
      'MindMate did not respond in time. Your request may still be processing; check your connection before trying again.',
    );
  });

  test(
    'firebaseErrorCode strips functions/ prefix after trimming and lowercasing',
    () {
      expect(
        FirebaseRuntimeDiagnostics.firebaseErrorCode(
          FirebaseFunctionsException(
            code: ' functions/internal ',
            message: 'x',
          ),
        ),
        'internal',
      );
      expect(
        FirebaseRuntimeDiagnostics.firebaseErrorCode(
          FirebaseFunctionsException(
            code: ' functions/unavailable ',
            message: 'unavailable',
          ),
        ),
        'unavailable',
      );
      expect(
        FirebaseRuntimeDiagnostics.firebaseErrorCode(
          FirebaseFunctionsException(
            code: 'FUNCTIONS/FAILED-PRECONDITION',
            message: 'x',
          ),
        ),
        'failed-precondition',
      );
    },
  );

  test(
    'internal codes are never hijacked by profile or App Check message heuristics',
    () {
      const fallback = 'Unable to mark inquiry as resolved.';
      for (final code in const [
        'internal',
        'INTERNAL',
        ' functions/internal ',
      ]) {
        for (final msg in const [
          'Firestore profile document missing at projects/p/documents/users/1',
          'App Check token missing in projects/p/databases/(default)/documents/inquiries/1',
        ]) {
          final result = FirebaseErrorMessage.describe(
            FirebaseFunctionsException(code: code, message: msg),
            fallback: fallback,
          );
          expect(
            result,
            fallback,
            reason: 'Hijacked code="$code" msg="$msg" -> "$result"',
          );
        }
      }
    },
  );

  test(
    'passthrough codes suppress internal prose, Error/RangeError/FirebaseError prefixes, JS runtime errors, paths, mid-line stack frames, and encoded URLs while preserving lowercase prose',
    () {
      const fallback = 'Unable to mark inquiry as resolved.';
      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: ' functions/unavailable ',
            message: 'unavailable',
          ),
          fallback: fallback,
        ),
        'The connection to MindMates is unavailable. Check your internet connection and try again.',
      );

      const unsafeMessages = [
        'Internal error',
        'Internal server error',
        'INTERNAL: upstream connection failed',
        'Error: ECONNREFUSED 127.0.0.1:8080',
        'Error: invalid payload',
        'RangeError: Maximum call stack size exceeded',
        'FirebaseError: upstream timeout',
        "Cannot read properties of undefined (reading 'status')",
        "Cannot read property 'uid' of null",
        'handler is not a function',
        'undefined is not an object',
        'Failed at resolveInquiry (/workspace/functions/lib/index.js:42:5)',
        'Failed at lookup (/app/lib/index.js:12)',
        r'C:\Users\dev\functions\src\index.ts:99',
        'https://cloudfunctions.net/v1/projects%2fp/token%3dsecret',
        'Request to firestore.googleapis.com failed',
      ];
      for (final code in const [
        'unavailable',
        'failed-precondition',
        'invalid-argument',
        'not-found',
        'already-exists',
      ]) {
        for (final msg in unsafeMessages) {
          final result = FirebaseErrorMessage.describe(
            FirebaseFunctionsException(code: code, message: msg),
            fallback: fallback,
          );
          expect(
            result,
            isNot(msg),
            reason: 'Leaked passthrough for code="$code" msg="$msg"',
          );
        }
      }

      // Legitimate lowercase-start prose on invalid-argument is preserved.
      expect(
        FirebaseErrorMessage.describe(
          FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'at least 3 characters are required.',
          ),
          fallback: fallback,
        ),
        'at least 3 characters are required.',
      );
    },
  );

  test(
    'passthrough codes suppress prefixed Exception prefixes, underscore-delimited internal tokens, forward-slash Windows paths, and WebKit null errors while preserving legitimate prose',
    () {
      const fallback = 'Unable to mark inquiry as resolved.';
      const expectedByCode = <String, String>{
        'unavailable':
            'The connection to MindMates is unavailable. Check your internet connection and try again.',
        'failed-precondition':
            'This action cannot be completed yet. Check your profile and try again.',
        'invalid-argument':
            'Some information is invalid or missing. Check your entries and try again.',
        'not-found': fallback,
        'already-exists':
            'This information has already been saved for your account.',
      };

      const bypassedMessages = [
        'FirebaseFunctionsException: crash',
        'TimeoutException: upstream timed out',
        'PlatformException: channel failed',
        'internal_error',
        'Internal_error',
        'my_internal_failure',
        'C:/secret/config.json',
        'null is not an object',
      ];

      for (final entry in expectedByCode.entries) {
        for (final msg in bypassedMessages) {
          final result = FirebaseErrorMessage.describe(
            FirebaseFunctionsException(code: entry.key, message: msg),
            fallback: fallback,
          );
          expect(
            result,
            isNot(msg),
            reason: 'Leaked passthrough for code="${entry.key}" msg="$msg"',
          );
          expect(
            result,
            entry.value,
            reason:
                'Unexpected fallback for code="${entry.key}" msg="$msg": "$result"',
          );
        }
      }

      for (final safeMessage in const [
        'Student has internalized negative feedback.',
        'External coordinator approval is required.',
        'at least 3 characters are required.',
        'Network error',
      ]) {
        for (final code in expectedByCode.keys) {
          expect(
            FirebaseErrorMessage.describe(
              FirebaseFunctionsException(code: code, message: safeMessage),
              fallback: fallback,
            ),
            safeMessage,
            reason:
                'Legitimate message falsely suppressed for code="$code" msg="$safeMessage"',
          );
        }
      }
    },
  );
}
