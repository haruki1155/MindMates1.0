import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mind_mates/core/config/app_environment.dart';
import 'package:mind_mates/features/mood/config/mood_v2_feature_flag.dart';
import 'package:mind_mates/features/mood/domain/mood_v2_compatibility.dart';
import 'package:mind_mates/repositories/mood_v2_repository.dart';

class _Reached implements Exception {}

class _FakeCallable extends Fake implements HttpsCallable {
  _FakeCallable(this.calls, this.name);
  final List<(String, Object?)> calls;
  final String name;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) {
    calls.add((name, parameters));
    throw _Reached();
  }
}

class _FakeFunctions extends Fake implements FirebaseFunctions {
  final calls = <(String, Object?)>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _FakeCallable(calls, name);
}

class _FakeFirestore extends Fake implements FirebaseFirestore {
  final collections = <String>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    collections.add(path);
    throw _Reached();
  }
}

void main() {
  const verifyWriterOnlyPilot = bool.fromEnvironment(
    'VERIFY_MOOD_V2_WRITER_ONLY_PILOT',
    defaultValue: false,
  );

  test(
    'Mood V2 repository is inert while the writer flag is off',
    () async {
      if (verifyWriterOnlyPilot || MoodV2FeatureFlag.enabled) return;
      final repository = MoodV2Repository();

      expect(MoodV2FeatureFlag.enabled, isFalse);
      await expectLater(
        repository.create(
          level: 3,
          clientRequestId: '00000000-0000-4000-8000-000000000001',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await repository.fetchHistory('another-user'), isEmpty);
    },
    skip: MoodV2FeatureFlag.enabled,
  );

  test(
    'writer on: create reaches the createMoodEntry callable',
    () async {
      final functions = _FakeFunctions();
      final repository = MoodV2Repository(functions: functions);

      await expectLater(
        repository.create(
          level: 3,
          clientRequestId: '00000000-0000-4000-8000-000000000001',
        ),
        throwsA(isA<_Reached>()),
      );
      expect(functions.calls, hasLength(1));
      expect(functions.calls.single.$1, 'createMoodEntry');
      expect(
        functions.calls.single.$2,
        containsPair('clientRequestId', '00000000-0000-4000-8000-000000000001'),
      );
      expect(functions.calls.single.$2, containsPair('level', 3));
    },
    skip: !MoodV2FeatureFlag.enabled,
  );

  test(
    'writer on: fetchHistory queries instead of short-circuiting',
    () async {
      final firestore = _FakeFirestore();
      final repository = MoodV2Repository(firestore: firestore);

      await expectLater(
        repository.fetchHistory('some-user'),
        throwsA(isA<_Reached>()),
      );
      expect(firestore.collections, hasLength(1));
    },
    skip: !MoodV2FeatureFlag.enabled,
  );

  test('the compatibility readers default to disabled', () {
    if (verifyWriterOnlyPilot) return;
    // These stay false in every environment, staging included. The writer,
    // the five student-facing readers and the presentation flag follow the
    // staging build; see mood_v2_feature_flag_test.dart.
    expect([
      MoodV2ReadCompatibilityFlag.reportsEnabled,
      MoodV2ReadCompatibilityFlag.mindAidEnabled,
    ], everyElement(isFalse));
  });

  test(
    'writer, presentation and the five readers follow the staging build',
    () {
      if (verifyWriterOnlyPilot) return;
      expect([
        MoodV2FeatureFlag.enabled,
        MoodV2FeatureFlag.presentation,
        MoodV2FeatureFlag.providerRead,
        MoodV2FeatureFlag.homeRead,
        MoodV2FeatureFlag.profileRead,
        MoodV2FeatureFlag.historyRead,
        MoodV2FeatureFlag.insightsRead,
      ], everyElement(equals(AppEnvironmentConfig.isStagingBuild)));
    },
  );

  test('writer-only pilot does not enable any Mood V2 reader', () {
    if (!verifyWriterOnlyPilot) return;
    expect(MoodV2FeatureFlag.enabled, isTrue);
    expect([
      MoodV2FeatureFlag.providerRead,
      MoodV2FeatureFlag.homeRead,
      MoodV2FeatureFlag.profileRead,
      MoodV2FeatureFlag.historyRead,
      MoodV2FeatureFlag.insightsRead,
      MoodV2ReadCompatibilityFlag.reportsEnabled,
      MoodV2ReadCompatibilityFlag.mindAidEnabled,
    ], everyElement(isFalse));
  });
}
