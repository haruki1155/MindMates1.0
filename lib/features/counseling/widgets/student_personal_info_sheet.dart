import 'package:flutter/material.dart';

import '../../../models/student_personal_info.dart';
import '../../../repositories/student_roster_repository.dart';

const studentInfoIncompleteCopy =
    "This student hasn't completed their Student Information yet.";
const studentInfoAccessLoggedCopy = 'Access to this record is logged.';

typedef StudentPersonalInfoResult = ({
  StudentOfficialInfo official,
  StudentPersonalInfo? personal,
});
typedef StudentPersonalInfoLoader =
    Future<StudentPersonalInfoResult> Function(String userId);

/// "View Student Information" action. Renders nothing unless [canView] and a
/// real [userId] exist (walk-in imports have an empty userId). Data is fetched
/// only when the sheet is opened by a tap.
class ViewStudentInformationButton extends StatelessWidget {
  const ViewStudentInformationButton({
    super.key,
    required this.userId,
    required this.canView,
    this.loader,
  });

  final String userId;
  final bool canView;
  final StudentPersonalInfoLoader? loader;

  @override
  Widget build(BuildContext context) {
    if (!canView || userId.trim().isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () =>
          showStudentPersonalInfoSheet(context, userId: userId, loader: loader),
      icon: const Icon(Icons.badge_outlined, size: 17),
      label: const Text('View Student Information'),
    );
  }
}

Future<void> showStudentPersonalInfoSheet(
  BuildContext context, {
  required String userId,
  StudentPersonalInfoLoader? loader,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _StudentPersonalInfoSheet(
    userId: userId,
    loader: loader ?? StudentRosterRepository().getStudentPersonalInfo,
  ),
);

class _StudentPersonalInfoSheet extends StatefulWidget {
  const _StudentPersonalInfoSheet({required this.userId, required this.loader});
  final String userId;
  final StudentPersonalInfoLoader loader;

  @override
  State<_StudentPersonalInfoSheet> createState() => _SheetState();
}

class _SheetState extends State<_StudentPersonalInfoSheet> {
  late Future<StudentPersonalInfoResult> _future = widget.loader(
    widget.userId,
  );

  void _retry() => setState(() => _future = widget.loader(widget.userId));

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Student Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<StudentPersonalInfoResult>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "We couldn't load this student's information.",
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Try Again'),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _Body(
                    official: snapshot.data!.official,
                    personal: snapshot.data!.personal,
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              studentInfoAccessLoggedCopy,
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.official, required this.personal});
  final StudentOfficialInfo official;
  final StudentPersonalInfo? personal;

  @override
  Widget build(BuildContext context) {
    final p = personal;
    final name = [
      official.firstName,
      official.middleName,
      official.surname,
    ].where((s) => s.trim().isNotEmpty).join(' ');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Official record'),
          _row('Student No.', official.studentNo),
          _row('Name', name),
          _row('Date of birth', official.dateOfBirth),
          _row('College', official.college),
          _row('Course', official.course),
          _row('Year level', official.yearLevel),
          _row('Email', official.email),
          const SizedBox(height: 12),
          if (p == null)
            const Text(studentInfoIncompleteCopy)
          else ...[
            _section('Personal'),
            _row('Sex', p.sex),
            _row('Civil status', p.civilStatus),
            if (p.spouse.isNotEmpty) _row('Spouse', p.spouse),
            _row('Nationality', p.nationality),
            _row('Place of birth', p.placeOfBirth),
            _row('Telephone', p.telephone),
            _row('Cellphone', p.cellphone),
            _section('Address'),
            _row('Home address', _address(p.homeAddress)),
            if (p.cityAddress != null && !p.cityAddress!.isEmpty)
              _row('City address', _address(p.cityAddress!)),
            _section('Family'),
            _row('Father', p.father),
            _row('Father occupation', p.fatherOccupation),
            _row('Mother', p.mother),
            _row('Mother occupation', p.motherOccupation),
            _row('Guardian', p.guardian),
            _row('Guardian relationship', p.guardianRelationship),
            _row('Guardian address', p.guardianAddress),
          ],
        ],
      ),
    );
  }

  static String _address(StudentAddress a) => [
    a.number,
    a.street,
    a.barangay,
    a.cityTown,
    a.province,
    a.zipCode,
  ].where((s) => s.trim().isNotEmpty).join(', ');

  static Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
  );

  static Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(child: Text(value.trim().isEmpty ? '-' : value)),
      ],
    ),
  );
}
