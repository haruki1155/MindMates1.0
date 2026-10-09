import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import '../models/intervention_models.dart';

class InterventionWalkingScreen extends StatefulWidget {
  const InterventionWalkingScreen({super.key, this.stepCountStream});

  /// Allows deterministic sensor simulations without changing the production
  /// Pedometer integration.
  final Stream<int>? stepCountStream;

  @override
  State<InterventionWalkingScreen> createState() =>
      _InterventionWalkingScreenState();
}

class _InterventionWalkingScreenState extends State<InterventionWalkingScreen> {
  int? _baseline;
  int _steps = 0;
  bool _paused = false, _fallback = false;
  StreamSubscription<int>? _testSub;
  @override
  void initState() {
    super.initState();
    final stream =
        widget.stepCountStream ??
        Pedometer.stepCountStream.map((event) => event.steps);
    _testSub = stream.listen(
      _onStepCount,
      onError: (_) {
        if (mounted) setState(() => _fallback = true);
      },
    );
  }

  void _onStepCount(int totalSteps) {
    if (_paused) return;
    final base = _baseline ??= totalSteps;
    final next = totalSteps - base;
    if (next >= _steps && mounted) setState(() => _steps = next);
    if (next >= 500 && mounted) {
      Navigator.pop(context, InterventionOutcome.completed);
    }
  }

  @override
  void dispose() {
    _testSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Walk 500 steps')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            '$_steps / 500 steps',
            style: Theme.of(c).textTheme.headlineMedium,
          ),
          LinearProgressIndicator(value: (_steps / 500).clamp(0, 1)),
          if (_fallback)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Automatic step counting is unavailable. You may self-report completion or skip.',
              ),
            ),
          const Spacer(),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(c, InterventionOutcome.skipped),
                child: const Text('Skip'),
              ),
              FilledButton(
                onPressed: () => setState(() => _paused = !_paused),
                child: Text(_paused ? 'Resume' : 'Pause'),
              ),
              if (_fallback)
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(c, InterventionOutcome.completed),
                  child: const Text('I completed my walk'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
