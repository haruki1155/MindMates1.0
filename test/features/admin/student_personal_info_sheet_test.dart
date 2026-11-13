import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/widgets/student_personal_info_sheet.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/student_personal_info.dart';

const _official = StudentOfficialInfo(
  studentNo: '2021-00123',
  surname: 'Dela Cruz',
  firstName: 'Ana',
  middleName: '',
  dateOfBirth: '2005-02-03',
  college: 'CITE',
  course: 'BSIT',
  yearLevel: '3rd Year',
  email: 'ana@example.com',
);

Widget _host(String userId, bool canView, StudentPersonalInfoLoader loader) =>
    MaterialApp(
      home: Scaffold(
        body: ViewStudentInformationButton(
          userId: userId,
          canView: canView,
          loader: loader,
        ),
      ),
    );

void main() {
  test('only clinical roles may view', () {
    expect(AccessRole.counselor.canAccessClinicalData, isTrue);
    expect(AccessRole.admin.canAccessClinicalData, isTrue);
    expect(AccessRole.portalStaff.canAccessClinicalData, isFalse);
  });

  testWidgets('hidden when not allowed or no userId', (tester) async {
    Future<({StudentOfficialInfo official, StudentPersonalInfo? personal})>
    never(String id) => throw StateError('should not fetch');
    await tester.pumpWidget(_host('u1', false, never));
    expect(find.text('View Student Information'), findsNothing);
    await tester.pumpWidget(_host('', true, never));
    expect(find.text('View Student Information'), findsNothing);
  });

  testWidgets('fetches only on tap; null personal shows incomplete copy', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _host('u1', true, (id) async {
        calls.add(id);
        return (official: _official, personal: null);
      }),
    );
    expect(find.text('View Student Information'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.tap(find.text('View Student Information'));
    await tester.pumpAndSettle();
    expect(calls, ['u1']);
    expect(
      find.text("This student hasn't completed their Student Information yet."),
      findsOneWidget,
    );
    expect(find.text('Access to this record is logged.'), findsOneWidget);
  });
}
