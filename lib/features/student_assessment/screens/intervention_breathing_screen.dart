import 'dart:async';

import 'package:flutter/material.dart';

import '../models/intervention_models.dart';

class InterventionBreathingScreen extends StatefulWidget {
  const InterventionBreathingScreen({super.key});

  @override
  State<InterventionBreathingScreen> createState() =>
      _InterventionBreathingScreenState();
}

class _InterventionBreathingScreenState
    extends State<InterventionBreathingScreen>
    with SingleTickerProviderStateMixin {
  static const _phaseDuration = Duration(seconds: 4);

  Timer? _timer;
  late final AnimationController _animation;
  int _seconds = _phaseDuration.inSeconds;
  int _phase = 0;
  int _cycles = 0;
  bool _paused = false;
  bool _hold = true;
  bool _completed = false;

  int get _phaseCount => _hold ? 3 : 2;
  String get _label => const ['Inhale', 'Exhale', 'Hold'][_phase];

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: _phaseDuration)
      ..forward();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_paused || _completed) return;
    if (_seconds > 1) {
      setState(() => _seconds -= 1);
      return;
    }

    final completesCycle = _phase == _phaseCount - 1;
    if (completesCycle && _cycles + 1 >= 5) {
      _complete();
      return;
    }
    setState(() {
      if (completesCycle) _cycles += 1;
      _phase = (_phase + 1) % _phaseCount;
      _seconds = _phaseDuration.inSeconds;
    });
    _animation.forward(from: 0);
  }

  void _complete() {
    if (_completed || !mounted) return;
    _completed = true;
    _timer?.cancel();
    Navigator.of(context).pop(InterventionOutcome.completed);
  }

  void _setHold(bool enabled) {
    if (_hold == enabled) return;
    setState(() {
      _hold = enabled;
      if (!_hold && _phase == 2) {
        _phase = 0;
        _seconds = _phaseDuration.inSeconds;
        _animation.forward(from: 0);
      }
    });
  }

  void _restart() {
    setState(() {
      _phase = 0;
      _seconds = _phaseDuration.inSeconds;
      _cycles = 0;
      _paused = false;
    });
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Breathing exercise')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: .7, end: 1.15).animate(_animation),
            child: CircleAvatar(
              radius: 90,
              child: Text('$_seconds', style: const TextStyle(fontSize: 48)),
            ),
          ),
          const SizedBox(height: 24),
          Text('$_label · Cycle ${_cycles + 1} of 5'),
          SwitchListTile(
            title: const Text('Include comfortable hold'),
            value: _hold,
            onChanged: _setHold,
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(InterventionOutcome.skipped),
                child: const Text('Skip'),
              ),
              FilledButton(
                onPressed: () => setState(() => _paused = !_paused),
                child: Text(_paused ? 'Resume' : 'Pause'),
              ),
              TextButton(onPressed: _restart, child: const Text('Restart')),
            ],
          ),
        ],
      ),
    ),
  );
}
