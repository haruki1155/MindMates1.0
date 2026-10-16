import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/intervention_models.dart';
import '../widgets/assessment_presentation.dart';

enum WalkingTrackingState {
  initializing,
  delayedReading,
  tracking,
  unavailable,
  manualFallback,
}

class InterventionWalkingScreen extends StatefulWidget {
  const InterventionWalkingScreen({
    super.key,
    this.stepCountStream,
    this.requestActivityRecognitionPermission,
    this.initialReadingDelay = const Duration(seconds: 5),
    this.noReadingTimeout = const Duration(seconds: 15),
  });

  final Stream<int>? stepCountStream;
  final Future<PermissionStatus> Function()?
  requestActivityRecognitionPermission;
  final Duration initialReadingDelay;
  final Duration noReadingTimeout;

  @override
  State<InterventionWalkingScreen> createState() =>
      _InterventionWalkingScreenState();
}

class _InterventionWalkingScreenState extends State<InterventionWalkingScreen> {
  int? _baseline;
  int? _lastSensorTotal;
  int _steps = 0;
  bool _paused = false;
  bool _completed = false;
  bool _rebaseOnNextReading = false;
  String? _fallbackMessage;
  WalkingTrackingState _state = WalkingTrackingState.initializing;
  StreamSubscription<int>? _stepSubscription;
  Timer? _delayedReadingTimer;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    unawaited(_startStepCounting());
  }

  Future<void> _startStepCounting() async {
    if (widget.stepCountStream == null) {
      final permission = await _permissionStatus();
      if (!mounted) return;
      if (!permission.isGranted) {
        _offerFallback(
          permission.isPermanentlyDenied
              ? 'Activity-recognition permission is permanently denied.'
              : 'Activity-recognition permission was not granted.',
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
      onError: (_) => _offerFallback(
        'Automatic step counting is unavailable on this device.',
      ),
    );
    _armInitialTimers();
  }

  Future<PermissionStatus> _permissionStatus() {
    final requested = widget.requestActivityRecognitionPermission;
    if (requested != null) return requested();
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(PermissionStatus.granted);
    }
    return Permission.activityRecognition.request();
  }

  void _armInitialTimers() {
    _delayedReadingTimer?.cancel();
    _watchdog?.cancel();
    _delayedReadingTimer = Timer(widget.initialReadingDelay, () {
      if (!mounted || _baseline != null || _completed || _paused) return;
      setState(() => _state = WalkingTrackingState.delayedReading);
    });
    _watchdog = Timer(widget.noReadingTimeout, () {
      if (_baseline == null) {
        _offerFallback('No step reading arrived from your phone.');
      }
    });
  }

  void _armStallWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(widget.noReadingTimeout, () {
      if (_paused || _completed || _state != WalkingTrackingState.tracking) {
        return;
      }
      _offerFallback('Step readings stopped arriving from your phone.');
    });
  }

  void _offerFallback(String reason) {
    if (!mounted ||
        _completed ||
        _state == WalkingTrackingState.unavailable ||
        _state == WalkingTrackingState.manualFallback) {
      return;
    }
    _delayedReadingTimer?.cancel();
    _watchdog?.cancel();
    unawaited(_stepSubscription?.cancel() ?? Future<void>.value());
    setState(() {
      _state = WalkingTrackingState.unavailable;
      _fallbackMessage =
          '$reason You can use a timed-walk alternative or skip this activity.';
    });
  }

  void _onStepCount(int totalSteps) {
    if (_completed ||
        !mounted ||
        _state == WalkingTrackingState.unavailable ||
        _state == WalkingTrackingState.manualFallback) {
      return;
    }
    if (totalSteps < 0) return;
    _delayedReadingTimer?.cancel();
    final previousTotal = _lastSensorTotal;
    _lastSensorTotal = totalSteps;
    if (_paused) return;
    if (_baseline == null ||
        _rebaseOnNextReading ||
        (previousTotal != null && totalSteps < previousTotal)) {
      // Rebase after a resumed session or an Android pedometer reset, while
      // retaining already-earned progress and never inventing steps.
      _baseline = totalSteps - _steps;
      _rebaseOnNextReading = false;
    }
    final next = totalSteps - _baseline!;
    if (next >= _steps) {
      setState(() {
        _steps = next;
        _state = WalkingTrackingState.tracking;
      });
    }
    _armStallWatchdog();
    if (next >= 500) _completeAutomatically();
  }

  void _togglePaused() {
    if (_state == WalkingTrackingState.unavailable ||
        _state == WalkingTrackingState.manualFallback) {
      return;
    }
    setState(() {
      _paused = !_paused;
      if (!_paused) _rebaseOnNextReading = true;
    });
    if (_paused) {
      _watchdog?.cancel();
    } else {
      _armStallWatchdog();
    }
  }

  void _completeAutomatically() {
    if (_completed || !mounted) return;
    _completed = true;
    _cancelTracking();
    Navigator.of(context).pop(InterventionOutcome.completed);
  }

  void _recordSelfReportedCompletion() {
    if (_completed || !mounted) return;
    _completed = true;
    _cancelTracking();
    Navigator.of(context).pop(InterventionOutcome.selfReportedCompleted);
  }

  void _beginManualFallback() {
    setState(() => _state = WalkingTrackingState.manualFallback);
  }

  void _cancelTracking() {
    _delayedReadingTimer?.cancel();
    _watchdog?.cancel();
    unawaited(_stepSubscription?.cancel() ?? Future<void>.value());
  }

  @override
  void dispose() {
    _cancelTracking();
    super.dispose();
  }

  String get _stateMessage => switch (_state) {
    WalkingTrackingState.initializing =>
      'Preparing automatic step tracking. Some phones may report the first reading after a short delay.',
    WalkingTrackingState.delayedReading =>
      'Still waiting for your phone’s step sensor. Keep the app open while we wait.',
    WalkingTrackingState.tracking =>
      'Automatic tracking is active. Step updates can arrive in batches on some phones.',
    WalkingTrackingState.unavailable =>
      _fallbackMessage ?? 'Automatic step tracking is unavailable.',
    WalkingTrackingState.manualFallback =>
      _fallbackMessage ?? 'Automatic step tracking is unavailable.',
  };

  @override
  Widget build(BuildContext context) {
    final unavailable =
        _state == WalkingTrackingState.unavailable ||
        _state == WalkingTrackingState.manualFallback;
    return Scaffold(
      appBar: AppBar(title: const Text('Walking activity')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 40)
                    .clamp(0, double.infinity)
                    .toDouble(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'A short walking break',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const AssessmentStatusPill(label: '500-step goal'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  AssessmentSurfaceCard(
                    color: AssessmentPresentation.softAccent(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.directions_walk_rounded,
                              color: AssessmentPresentation.onSoftAccent(
                                context,
                              ),
                              size: 30,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$_steps / 500 steps',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: (_steps / 500).clamp(0, 1),
                          minHeight: 9,
                          borderRadius: BorderRadius.circular(999),
                          color: AssessmentPresentation.onSoftAccent(context),
                          backgroundColor: AssessmentPresentation.softAccent(
                            context,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _stateMessage,
                          style: TextStyle(
                            color: AssessmentPresentation.muted(context),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!unavailable)
                    FilledButton.icon(
                      style: AssessmentPresentation.filledButtonStyle(context),
                      onPressed: _togglePaused,
                      icon: Icon(
                        _paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      label: Text(
                        _paused ? 'Resume tracking' : 'Pause tracking',
                      ),
                    ),
                  if (_state == WalkingTrackingState.unavailable)
                    FilledButton.icon(
                      style: AssessmentPresentation.filledButtonStyle(context),
                      onPressed: _beginManualFallback,
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('Use timed-walk option'),
                    ),
                  if (_state == WalkingTrackingState.manualFallback)
                    FilledButton.icon(
                      style: AssessmentPresentation.filledButtonStyle(context),
                      onPressed: _recordSelfReportedCompletion,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Record self-reported walk'),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: AssessmentPresentation.textButtonStyle(context),
                    onPressed: () =>
                        Navigator.of(context).pop(InterventionOutcome.skipped),
                    child: const Text('Skip activity'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
