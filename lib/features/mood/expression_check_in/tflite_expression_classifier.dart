import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'expression_scan_logic.dart';

/// On-device adapter for the MIT-licensed justinshenk/fer model.
///
/// It accepts an already upright, isolated face image. Camera handling, face
/// detection, persistence, and UI deliberately remain outside this class.
class TfliteExpressionClassifier {
  static const assetPath =
      'assets/models/expression/emotion_model_quantized.tflite';
  static const modelVersion = 'justinshenk_fer_tflite_v1';

  Interpreter? _interpreter;

  bool get isInitialized => _interpreter != null;

  Future<void> initialize() async {
    if (_interpreter != null) return;
    final interpreter = await Interpreter.fromAsset(assetPath);
    try {
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      _validateModelContract(input, output);
      if (kDebugMode) {
        debugPrint(
          'Expression model loaded. '
          'Input: ${input.shape} ${input.type}; '
          'Output: ${output.shape} ${output.type}',
        );
      }
      _interpreter = interpreter;
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  ExpressionModelOutput classify(img.Image preparedFace) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Expression classifier is not initialized.');
    }

    final grayscale = img.grayscale(preparedFace);
    final resized = img.copyResize(grayscale, width: 64, height: 64);
    var minimum = 1.0;
    var maximum = -1.0;
    final input = <List<List<List<double>>>>[
      List<List<List<double>>>.generate(
        64,
        (y) => List<List<double>>.generate(64, (x) {
          final pixel = resized.getPixel(x, y);
          final value = ((pixel.r / 255.0) - 0.5) * 2.0;
          if (value < minimum) minimum = value;
          if (value > maximum) maximum = value;
          return <double>[value];
        }, growable: false),
        growable: false,
      ),
    ];
    if (kDebugMode) {
      debugPrint(
        'Expression input: 64x64 grayscale float32; '
        'normalized min=$minimum max=$maximum',
      );
    }
    final output = <List<double>>[List<double>.filled(7, 0)];
    interpreter.run(input, output);
    return ExpressionModelOutput(scores: output.first);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  static void _validateModelContract(Tensor input, Tensor output) {
    final inputShape = input.shape;
    final outputShape = output.shape;
    final isSupported =
        input.type == TensorType.float32 &&
        output.type == TensorType.float32 &&
        inputShape.length == 4 &&
        inputShape[0] == 1 &&
        inputShape[1] == 64 &&
        inputShape[2] == 64 &&
        inputShape[3] == 1 &&
        outputShape.length == 2 &&
        outputShape[0] == 1 &&
        outputShape[1] == 7;
    if (!isSupported) {
      throw StateError(
        'Unsupported expression model tensor contract: '
        'input=$inputShape ${input.type}, output=$outputShape ${output.type}.',
      );
    }
  }
}
