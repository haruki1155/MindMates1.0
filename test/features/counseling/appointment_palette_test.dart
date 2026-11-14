import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/constants/app_colors.dart';
import 'package:mind_mates/features/counseling/widgets/appointment_presentation.dart';
import 'package:mind_mates/models/appointment_model.dart';

void main() {
  test('appointment brand green is the app palette primary', () {
    expect(AppointmentVisuals.teal, AppColors.primary);
    expect(AppointmentVisuals.iconTint, AppColors.primary);
  });

  test('pending, confirmed and cancelled status colours stay mutually distinct', () {
    final pending = AppointmentVisuals.statusColors(AppointmentStatus.requested);
    final confirmed = AppointmentVisuals.statusColors(AppointmentStatus.confirmed);
    final cancelled = AppointmentVisuals.statusColors(AppointmentStatus.cancelled);
    expect({pending.$1, confirmed.$1, cancelled.$1}.length, 3);
    expect({pending.$2, confirmed.$2, cancelled.$2}.length, 3);
    expect(confirmed.$2, AppColors.primary);
  });
}
