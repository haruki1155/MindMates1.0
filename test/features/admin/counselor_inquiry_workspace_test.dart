import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/features/admin/widgets/counselor_inquiry_workspace.dart';

void main() {
  testWidgets('Counselor Inquiries opens Messages and can switch to Other services', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CounselorInquiryWorkspace(
            messages: Text('Existing counselor conversation inbox'),
            otherServices: Text('Existing service inquiry queue'),
          ),
        ),
      ),
    ));

    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Other services'), findsOneWidget);
    expect(find.text('Existing counselor conversation inbox'), findsOneWidget);
    expect(find.text('Existing service inquiry queue'), findsNothing);

    await tester.tap(find.text('Other services'));
    await tester.pumpAndSettle();
    expect(find.text('Existing counselor conversation inbox'), findsNothing);
    expect(find.text('Existing service inquiry queue'), findsOneWidget);

    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    expect(find.text('Existing counselor conversation inbox'), findsOneWidget);
  });

  test('Counselor Messages is inside Inquiries, not a sidebar destination', () {
    final destinations = AdminPortalPage.values.map((value) => value.name);
    expect(destinations, isNot(contains('counselorMessages')));
    expect(destinations, contains('inquiries'));
  });

  test('messaging access remains counselor-only after moving into Inquiries', () {
    expect(canShowCounselorMessagingInInquiries(AccessRole.counselor), isTrue);
    expect(canShowCounselorMessagingInInquiries(AccessRole.admin), isFalse);
    expect(canShowCounselorMessagingInInquiries(AccessRole.portalStaff), isFalse);
    expect(canShowCounselorMessagingInInquiries(AccessRole.appUser), isFalse);
  });
}
