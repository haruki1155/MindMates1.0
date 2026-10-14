import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/intervention_models.dart';

class InterventionWalkingScreen extends StatefulWidget {
  const InterventionWalkingScreen({
    super.key,
    this.stepCountStream,
    this.requestActivityRecognitionPermission,
    this.noReadingTimeout = const Duration(seconds: 15),
  });

  /// Allows deterministic sensor simulations without changing production input.
  final Stream<int>? stepCountStream;
  final Future<PermissionStatus> Function()?
  requestActivityRecognitionPermission;
  final Duration noReadingTimeout;

  @override
  State<InterventionWalkingScreen> createState() =>
      _InterventionWalkingScreenState();
}

class _InterventionWalkingScreenState extends State<InterventionWalkingScreen> {
  int? _baseline;
  int _steps = 0;
  bool _paused = false;
  bool _fallback = false;
  bool _completed = false;
  bool _rebaseOnNextReading = false;
  String? _fallbackMessage;
  StreamSubscription<int>? _stepSubscription;
  Timer? _noReadingTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_startStepCounting());
  }

  Future<void> _startStepCounting() async {
    // Injected streams are test-only sensor simulations and deliberately avoid
    // platform permission APIs.
    if (widget.stepCountStream == null) {
      final status = await _permissionStatus();
      if (!mounted) return;
      if (!status.isGranted) {
        _showFallback(
          status.isPermanentlyDenied
              ? 'Activity-recognition permission is permanently denied. You may self-report completion or skip.'
              : 'Activity-recognition permission was not granted. You may self-report completion or skip.',
        );
        return;
      }
    }
    if (!mounted) return;
    final stream =
        widget.stepCountStream ??
        Pedometer.stepCountStream.map((event) => event.steps);
    _stepSubscription = stream.listen(
      _onStepCount,
      onError: (_) => _showFallback(
        'Automatic step counting is unavailable. You may self-report completion or skip.',
      ),
    );
    _noReadingTimer = Timer(widget.noReadingTimeout, () {
      if (_baseline == null) {
        _showFallback(
          'Automatic step counting is unavailable. You may self-report completion or skip.',
        );
      }
    });
  }

  Future<PermissionStatus> _permissionStatus() {
    final requested = widget.requestActivityRecognitionPermission;
    if (requested != null) return requested();
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(PermissionStatus.granted);
    }
    return Permission.activityRecognition.request();
  }

  void _showFallback(String message) {
    if (!mounted || _completed) return;
    _noReadingTimer?.cancel();
    setState(() {
      _fallback = true;
      _fallbackMessage = message;
    });
  }

  void _onStepCount(int totalSteps) {
    if (_completed || !mounted) return;
    _noReadingTimer?.cancel();
    if (_paused) return;
    if (_baseline == null || _rebaseOnNextReading) {
      _baseline = totalSteps - _steps;
      _rebaseOnNextReading = false;
    }
    final next = totalSteps - _baseline!;
    if (next >= _steps) setState(() => _steps = next);
    if (next >= 500) _complete();
  }

  void _togglePaused() {
    setState(() {
      _paused = !_paused;
      if (!_paused) _rebaseOnNextReading = true;
    });
  }

  void _complete() {
    if (_completed || !mounted) return;
    _completed = true;
    _noReadingTimer?.cancel();
    unawaited(_stepSubscription?.cancel() ?? Future<void>.value());
    Navigator.of(context).pop(InterventionOutcome.completed);
  }

  @override
  void dispose() {
    _noReadingTimer?.cancel();
    _stepSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Walk 500 steps')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            '$_steps / 500 steps',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          LinearProgressIndicator(value: (_steps / 500).clamp(0, 1)),
          if (_fallback)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_fallbackMessage!),
            ),
          const Spacer(),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(InterventionOutcome.skipped),
                child: const Text('Skip'),
              ),
              FilledButton(
                onPressed: _togglePaused,
                child: Text(_paused ? 'Resume' : 'Pause'),
              ),
              if (_fallback)
                FilledButton(
                  onPressed: _complete,
                  child: const Text('I completed my walk'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
