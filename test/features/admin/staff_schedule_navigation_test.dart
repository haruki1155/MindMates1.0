import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/models/profile_roles.dart';

void main() {
  test('staff cannot see the Schedule navigation', () {
    expect(canShowScheduleNavigation(AccessRole.portalStaff), isFalse);
    expect(canShowScheduleNavigation(AccessRole.appUser), isFalse);
  });

  test('authorized clinical and administrative roles retain Schedule', () {
    expect(canShowScheduleNavigation(AccessRole.counselor), isTrue);
    expect(canShowScheduleNavigation(AccessRole.admin), isTrue);
  });
}
