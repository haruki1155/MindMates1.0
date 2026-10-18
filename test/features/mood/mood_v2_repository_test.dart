import 'package:flutter_test/flutter_test.dart';

import 'package:mind_mates/features/mood/config/mood_v2_feature_flag.dart';
import 'package:mind_mates/repositories/mood_v2_repository.dart';

void main() {
  test('Mood V2 repository is inert until its rollout flag is explicitly enabled',
      () async {
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
  });
}
