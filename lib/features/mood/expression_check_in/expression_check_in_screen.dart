import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_frame_transformer.dart';
import 'expression_scan_controller.dart';
import 'expression_scan_logic.dart';
import 'mlkit_expression_analyzer.dart';

class ExpressionCheckInResult {
  const ExpressionCheckInResult({
    required this.completed,
    this.cue,
    this.source,
  });

  final bool completed;
  final ExpressionCue? cue;
  final ExpressionCueSource? source;
}

class ExpressionCheckInScreen extends StatefulWidget {
  const ExpressionCheckInScreen({super.key, this.controller});

  /// An injected controller makes the camera states testable without hardware.
  final ExpressionScanController? controller;

  @override
  State<ExpressionCheckInScreen> createState() =>
      _ExpressionCheckInScreenState();
}

class _ExpressionCheckInScreenState extends State<ExpressionCheckInScreen>
    with WidgetsBindingObserver {
  late final ExpressionScanController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        ExpressionScanController(
          camera: DeviceExpressionCamera(),
          permission: const DeviceCameraPermission(),
          analyzer: MlKitExpressionAnalyzer(),
        );
    _controller.addListener(_onScanChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_controller.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onScanChanged);
    unawaited(_controller.disposeAsync());
    super.dispose();
  }

  void _onScanChanged() {
    if (mounted) setState(() {});
  }

  void _finish({ExpressionCue? cue}) {
    Navigator.of(context).pop(
      ExpressionCheckInResult(
        completed: cue != null,
        cue: cue,
        source: cue == null ? null : _controller.cueSource,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _controller.status;
    return Scaffold(
      appBar: AppBar(title: const Text('Expression Check-In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Center your face and look toward the camera.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text('Then tell us how you actually feel.'),
              const SizedBox(height: 18),
              if (_showsPreview(status)) ...[
                _cameraPreview(_controller.previewController),
                const SizedBox(height: 18),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _statusContent(status),
              ),
              if (kDebugMode && _controller.debugDecision != null) ...[
                const SizedBox(height: 12),
                _predictionDebugPanel(_controller.debugDecision!),
              ],
              const SizedBox(height: 24),
              const Text(
                'Processed on this device. Camera frames are not saved.',
              ),
              const SizedBox(height: 8),
              const Text(
                'An expression cue cannot tell how you actually feel.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _predictionDebugPanel(ProductCueDecision decision) {
    final raw = decision.ferEma.scores;
    final labels = ExpressionModelOutput.labels;
    final rawOrder = List<int>.generate(raw.length, (index) => index)
      ..sort((a, b) => raw[b].compareTo(raw[a]));
    final lines = <String>[
      'FER EMA',
      for (var i = 0; i < raw.length; i++)
        '${labels[i].name} ${raw[i].toStringAsFixed(2)}',
      'Raw top: ${labels[rawOrder[0]].name}',
      'Raw second: ${labels[rawOrder[1]].name}',
      'Raw margin: ${(raw[rawOrder[0]] - raw[rawOrder[1]]).toStringAsFixed(2)}',
      'PRODUCT EMA',
      for (final score in decision.productScores.entries)
        '${_debugCueName(score.key)} ${score.value.toStringAsFixed(2)}',
      'Top product: ${_debugCueName(decision.topCue)}',
      'Second: ${_debugCueName(decision.secondCue)}',
      'Margin: ${decision.margin.toStringAsFixed(2)}',
      'Candidate: ${decision.candidateCue == null ? '-' : _debugCueName(decision.candidateCue!)}',
      'Confirmations: ${decision.candidateConfirmations} / ${decision.requiredConfirmations}',
      'TREND',
      for (final trend in decision.trends.entries)
        '${_debugCueName(trend.key)}: ${trend.value >= 0 ? '+' : ''}${trend.value.toStringAsFixed(2)}',
      'Decision: ${switch (decision.status) {
        ExpressionDecisionStatus.continueScanning => 'CONTINUE',
        ExpressionDecisionStatus.accepted => 'ACCEPTED',
        ExpressionDecisionStatus.unclear => 'UNCLEAR',
      }}',
      'Reason: ${decision.reason}',
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.black87,
      child: Text(
        lines.join('\n'),
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  String _debugCueName(ExpressionCue cue) => switch (cue) {
    ExpressionCue.positiveLike => 'Upbeat',
    ExpressionCue.neutralLike => 'Neutral',
    ExpressionCue.subduedLike => 'Subdued',
    ExpressionCue.tenseLike => 'Tense',
    ExpressionCue.surprisedLike => 'Surprised',
    ExpressionCue.unclear => 'Unclear',
    ExpressionCue.smiling => 'Smiling',
    ExpressionCue.noStrongExpression => 'No strong expression',
  };

  bool _showsPreview(ScanStatus status) => switch (status) {
    ScanStatus.ready ||
    ScanStatus.noFace ||
    ScanStatus.multipleFaces ||
    ScanStatus.faceNotCentered ||
    ScanStatus.lookAtCamera ||
    ScanStatus.stabilizing => true,
    ScanStatus.noResult || ScanStatus.resultReady => true,
    _ => false,
  };

  Widget _cameraPreview(CameraController? camera) {
    final observation = _controller.lastObservation;
    return Semantics(
      label: 'Front camera preview with face guide',
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final isLandscape =
                  camera != null &&
                  (camera.value.deviceOrientation ==
                          DeviceOrientation.landscapeLeft ||
                      camera.value.deviceOrientation ==
                          DeviceOrientation.landscapeRight);
              final previewRatio = camera != null && camera.value.isInitialized
                  ? (isLandscape
                        ? camera.value.aspectRatio
                        : 1 / camera.value.aspectRatio)
                  : 3 / 4;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: camera != null && camera.value.isInitialized
                        ? FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: previewRatio * viewport.height,
                              height: viewport.height,
                              child: CameraPreview(camera),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: .55,
                      heightFactor: .75,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: const BorderRadius.all(
                            Radius.elliptical(180, 240),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (kDebugMode &&
                      observation?.faceBox != null &&
                      observation?.uprightSize != null)
                    CustomPaint(
                      painter: _DebugFacePainter(
                        geometry: ExpressionPreviewGeometry(
                          sourceSize: observation!.uprightSize!,
                          viewportSize: viewport,
                          mirrored: true,
                        ),
                        faceBox: observation.faceBox!,
                        cropBox: observation.cropBox,
                      ),
                    ),
                  if (kDebugMode && observation?.debugCropPng != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: Image.memory(observation!.debugCropPng!),
                      ),
                    ),
                  if (kDebugMode && observation?.faceBox != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        color: Colors.black87,
                        child: Text(
                          'raw ${observation!.rawSize} rot ${observation.rotationDegrees}\n'
                          'upright ${observation.uprightSize} view $viewport\n'
                          'face ${observation.faceBox}\n'
                          'crop ${observation.cropBox}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusContent(ScanStatus status) {
    switch (status) {
      case ScanStatus.initializing:
        return Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Starting camera...'),
            TextButton(
              onPressed: _finish,
              child: const Text('Continue without camera'),
            ),
          ],
        );
      case ScanStatus.permissionRequired:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Camera access lets you scan an expression on this device.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _controller.requestCamera,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Allow Camera'),
            ),
            TextButton(
              onPressed: _finish,
              child: const Text('Continue without camera'),
            ),
          ],
        );
      case ScanStatus.permissionDenied:
        return _actionState(
          title: 'Camera access is turned off',
          detail:
              'Enable camera access in device settings, or choose your mood manually.',
          action: 'Open Settings',
          onAction: _controller.openSettings,
        );
      case ScanStatus.cameraUnavailable:
        return _actionState(
          title: 'Camera unavailable',
          detail: 'Expression Check-In cannot use the front camera right now.',
          action: 'Try Again',
          onAction: _controller.retry,
        );
      case ScanStatus.failure:
        return _actionState(
          title: 'We could not get a clear expression cue',
          detail: 'Try again or continue with the normal mood check-in.',
          action: 'Try Again',
          onAction: _controller.retry,
        );
      case ScanStatus.noResult:
        return _actionState(
          title: "We couldn't get a clear expression cue.",
          detail: 'You can try again or continue without the camera.',
          action: 'Try again',
          onAction: _controller.retry,
        );
      case ScanStatus.resultReady:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _cueTitle(_controller.cue),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('This is only an expression cue.'),
            const Text('Does that match how you feel?'),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => _finish(cue: _controller.cue),
              child: const Text('Yes, somewhat'),
            ),
            TextButton(onPressed: _finish, child: const Text('Not really')),
            TextButton(
              onPressed: _controller.retry,
              child: const Text('Scan Again'),
            ),
            TextButton(onPressed: _finish, child: const Text('Skip')),
          ],
        );
      case ScanStatus.paused:
        return Column(
          children: [
            const Text('Scan paused. Return to the app to continue.'),
            TextButton(
              onPressed: _finish,
              child: const Text('Continue without camera'),
            ),
          ],
        );
      case ScanStatus.ready:
      case ScanStatus.noFace:
      case ScanStatus.multipleFaces:
      case ScanStatus.faceNotCentered:
      case ScanStatus.lookAtCamera:
      case ScanStatus.stabilizing:
        return Column(
          children: [
            Text(switch (status) {
              ScanStatus.noFace => 'Position your face inside the guide.',
              ScanStatus.multipleFaces => 'Keep only one face in the frame.',
              ScanStatus.faceNotCentered =>
                _controller.lastObservation?.positioningHint ??
                    'Center your face in the guide.',
              ScanStatus.lookAtCamera =>
                _controller.lastObservation?.positioningHint ??
                    'Look toward the camera.',
              ScanStatus.stabilizing => 'Hold still for a moment.',
              _ => 'Center one face in the guide.',
            }, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _finish,
              child: const Text('Continue without camera'),
            ),
          ],
        );
    }
  }

  String _cueTitle(ExpressionCue? cue) => switch (cue) {
    ExpressionCue.positiveLike =>
      'Your visible expression appeared more upbeat.',
    ExpressionCue.neutralLike =>
      'Your visible expression appeared fairly neutral.',
    ExpressionCue.subduedLike =>
      'Your visible expression appeared a little subdued.',
    ExpressionCue.tenseLike => 'Your visible expression appeared more tense.',
    ExpressionCue.surprisedLike =>
      'Your visible expression appeared more surprised.',
    ExpressionCue.smiling => 'Smiling expression detected',
    ExpressionCue.noStrongExpression => 'No strong expression detected',
    _ => 'Expression unclear',
  };

  Widget _actionState({
    required String title,
    required String detail,
    required String action,
    required VoidCallback onAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(detail),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onAction, child: Text(action)),
        TextButton(
          onPressed: _finish,
          child: const Text('Continue without camera'),
        ),
      ],
    );
  }
}

class _DebugFacePainter extends CustomPainter {
  const _DebugFacePainter({
    required this.geometry,
    required this.faceBox,
    required this.cropBox,
  });

  final ExpressionPreviewGeometry geometry;
  final Rect faceBox;
  final Rect? cropBox;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      geometry.mapRect(faceBox),
      Paint()
        ..color = Colors.lightGreenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (cropBox case final rect?) {
      canvas.drawRect(
        geometry.mapRect(rect),
        Paint()
          ..color = Colors.orangeAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DebugFacePainter oldDelegate) =>
      oldDelegate.faceBox != faceBox ||
      oldDelegate.cropBox != cropBox ||
      oldDelegate.geometry.viewportSize != geometry.viewportSize;
}
