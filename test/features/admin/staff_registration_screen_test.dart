import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/staff_registration_screen.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

void main() {
  testWidgets('shows a controlled PACC access request form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StaffRegistrationScreen(repository: AdminPortalRepository()),
      ),
    );
    expect(find.text('Request PACC Portal Access'), findsNWidgets(2));
    expect(find.text('PACC Staff'), findsOneWidget);
    expect(find.text('Counselor'), findsOneWidget);
    expect(find.text('Department'), findsNothing);
    expect(find.text('College'), findsNothing);
    expect(find.text('Course'), findsNothing);
  });
}
