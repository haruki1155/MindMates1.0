import 'dart:convert';

import 'package:flutter/services.dart';

import 'paacc_ml_exception.dart';

class PaaccTokenizer {
  final List<String> vocabulary;
  final Map<String, int> _wordToIndex;
  final int maxLength;

  PaaccTokenizer({required List<String> vocabulary, required this.maxLength})
    : vocabulary = List.unmodifiable(vocabulary),
      _wordToIndex = {
        for (var index = 0; index < vocabulary.length; index++)
          vocabulary[index]: index,
      };

  static Future<PaaccTokenizer> load({required int maxLength}) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/ml/paacc_v4_vocabulary.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const PaaccMlException(
          'PAACC vocabulary JSON must contain a list.',
        );
      }
      if (decoded.length < 2 || decoded.any((item) => item is! String)) {
        throw const PaaccMlException('PAACC vocabulary is invalid.');
      }
      return PaaccTokenizer(
        vocabulary: decoded.cast<String>(),
        maxLength: maxLength,
      );
    } on PaaccMlException {
      rethrow;
    } catch (error) {
      throw PaaccMlException('Failed to load PAACC vocabulary: $error');
    }
  }

  List<int> tokenize(String text) {
    var normalized = text.toLowerCase();
    normalized = normalized.replaceAll(
      RegExp(r'''[!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~]'''),
      '',
    );

    final words = normalized
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final tokens = List<int>.filled(maxLength, 0, growable: false);

    var index = 0;
    for (final word in words) {
      if (index >= maxLength) break;
      tokens[index] = _wordToIndex[word] ?? 1;
      index++;
    }
    return tokens;
  }
}
