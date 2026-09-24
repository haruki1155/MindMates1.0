import 'package:tflite_flutter/tflite_flutter.dart';

import 'intent_prediction.dart';
import 'paacc_ml_config.dart';
import 'paacc_ml_exception.dart';
import 'paacc_tokenizer.dart';

class PaaccIntentClassifier {
  final Interpreter _interpreter;
  final PaaccTokenizer _tokenizer;
  final PaaccMlConfig _config;
  bool _disposed = false;

  PaaccIntentClassifier._(this._interpreter, this._tokenizer, this._config);

  static Future<PaaccIntentClassifier> create() async {
    final config = await PaaccMlConfig.load();
    final tokenizer = await PaaccTokenizer.load(maxLength: config.maxLength);
    try {
      final interpreter = await Interpreter.fromAsset(
        'assets/ml/paacc_intent_model_v4.tflite',
      );
      final classifier = PaaccIntentClassifier._(
        interpreter,
        tokenizer,
        config,
      );
      try {
        classifier._validateTensorContract();
      } catch (_) {
        interpreter.close();
        rethrow;
      }
      return classifier;
    } catch (error) {
      if (error is PaaccMlException) rethrow;
      throw PaaccMlException('Failed to load PAACC model asset: $error');
    }
  }

  void _validateTensorContract() {
    final input = _interpreter.getInputTensor(0);
    final output = _interpreter.getOutputTensor(0);
    if (input.shape.length != 2 ||
        input.shape[0] != 1 ||
        input.shape[1] != _config.maxLength ||
        input.type != TensorType.int32) {
      throw const PaaccMlException('Unexpected PAACC input tensor contract.');
    }
    if (output.shape.length != 2 ||
        output.shape[0] != 1 ||
        output.shape[1] != _config.labels.length ||
        output.type != TensorType.float32) {
      throw const PaaccMlException('Unexpected PAACC output tensor contract.');
    }
  }

  IntentPrediction predict(String text) {
    if (_disposed) {
      throw const PaaccMlException('Classifier has already been disposed.');
    }
    try {
      final tokens = _tokenizer.tokenize(text);
      if (tokens.length != _config.maxLength) {
        throw const PaaccMlException('Unexpected PAACC input token count.');
      }
      final output = [
        List<double>.filled(_config.labels.length, 0.0, growable: false),
      ];
      _interpreter.run([tokens], output);
      final probabilities = List<double>.unmodifiable(output.first);
      if (probabilities.length != _config.labels.length) {
        throw const PaaccMlException('Unexpected PAACC output tensor shape.');
      }

      var bestIndex = 0;
      var bestProbability = probabilities.first;
      for (var index = 1; index < probabilities.length; index++) {
        if (probabilities[index] > bestProbability) {
          bestProbability = probabilities[index];
          bestIndex = index;
        }
      }
      final rawIntent = _config.labels[bestIndex];
      final accepted = bestProbability >= _config.threshold;
      return IntentPrediction(
        rawIntent: rawIntent,
        finalIntent: accepted ? rawIntent : 'uncertain',
        classIndex: bestIndex,
        confidence: bestProbability,
        probabilities: probabilities,
        accepted: accepted,
      );
    } on PaaccMlException {
      rethrow;
    } catch (error) {
      throw PaaccMlException('PAACC inference failed: $error');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _interpreter.close();
  }
}
