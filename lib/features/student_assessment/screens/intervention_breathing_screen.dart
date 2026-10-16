import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/intervention_models.dart';
import '../widgets/assessment_presentation.dart';

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
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 500;
          final radius = compact ? 56.0 : 90.0;
          final animationDiameter = radius * 2 * 1.15;
          final padding = EdgeInsets.symmetric(
            horizontal: 20,
            vertical: compact ? 8 : 20,
          );

          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - padding.vertical,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Guided breathing',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      AssessmentStatusPill(label: 'Cycle ${_cycles + 1} of 5'),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 16),
                  Center(
                    child: SizedBox(
                      height: animationDiameter,
                      width: animationDiameter,
                      child: AssessmentSurfaceCard(
                        padding: EdgeInsets.zero,
                        color: AssessmentPresentation.softPrimary(context),
                        child: Center(
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: .7,
                              end: 1.15,
                            ).animate(_animation),
                            child: CircleAvatar(
                              radius: radius,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: Text(
                                '$_seconds',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontSize: compact ? 36 : 48,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 16),
                  Text(
                    '$_label for $_seconds seconds',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 16),
                  AssessmentSurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: SwitchListTile(
                      title: const Text('Include comfortable hold'),
                      subtitle: Text(
                        'Turn this off for a simpler inhale and exhale rhythm.',
                        style: TextStyle(
                          color: AssessmentPresentation.muted(context),
                        ),
                      ),
                      value: _hold,
                      onChanged: _setHold,
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 16),
                  FilledButton.icon(
                    onPressed: () => setState(() => _paused = !_paused),
                    icon: Icon(
                      _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    label: Text(_paused ? 'Resume exercise' : 'Pause exercise'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _restart,
                          child: const Text('Restart'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(InterventionOutcome.skipped),
                          child: const Text('Skip activity'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
