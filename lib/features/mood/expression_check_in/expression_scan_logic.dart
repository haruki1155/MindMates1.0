import 'dart:typed_data';

import 'dart:ui';

/// Runtime-only observations. Camera images and face measurements are not saved.
class ExpressionFrame {
  const ExpressionFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotationDegrees,
    required this.formatCode,
    required this.timestamp,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotationDegrees;
  final int formatCode;
  final DateTime timestamp;
}

abstract interface class ExpressionAnalyzer {
  Future<ExpressionObservation> analyze(ExpressionFrame frame);
  Future<void> dispose();
}

/// Optional lifecycle hook for analyzers with a local model to load.
abstract interface class InitializableExpressionAnalyzer {
  Future<void> initialize();
}

class ExpressionObservation {
  const ExpressionObservation({
    required this.faceCount,
    required this.isFaceCentered,
    required this.isFacingCamera,
    required this.smileProbability,
    this.modelOutput,
    this.faceBox,
    this.uprightSize,
    this.cropBox,
    this.debugCropPng,
    this.rawSize,
    this.rotationDegrees,
    this.positioningHint,
    required this.timestamp,
  });

  final int faceCount;
  final bool isFaceCentered;
  final bool isFacingCamera;
  final double? smileProbability;
  final ExpressionModelOutput? modelOutput;
  final Rect? faceBox;
  final Size? uprightSize;
  final Rect? cropBox;
  final Uint8List? debugCropPng;
  final Size? rawSize;
  final int? rotationDegrees;
  final String? positioningHint;
  final DateTime timestamp;
}

enum RawFerExpression { angry, disgust, fear, happy, sad, surprise, neutral }

/// Runtime-only, ordered exactly as the FER model output tensor.
class ExpressionModelOutput {
  ExpressionModelOutput({required List<double> scores})
    : scores = List<double>.unmodifiable(scores);

  static const labels = <RawFerExpression>[
    RawFerExpression.angry,
    RawFerExpression.disgust,
    RawFerExpression.fear,
    RawFerExpression.happy,
    RawFerExpression.sad,
    RawFerExpression.surprise,
    RawFerExpression.neutral,
  ];

  final List<double> scores;

  bool get isValid =>
      scores.length == labels.length &&
      scores.every((score) => score.isFinite && score >= 0);

  RawFerExpression get topLabel => labels[topIndex];

  int get topIndex {
    if (!isValid) throw StateError('Invalid FER score vector.');
    var index = 0;
    for (var current = 1; current < scores.length; current++) {
      if (scores[current] > scores[index]) index = current;
    }
    return index;
  }
}

enum ExpressionCue {
  positiveLike,
  neutralLike,
  subduedLike,
  tenseLike,
  surprisedLike,
  // Retained only as the ML Kit fallback while the local model is optional.
  smiling,
  noStrongExpression,
  unclear,
}

enum ExpressionCueSource { tflite, mlKit }

enum ScanStatus {
  initializing,
  permissionRequired,
  permissionDenied,
  cameraUnavailable,
  ready,
  noFace,
  multipleFaces,
  faceNotCentered,
  lookAtCamera,
  stabilizing,
  resultReady,
  noResult,
  failure,
  paused,
}

class ExpressionScanConfig {
  const ExpressionScanConfig({
    this.processEvery = const Duration(milliseconds: 180),
    this.scanTimeout = const Duration(seconds: 15),
    this.frameTimeout = const Duration(seconds: 3),
    this.requiredStableSamples = 5,
    this.maximumSampleAge = const Duration(seconds: 2),
    this.smileThreshold = 0.75,
    this.modelRollingSamples = 8,
    this.modelMinimumSamples = 5,
    this.modelMinimumTopScore = 0.60,
    this.modelMinimumMargin = 0.12,
    this.modelEmaAlpha = .30,
    this.modelStandardConfirmations = 3,
    this.modelNeutralConfirmations = 5,
  });

  final Duration processEvery;
  final Duration scanTimeout;
  final Duration frameTimeout;
  final int requiredStableSamples;
  final Duration maximumSampleAge;
  final double smileThreshold;
  final int modelRollingSamples;
  final int modelMinimumSamples;
  final double modelMinimumTopScore;
  final double modelMinimumMargin;
  final double modelEmaAlpha;
  final int modelStandardConfirmations;
  final int modelNeutralConfirmations;
}

ScanStatus validateFace(ExpressionObservation observation) {
  if (observation.faceCount == 0) return ScanStatus.noFace;
  if (observation.faceCount > 1) return ScanStatus.multipleFaces;
  if (!observation.isFaceCentered) return ScanStatus.faceNotCentered;
  if (!observation.isFacingCamera) return ScanStatus.lookAtCamera;
  return ScanStatus.stabilizing;
}

ExpressionCue mapCue(
  ExpressionObservation observation, {
  ExpressionScanConfig config = const ExpressionScanConfig(),
}) {
  final smile = observation.smileProbability;
  if (smile == null || !smile.isFinite || smile < 0 || smile > 1) {
    return ExpressionCue.unclear;
  }
  return smile >= config.smileThreshold
      ? ExpressionCue.smiling
      : ExpressionCue.noStrongExpression;
}

ExpressionCue mapModelOutput(
  ExpressionModelOutput output, {
  ExpressionScanConfig config = const ExpressionScanConfig(),
}) => output.isValid
    ? evaluateModelOutput(output, config: config).cue
    : ExpressionCue.unclear;

double applyEma({
  required double previous,
  required double current,
  required double alpha,
}) => (alpha * current) + ((1 - alpha) * previous);

enum ExpressionDecisionStatus { continueScanning, accepted, unclear }

class ProductCueDecision {
  const ProductCueDecision({
    required this.ferEma,
    required this.productScores,
    required this.topCue,
    required this.secondCue,
    required this.margin,
    required this.cue,
    required this.reason,
    required this.status,
    required this.candidateCue,
    required this.candidateConfirmations,
    required this.requiredConfirmations,
    required this.trends,
  });

  final ExpressionModelOutput ferEma;
  final Map<ExpressionCue, double> productScores;
  final ExpressionCue topCue;
  final ExpressionCue secondCue;
  final double margin;
  final ExpressionCue cue;
  final String reason;
  final ExpressionDecisionStatus status;
  final ExpressionCue? candidateCue;
  final int candidateConfirmations;
  final int requiredConfirmations;
  final Map<ExpressionCue, double> trends;

  ProductCueDecision copyWith({
    ExpressionCue? cue,
    String? reason,
    ExpressionDecisionStatus? status,
  }) => ProductCueDecision(
    ferEma: ferEma,
    productScores: productScores,
    topCue: topCue,
    secondCue: secondCue,
    margin: margin,
    cue: cue ?? this.cue,
    reason: reason ?? this.reason,
    status: status ?? this.status,
    candidateCue: candidateCue,
    candidateConfirmations: candidateConfirmations,
    requiredConfirmations: requiredConfirmations,
    trends: trends,
  );
}

ProductCueDecision evaluateModelOutput(
  ExpressionModelOutput output, {
  ExpressionScanConfig config = const ExpressionScanConfig(),
}) {
  if (!output.isValid) throw ArgumentError('Invalid FER score vector.');
  final scores = output.scores;
  final products = <ExpressionCue, double>{
    ExpressionCue.positiveLike: scores[3],
    ExpressionCue.neutralLike: scores[6],
    ExpressionCue.subduedLike: scores[4],
    ExpressionCue.tenseLike: scores[0] > scores[1] ? scores[0] : scores[1],
    ExpressionCue.surprisedLike: scores[5],
  };
  final ordered = products.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = ordered[0];
  final second = ordered[1];
  final margin = top.value - second.value;
  final reason = output.topLabel == RawFerExpression.fear
      ? 'fear_unmapped'
      : top.value < config.modelMinimumTopScore
      ? 'top score too low'
      : margin < config.modelMinimumMargin
      ? 'margin too small'
      : 'accepted';
  final accepted = reason == 'accepted';
  return ProductCueDecision(
    ferEma: output,
    productScores: Map.unmodifiable(products),
    topCue: top.key,
    secondCue: second.key,
    margin: margin,
    cue: accepted ? top.key : ExpressionCue.unclear,
    reason: reason,
    status: accepted
        ? ExpressionDecisionStatus.accepted
        : ExpressionDecisionStatus.continueScanning,
    candidateCue: null,
    candidateConfirmations: 0,
    requiredConfirmations: top.key == ExpressionCue.neutralLike
        ? config.modelNeutralConfirmations
        : config.modelStandardConfirmations,
    trends: Map.unmodifiable({for (final cue in products.keys) cue: 0.0}),
  );
}

class ExpressionStabilityFilter {
  ExpressionStabilityFilter({this.config = const ExpressionScanConfig()});

  final ExpressionScanConfig config;
  ExpressionCue? _lastCue;
  DateTime? _firstSampleAt;
  int _consecutiveSamples = 0;
  ExpressionModelOutput? _emaScores;
  Map<ExpressionCue, double>? _previousProductScores;
  ExpressionCue? _candidateCue;
  int _candidateConfirmations = 0;
  int _validModelSamples = 0;
  ProductCueDecision? latestDecision;
  ExpressionModelOutput? get emaScores => _emaScores;

  ExpressionCue? add(ExpressionCue cue, DateTime timestamp) {
    if (_lastCue != cue ||
        _firstSampleAt == null ||
        timestamp.isBefore(_firstSampleAt!) ||
        timestamp.difference(_firstSampleAt!) > config.maximumSampleAge) {
      _lastCue = cue;
      _firstSampleAt = timestamp;
      _consecutiveSamples = 0;
    }
    _consecutiveSamples++;
    return _consecutiveSamples >= config.requiredStableSamples ? cue : null;
  }

  ExpressionCue? addObservation(ExpressionObservation observation) {
    final output = observation.modelOutput;
    if (output == null) {
      _resetModelState();
      latestDecision = null;
      return add(mapCue(observation, config: config), observation.timestamp);
    }
    if (!output.isValid) {
      reset();
      return null;
    }
    _validModelSamples++;
    _emaScores = _nextEma(output);
    final base = evaluateModelOutput(_emaScores!, config: config);
    final trends = <ExpressionCue, double>{
      for (final entry in base.productScores.entries)
        entry.key:
            entry.value - (_previousProductScores?[entry.key] ?? entry.value),
    };
    _previousProductScores = base.productScores;

    final gateReason = _modelGateReason(base);
    final candidateChanged = _candidateCue != base.topCue;
    if (gateReason != null) {
      _candidateCue = null;
      _candidateConfirmations = 0;
      latestDecision = _temporalDecision(
        base: base,
        trends: trends,
        status: ExpressionDecisionStatus.continueScanning,
        cue: ExpressionCue.unclear,
        reason: gateReason,
      );
      return null;
    }

    _candidateCue = base.topCue;
    _candidateConfirmations = candidateChanged
        ? 1
        : _candidateConfirmations + 1;
    final required = _requiredConfirmations(base.topCue);
    final neutralCompetitorRising =
        base.topCue == ExpressionCue.neutralLike &&
        base.secondCue != ExpressionCue.neutralLike &&
        (trends[ExpressionCue.neutralLike] ?? 0) < 0 &&
        (trends[base.secondCue] ?? 0) > 0;
    final accepted =
        _candidateConfirmations >= required && !neutralCompetitorRising;
    latestDecision = _temporalDecision(
      base: base,
      trends: trends,
      status: accepted
          ? ExpressionDecisionStatus.accepted
          : ExpressionDecisionStatus.continueScanning,
      cue: accepted ? base.topCue : ExpressionCue.unclear,
      reason: accepted
          ? 'accepted'
          : neutralCompetitorRising
          ? 'neutral_competitor_rising'
          : candidateChanged
          ? 'candidate_changed'
          : _candidateConfirmations < required
          ? base.topCue == ExpressionCue.neutralLike
                ? 'neutral_not_stable_long_enough'
                : 'candidate_unstable'
          : 'candidate_unstable',
    );
    return accepted ? base.topCue : null;
  }

  ProductCueDecision? markUnclear() {
    final decision = latestDecision;
    if (decision == null) return null;
    latestDecision = decision.copyWith(
      cue: ExpressionCue.unclear,
      reason: 'scan_timeout',
      status: ExpressionDecisionStatus.unclear,
    );
    return latestDecision;
  }

  ExpressionModelOutput _nextEma(ExpressionModelOutput current) {
    final previous = _emaScores;
    if (previous == null) return current;
    return ExpressionModelOutput(
      scores: List<double>.generate(
        current.scores.length,
        (index) => applyEma(
          previous: previous.scores[index],
          current: current.scores[index],
          alpha: config.modelEmaAlpha,
        ),
        growable: false,
      ),
    );
  }

  String? _modelGateReason(ProductCueDecision decision) {
    if (_validModelSamples < config.modelMinimumSamples) {
      return 'insufficient_samples';
    }
    if (decision.ferEma.topLabel == RawFerExpression.fear) {
      return 'fear_unmapped';
    }
    if (decision.productScores[decision.topCue]! <
        config.modelMinimumTopScore) {
      return 'top_score_too_low';
    }
    if (decision.margin < config.modelMinimumMargin) return 'margin_too_small';
    return null;
  }

  int _requiredConfirmations(ExpressionCue cue) =>
      cue == ExpressionCue.neutralLike
      ? config.modelNeutralConfirmations
      : config.modelStandardConfirmations;

  ProductCueDecision _temporalDecision({
    required ProductCueDecision base,
    required Map<ExpressionCue, double> trends,
    required ExpressionDecisionStatus status,
    required ExpressionCue cue,
    required String reason,
  }) => ProductCueDecision(
    ferEma: base.ferEma,
    productScores: base.productScores,
    topCue: base.topCue,
    secondCue: base.secondCue,
    margin: base.margin,
    cue: cue,
    reason: reason,
    status: status,
    candidateCue: _candidateCue,
    candidateConfirmations: _candidateConfirmations,
    requiredConfirmations: _requiredConfirmations(base.topCue),
    trends: Map.unmodifiable(trends),
  );

  void reset() {
    _lastCue = null;
    _firstSampleAt = null;
    _consecutiveSamples = 0;
    _resetModelState();
    latestDecision = null;
  }

  void _resetModelState() {
    _emaScores = null;
    _previousProductScores = null;
    _candidateCue = null;
    _candidateConfirmations = 0;
    _validModelSamples = 0;
  }
}
