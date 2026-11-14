import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/widgets/student_personal_info_sheet.dart';
import 'package:mind_mates/features/admin/screens/counselor_workflow_page.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
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

class _Repo extends AdminPortalRepository {
  _Repo(this.role, this.userIds);
  final AccessRole role;
  final List<String> userIds;
  @override
  AccessRole get currentAccessRole => role;
  @override
  Stream<List<AppointmentModel>> watchAppointments() =>
      throw StateError('My Cases must use assigned appointments.');

  @override
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() => Stream.value([
    for (final id in userIds)
      AppointmentModel(
        id: 'a-$id',
        userId: id,
        fullName: 'Ana Dela Cruz',
        scheduledAt: DateTime(2026, 1, 1),
        scheduledTime: '10:00 AM',
        location: 'PACC',
        status: 'confirmed',
        concern: '',
        contactNumber: '',
        email: '',
        preferredContactMethod: '',
        createdAt: DateTime(2026, 1, 1),
      ),
  ]);
}

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

  Future<void> pumpWorkflow(WidgetTester tester, _Repo repo) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CounselorWorkflowPage(
            repository: repo,
            mode: CounselorWorkflowMode.cases,
            onOpenAppointments: () {},
            studentInfoLoader: (id) async =>
                (official: _official, personal: null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('counselor case card shows the action', (tester) async {
    await pumpWorkflow(tester, _Repo(AccessRole.counselor, ['u1']));
    expect(find.text('View Student Information'), findsOneWidget);
  });

  testWidgets('My Cases displays the recorded student name', (tester) async {
    await pumpWorkflow(tester, _Repo(AccessRole.counselor, ['u1']));
    expect(find.text('Ana Dela Cruz'), findsOneWidget);
    expect(find.text('Student ••••u1'), findsNothing);
  });

  testWidgets('Follow-ups is accessible from My Cases', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedMode = CounselorWorkflowMode.cases;
    final repository = _Repo(AccessRole.counselor, ['u1']);

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: CounselorWorkflowPage(
              repository: repository,
              mode: selectedMode,
              onOpenAppointments: () {},
              onModeChanged: (next) => setState(() => selectedMode = next),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('My Cases'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Assigned Cases'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Follow-ups'));
    await tester.pumpAndSettle();

    expect(selectedMode, CounselorWorkflowMode.followUps);
    expect(find.text('My Cases'), findsOneWidget);
    expect(find.text('No follow-ups due'), findsOneWidget);
  });

  testWidgets('portal staff never see the action', (tester) async {
    await pumpWorkflow(tester, _Repo(AccessRole.portalStaff, ['u1']));
    expect(find.text('View Student Information'), findsNothing);
  });
}
