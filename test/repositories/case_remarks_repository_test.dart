import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/case_remarks_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

Map<Object?, Object?> _m(Map<Object?, Object?> v) => v;

final _response = _m({
  'appointmentId': 'a1',
  'text': 'Line one\nLine two',
  'revision': 2,
  'updatedAt': '2026-11-16T01:00:00.000Z',
  'authorName': 'Coach Cite',
  'versions': <Object?>[
    _m({
      'revision': 2,
      'text': 'Line one\nLine two',
      'authorName': 'Coach Cite',
      'savedAt': '2026-11-16T01:00:00.000Z',
    }),
    _m({'revision': 1, 'text': 'Draft', 'authorName': '', 'savedAt': null}),
  ],
});

void main() {
  test('fetchCaseRemarks asks for one case and parses the view', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final repo = AdminPortalRepository(
      callableInvoker: (name, data) async {
        calls.add((name, data));
        return _response;
      },
    );

    final remarks = await repo.fetchCaseRemarks('a1');

    expect(calls.single.$1, 'getCaseRemarks');
    expect(calls.single.$2, {'appointmentId': 'a1'});
    expect(remarks.text, 'Line one\nLine two');
    expect(remarks.revision, 2);
    expect(remarks.authorName, 'Coach Cite');
    expect(remarks.updatedAt, DateTime.utc(2026, 11, 16, 1));
    expect(remarks.versions.map((v) => v.revision), [2, 1]);
    expect(remarks.versions.last.savedAt, isNull);
  });

  test(
    'saveCaseRemarks sends the text and the revision the editor saw',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repo = AdminPortalRepository(
        callableInvoker: (name, data) async {
          calls.add((name, data));
          return _response;
        },
      );

      final saved = await repo.saveCaseRemarks(
        appointmentId: 'a1',
        text: '',
        expectedRevision: 1,
      );

      expect(calls.single.$1, 'saveCaseRemarks');
      expect(calls.single.$2, {
        'appointmentId': 'a1',
        'text': '',
        'expectedRevision': 1,
      });
      expect(saved.revision, 2);
    },
  );

  test('an empty or malformed view reads as blank, revision 0', () {
    final remarks = CaseRemarks.fromJson(const {});
    expect(remarks.text, '');
    expect(remarks.revision, 0);
    expect(remarks.updatedAt, isNull);
    expect(remarks.versions, isEmpty);
    expect(remarks.hasRemarks, isFalse);
  });
}
