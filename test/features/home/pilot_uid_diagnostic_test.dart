import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/config/app_environment.dart';
import 'package:mind_mates/features/home/widgets/pilot_uid_diagnostic.dart';

void main() {
  test('matching, mismatching and missing UIDs return only safe outcomes', () {
    expect(checkPilotUid(() => 'mood-v2-pilot-student-001'), 'PILOT_MATCH');
    expect(checkPilotUid(() => 'private-other-uid'), 'PILOT_MISMATCH');
    expect(checkPilotUid(() => null), 'NOT_SIGNED_IN');
  });

  test(
    'reader failure returns CHECK_FAILED without exposing error content',
    () {
      expect(
        checkPilotUid(() => throw StateError('private credential')),
        'CHECK_FAILED',
      );
    },
  );

  test('production, development, profile and release builds are disabled', () {
    for (final environment in AppEnvironment.values) {
      expect(
        pilotDiagnosticEnabled(debugBuild: false, environment: environment),
        isFalse,
      );
    }
    expect(
      pilotDiagnosticEnabled(
        debugBuild: true,
        environment: AppEnvironment.production,
      ),
      isFalse,
    );
    expect(
      pilotDiagnosticEnabled(
        debugBuild: true,
        environment: AppEnvironment.development,
      ),
      isFalse,
    );
    expect(
      pilotDiagnosticEnabled(
        debugBuild: true,
        environment: AppEnvironment.staging,
      ),
      isTrue,
    );
  });

  testWidgets(
    'widget is gated and never displays actual identity or exception',
    (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PilotUidDiagnostic(
              readUid: () {
                reads++;
                return 'private-other-uid';
              },
            ),
          ),
        ),
      );
      expect(reads, 0);
      if (!AppEnvironmentConfig.isStaging) {
        expect(find.text('Verify pilot session'), findsNothing);
        expect(find.byKey(const ValueKey('pilot-uid-outcome')), findsNothing);
        return;
      }
      await tester.tap(find.text('Verify pilot session'));
      await tester.pump();
      expect(reads, 1);
      expect(find.text('PILOT_MISMATCH'), findsOneWidget);
      expect(find.textContaining('private-other-uid'), findsNothing);
    },
  );
}
