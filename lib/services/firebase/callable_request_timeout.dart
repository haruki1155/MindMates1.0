import 'dart:async';

import 'firebase_runtime_diagnostics.dart';

class CallableRequestTimeoutException extends TimeoutException {
  CallableRequestTimeoutException({
    required this.operation,
    required Duration timeout,
  }) : super('$operation did not complete within ${timeout.inSeconds} seconds.', timeout);

  final String operation;
}

Future<T> runBoundedCallable<T>({
  required String operation,
  required Duration timeout,
  required Future<T> Function() request,
}) async {
  FirebaseRuntimeDiagnostics.log(event: 'callable_${operation}_started');
  try {
    final value = await request().timeout(timeout);
    FirebaseRuntimeDiagnostics.log(event: 'callable_${operation}_succeeded');
    return value;
  } on TimeoutException {
    final timeoutError = CallableRequestTimeoutException(
      operation: operation,
      timeout: timeout,
    );
    FirebaseRuntimeDiagnostics.log(
      event: 'callable_${operation}_timed_out',
      error: timeoutError,
    );
    throw timeoutError;
  } catch (error) {
    FirebaseRuntimeDiagnostics.log(
      event: 'callable_${operation}_failed',
      error: error,
    );
    rethrow;
  }
}
