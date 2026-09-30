import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/ml/paacc/paacc_ml_config.dart';
import 'package:mind_mates/core/ml/paacc/paacc_tokenizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reproduces all PACC V4 tokenizer parity cases', () async {
    final config = await PaaccMlConfig.load();
    final tokenizer = await PaaccTokenizer.load(maxLength: config.maxLength);
    final reference =
        jsonDecode(
              await rootBundle.loadString(
                'assets/ml/paacc_v4_flutter_parity_reference.json',
              ),
            )
            as Map<String, dynamic>;
    final cases = reference['cases'] as List<dynamic>;

    expect(cases, hasLength(8));
    for (final item in cases.cast<Map<String, dynamic>>()) {
      expect(
        tokenizer.tokenize(item['message'] as String),
        equals((item['tokens'] as List<dynamic>).cast<int>()),
      );
    }
  });
}
