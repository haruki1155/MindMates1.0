import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/models/profile_roles.dart';

void main() {
  for (final role in [
    AccessRole.portalStaff,
    AccessRole.admin,
    AccessRole.counselor,
  ]) {
    for (final layout in ['expanded', 'compact', 'collapsed']) {
      testWidgets(
        '${role.name} $layout workspace preserves announcement role visibility',
        (tester) async {
          AdminPortalPage? selected;
          await tester.pumpWidget(
            MaterialApp(
              theme: AdminTheme.data,
              home: Scaffold(
                body: SizedBox(
                  width: layout == 'collapsed' ? 80 : 280,
                  height: 1000,
                  child: PortalWorkspaceNavigation(
                    page: AdminPortalPage.dashboard,
                    onChanged: (page) => selected = page,
                    accessRole: role,
                    compact: layout == 'compact',
                    collapsed: layout == 'collapsed',
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final target = layout == 'collapsed'
              ? find.byTooltip('Announcements')
              : find.text('Announcements');
          if (role == AccessRole.counselor) {
            expect(target, findsNothing);
            expect(
              layout == 'collapsed'
                  ? find.byTooltip('My Cases')
                  : find.text('My Cases'),
              findsOneWidget,
            );
          } else {
            expect(target, findsOneWidget);
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(selected, AdminPortalPage.announcements);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
