import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/services/intervention_rotation_policy.dart';

void main() {
  test('uses every ordinary activity before repeating and keeps assignments stable', () {
    final policy = InterventionRotationPolicy(random: Random(7));
    final first = [for (final id in ['a', 'b', 'c']) policy.select(id)];
    expect(first.toSet(), {InterventionType.walking, InterventionType.breathing, InterventionType.grounding});
    expect(policy.select('a'), first.first);
    expect(policy.select('d'), isNot(first.last));
  });

  test('never selects appointment and a new session starts a fresh rotation', () {
    final first = InterventionRotationPolicy(random: Random(1));
    final second = InterventionRotationPolicy(random: Random(1));
    final firstCycle = [for (var i = 0; i < 3; i++) first.select('a$i')];
    final secondCycle = [for (var i = 0; i < 3; i++) second.select('b$i')];
    expect(firstCycle, secondCycle);
    expect(firstCycle, isNot(contains(InterventionType.appointment)));
  });
}
