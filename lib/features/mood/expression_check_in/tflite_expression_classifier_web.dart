import 'package:image/image.dart' as img;
import 'expression_scan_logic.dart';

/// Browser fallback. Android/iOS continue using the original TFLite adapter.
class TfliteExpressionClassifier {
  static const assetPath =
      'assets/models/expression/emotion_model_quantized.tflite';
  static const modelVersion = 'justinshenk_fer_tflite_v1';

  bool get isInitialized => false;

  Future<void> initialize() async => throw UnsupportedError(
    'Expression TFLite inference requires Android or iOS.',
  );

  ExpressionModelOutput classify(img.Image preparedFace) =>
      throw UnsupportedError(
        'Expression TFLite inference requires Android or iOS.',
      );

  void dispose() {}
}
