import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/data/guidance_quick_replies.dart';

void main() {
  test('catalog holds the nine approved replies in order', () {
    expect(guidanceQuickReplies.map((r) => r.id), [
      'understand',
      'noted',
      'thank_you',
      'clarification',
      'available',
      'unavailable',
      'follow_up',
      'further_assistance',
      'resolved',
    ]);
    expect(guidanceQuickReplies.map((r) => r.text), [
      'I understand.',
      'Noted.',
      'Thank you for your guidance.',
      'I need clarification.',
      'I am available.',
      'I am not available.',
      'I would like a follow-up session.',
      'I need further assistance.',
      'My concern has been addressed.',
    ]);
    expect(isGuidanceQuickReplyText('Noted.'), isTrue);
    for (final nearMiss in ['Noted', 'Noted. ', 'noted.', '', 'Hello']) {
      expect(isGuidanceQuickReplyText(nearMiss), isFalse, reason: nearMiss);
    }
  });

  test('rules allowlist equals the catalog', () {
    final rules = File('firestore.rules').readAsStringSync();
    final body = RegExp(
      r'function guidanceQuickReplyTexts\(\)\s*\{\s*return\s*\[(.*?)\];',
      dotAll: true,
    ).firstMatch(rules);
    expect(body, isNotNull, reason: 'guidanceQuickReplyTexts() not found');
    final texts = RegExp(
      r"'([^']*)'",
    ).allMatches(body!.group(1)!).map((m) => m.group(1)).toList();
    expect(texts, guidanceQuickReplies.map((r) => r.text).toList());
  });
}
