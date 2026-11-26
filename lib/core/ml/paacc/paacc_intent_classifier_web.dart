import 'intent_prediction.dart';
import 'paacc_ml_exception.dart';

/// Browser fallback: the native TensorFlow Lite runtime requires dart:ffi.
class PaaccIntentClassifier {
  static Future<PaaccIntentClassifier> create() async =>
      throw const PaaccMlException(
        'On-device PACC inference is unavailable on Web.',
      );

  IntentPrediction predict(String text) => throw const PaaccMlException(
    'On-device PACC inference is unavailable on Web.',
  );

  void dispose() {}
}
