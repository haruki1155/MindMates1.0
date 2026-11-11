import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';
import '../test/features/mood/mood_visual_acceptance_test.dart' as acceptance;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  acceptance.moodVisualAcceptance(
    screenshot: (name) async {
      await binding.runAsync(() async {
        debugPrint('MOOD_CAPTURE:$name');
        await Future<void>.delayed(const Duration(seconds: 5));
      });
    },
  );
}
