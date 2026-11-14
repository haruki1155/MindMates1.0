import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/session_evidence.dart';

void main() {
  test('interview record parses private persisted fields and verified files', () {
    final note = SessionEvidenceRecord.fromJson({
      'summary': 'Session discussed',
      'interviewQuestions': 'What has helped?',
      'requirementsChecked': 'Consent reviewed',
      'materialsUsed': 'Worksheet',
      'attachments': [
        {
          'path': 'counseling_session_files/apt/counselor/0123456789abcdef0123456789abcdef.pdf',
          'name': 'Worksheet.pdf',
          'contentType': 'application/pdf',
          'size': 120,
        },
      ],
    });
    expect(note.summary, 'Session discussed');
    expect(note.interviewQuestions, 'What has helped?');
    expect(note.requirementsChecked, 'Consent reviewed');
    expect(note.materialsUsed, 'Worksheet');
    expect(note.attachments.single.name, 'Worksheet.pdf');
  });

  test('legacy session summary without attachments remains readable', () {
    final note = SessionEvidenceRecord.fromJson({'summary': 'Older note'});
    expect(note.summary, 'Older note');
    expect(note.attachments, isEmpty);
    expect(note.interviewQuestions, isEmpty);
  });

  test('only supported clinical file formats are accepted', () {
    expect(sessionEvidenceMimeType('scan.jpg'), 'image/jpeg');
    expect(sessionEvidenceMimeType('SCAN.PNG'), 'image/png');
    expect(sessionEvidenceMimeType('notes.pdf'), 'application/pdf');
    expect(sessionEvidenceMimeType('draft.doc'), 'application/msword');
    expect(
      sessionEvidenceMimeType('details.docx'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    expect(sessionEvidenceMimeType('malware.exe'), isNull);
    expect(sessionEvidenceMimeType('raw.svg'), isNull);
  });

  test('private file path never contains original filename', () {
    final path = buildSessionEvidencePath(
      'appointment_1',
      'clinician_1',
      'Sensitive notes for student.pdf',
      nonce: '0123456789abcdef0123456789abcdef',
    );
    expect(path, 'counseling_session_files/appointment_1/clinician_1/0123456789abcdef0123456789abcdef.pdf');
    expect(path, isNot(contains('Sensitive')));
  });
}
