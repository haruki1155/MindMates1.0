import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/services/firebase/callable_request_timeout.dart';

void main() {
  test('returns a callable value that completes within its deadline', () async {
    final value = await runBoundedCallable<String>(
      operation: 'test_callable',
      timeout: const Duration(milliseconds: 10),
      request: () async => 'ok',
    );

    expect(value, 'ok');
  });

  test('throws a recoverable timeout when a callable never completes', () async {
    final pending = Completer<String>();

    await expectLater(
      runBoundedCallable<String>(
        operation: 'test_callable',
        timeout: const Duration(milliseconds: 1),
        request: () => pending.future,
      ),
      throwsA(isA<CallableRequestTimeoutException>()),
    );
  });
}
