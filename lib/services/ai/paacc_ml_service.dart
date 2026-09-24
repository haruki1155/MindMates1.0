import '../../core/ml/paacc/intent_prediction.dart';
import '../../core/ml/paacc/paacc_intent_classifier.dart';

class PaaccMlService {
  PaaccIntentClassifier? _classifier;
  Future<PaaccIntentClassifier>? _initialization;

  Future<IntentPrediction> predict(String text) async {
    final classifier = await _getClassifier();
    return classifier.predict(text);
  }

  Future<PaaccIntentClassifier> _getClassifier() {
    final classifier = _classifier;
    if (classifier != null) return Future.value(classifier);
    return _initialization ??= PaaccIntentClassifier.create().then((value) {
      _classifier = value;
      return value;
    });
  }

  void dispose() {
    _classifier?.dispose();
    _classifier = null;
    _initialization = null;
  }
}
