import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/counselor_messages_page.dart';

void main() {
  test('displays student name without an identifier', () {
    expect(
      counselorConversationStudentLabel('  Ana Dela Cruz  '),
      'Ana Dela Cruz',
    );
  });

  test('missing names never display raw identifiers', () {
    expect(counselorConversationStudentLabel(null), 'Student (name unavailable)');
    expect(counselorConversationStudentLabel(''), 'Student (name unavailable)');
  });
}
