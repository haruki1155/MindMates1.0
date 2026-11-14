import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';

Future<void> _pumpRail(
  WidgetTester tester, {
  required AccessRole role,
  required bool isSuperAdmin,
  required ValueChanged<AdminPortalPage> onChanged,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AdminTheme.data,
      home: Scaffold(
        body: SizedBox(
          width: 280,
          height: 2400,
          child: PortalWorkspaceNavigation(
            page: AdminPortalPage.dashboard,
            onChanged: onChanged,
            accessRole: role,
            isSuperAdmin: isSuperAdmin,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the super-administrator sees Back-up Data under System', (
    tester,
  ) async {
    AdminPortalPage? selected;
    await _pumpRail(
      tester,
      role: AccessRole.admin,
      isSuperAdmin: true,
      onChanged: (page) => selected = page,
    );
    expect(find.text('Back-up Data'), findsOneWidget);
    await tester.tap(find.text('Back-up Data'));
    await tester.pumpAndSettle();
    expect(selected, AdminPortalPage.backupData);
    expect(tester.takeException(), isNull);
  });

  for (final role in [
    AccessRole.admin,
    AccessRole.counselor,
    AccessRole.portalStaff,
  ]) {
    testWidgets('a non-super ${role.name} never sees Back-up Data', (
      tester,
    ) async {
      await _pumpRail(
        tester,
        role: role,
        isSuperAdmin: false,
        onChanged: (_) {},
      );
      expect(find.text('Back-up Data'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
    });
  }
}
