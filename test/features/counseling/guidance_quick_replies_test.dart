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
}
