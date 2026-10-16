import 'dart:math';
import '../models/intervention_models.dart';

class InterventionRotationPolicy {
  InterventionRotationPolicy({Random? random}) : _random = random ?? Random();
  final Random _random;
  final List<InterventionType> _remaining = [];
  InterventionType? _last;
  final Map<String, InterventionType> _assigned = {};
  InterventionType select(String domainId) {
    final existing = _assigned[domainId];
    if (existing != null) return existing;
    if (_remaining.isEmpty) {
      _remaining.addAll([InterventionType.walking, InterventionType.breathing, InterventionType.grounding]..shuffle(_random));
      if (_last != null && _remaining.first == _last && _remaining.length > 1) {
        final alternate = _remaining.indexWhere((item) => item != _last);
        final first = _remaining[0]; _remaining[0] = _remaining[alternate]; _remaining[alternate] = first;
      }
    }
    final selected = _remaining.removeAt(0);
    _assigned[domainId] = selected; _last = selected;
    return selected;
  }
}
