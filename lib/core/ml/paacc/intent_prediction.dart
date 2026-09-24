class IntentPrediction {
  final String rawIntent;
  final String finalIntent;
  final int classIndex;
  final double confidence;
  final List<double> probabilities;
  final bool accepted;

  const IntentPrediction({
    required this.rawIntent,
    required this.finalIntent,
    required this.classIndex,
    required this.confidence,
    required this.probabilities,
    required this.accepted,
  });

  bool get isUncertain => finalIntent == 'uncertain';
}
