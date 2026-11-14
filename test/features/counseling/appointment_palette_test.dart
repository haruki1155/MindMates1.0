import 'dart:math' as math;

import 'package:flutter/painting.dart';
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
  });

  test('every status chip pair meets WCAG AA (4.5:1)', () {
    for (final status in [
      AppointmentStatus.requested,
      AppointmentStatus.confirmed,
      AppointmentStatus.cancelled,
    ]) {
      final (bg, fg) = AppointmentVisuals.statusColors(status);
      expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: status.name);
    }
  });
}

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
