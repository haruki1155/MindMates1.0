import 'dart:convert';

import 'package:flutter/services.dart';

import 'paacc_ml_exception.dart';

class PaaccMlConfig {
  final String modelVersion;
  final double threshold;
  final int maxLength;
  final List<String> labels;

  const PaaccMlConfig({
    required this.modelVersion,
    required this.threshold,
    required this.maxLength,
    required this.labels,
  });

  static Future<PaaccMlConfig> load() async {
    try {
      final raw = await rootBundle.loadString('assets/ml/paacc_v4_config.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const PaaccMlException(
          'PAACC config JSON must contain an object.',
        );
      }

      final modelVersion = decoded['model_version'];
      final threshold = decoded['threshold'];
      final maxLength = decoded['max_length'];
      final labels = decoded['labels'];
      if (modelVersion is! String ||
          threshold is! num ||
          maxLength is! num ||
          labels is! List) {
        throw const PaaccMlException('PAACC config is malformed.');
      }

      final parsedLabels = labels
          .map((label) {
            if (label is! String || label.isEmpty) {
              throw const PaaccMlException(
                'PAACC config contains an invalid label.',
              );
            }
            return label;
          })
          .toList(growable: false);
      final config = PaaccMlConfig(
        modelVersion: modelVersion,
        threshold: threshold.toDouble(),
        maxLength: maxLength.toInt(),
        labels: List.unmodifiable(parsedLabels),
      );

      if (config.labels.length != 7) {
        throw const PaaccMlException('Expected 7 PAACC labels.');
      }
      if (config.maxLength != 40) {
        throw const PaaccMlException('Expected PAACC maxLength = 40.');
      }
      if (config.threshold <= 0 || config.threshold > 1) {
        throw const PaaccMlException('Invalid PAACC threshold.');
      }
      return config;
    } on PaaccMlException {
      rethrow;
    } catch (error) {
      throw PaaccMlException('Failed to load PAACC config: $error');
    }
  }
}
