// Public constructor arguments keep the camera, permission, and analyzer
// interfaces easy to inject while their stored fields remain private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'camera_frame_adapter.dart';
import 'expression_scan_logic.dart';

enum CameraAccess { granted, needsRequest, permanentlyDenied }

abstract interface class ExpressionCameraPermission {
  Future<CameraAccess> check();
  Future<CameraAccess> request();
  Future<void> openSettings();
}

class DeviceCameraPermission implements ExpressionCameraPermission {
  const DeviceCameraPermission();

  @override
  Future<CameraAccess> check() async => _map(await Permission.camera.status);

  @override
  Future<CameraAccess> request() async =>
      _map(await Permission.camera.request());

  @override
  Future<void> openSettings() async => openAppSettings();

  CameraAccess _map(PermissionStatus status) {
    if (status.isGranted) return CameraAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraAccess.permanentlyDenied;
    }
    return CameraAccess.needsRequest;
  }
}

abstract interface class ExpressionCamera {
  CameraController? get previewController;
  Future<void> start(void Function(ExpressionFrame) onFrame);
  Future<void> stop();
}

class DeviceExpressionCamera implements ExpressionCamera {
  DeviceExpressionCamera({CameraFrameAdapter? adapter})
    : _adapter = adapter ?? CameraFrameAdapter(platform: defaultTargetPlatform);

  final CameraFrameAdapter _adapter;
  CameraController? _controller;
  Future<void>? _starting;
  Future<void>? _stopping;
  int _generation = 0;
  bool _wantRunning = false;

  @override
  CameraController? get previewController => _controller;

  @override
  Future<void> start(void Function(ExpressionFrame) onFrame) async {
    _wantRunning = true;
    await _stopping;
    if (!_wantRunning) return;
    if (_controller?.value.isStreamingImages == true) return;
    if (_starting case final pending?) return pending;
    final generation = ++_generation;
    final pending = _startInternal(onFrame, generation);
    _starting = pending;
    try {
      await pending;
    } finally {
      if (identical(_starting, pending)) _starting = null;
    }
  }

  Future<void> _startInternal(
    void Function(ExpressionFrame) onFrame,
    int generation,
  ) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError('Expression scanning requires Android or iOS.');
    }
    final cameras = await availableCameras();
    if (!_wantRunning || generation != _generation) return;
    final front = cameras.where(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    if (front.isEmpty) throw StateError('Front camera unavailable.');
    final camera = front.first;
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
      if (!_wantRunning || generation != _generation) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream((image) {
        if (!_wantRunning || generation != _generation) return;
        final frame = _adapter.toFrame(
          image: image,
          camera: camera,
          orientation: controller.value.deviceOrientation,
        );
        if (frame != null) onFrame(frame);
      });
    } catch (_) {
      if (identical(_controller, controller)) _controller = null;
      await controller.dispose();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _wantRunning = false;
    ++_generation;
    if (_stopping case final pending?) return pending;
    final pending = _stopInternal();
    _stopping = pending;
    try {
      await pending;
    } finally {
      if (identical(_stopping, pending)) _stopping = null;
    }
  }

  Future<void> _stopInternal() async {
    try {
      await _starting;
    } catch (_) {
      // A partially opened controller is disposed by the start path.
    }
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } finally {
      await controller.dispose();
    }
  }
}

class ExpressionScanController extends ChangeNotifier {
  ExpressionScanController({
    required ExpressionCamera camera,
    required ExpressionCameraPermission permission,
    required ExpressionAnalyzer analyzer,
    this.config = const ExpressionScanConfig(),
  }) : _camera = camera,
       _permission = permission,
       _analyzer = analyzer,
       _filter = ExpressionStabilityFilter(config: config);

  final ExpressionCamera _camera;
  final ExpressionCameraPermission _permission;
  final ExpressionAnalyzer _analyzer;
  final ExpressionStabilityFilter _filter;
  final ExpressionScanConfig config;

  ScanStatus _status = ScanStatus.initializing;
  ExpressionCue? _cue;
  ExpressionCueSource? _cueSource;
  ExpressionObservation? _lastObservation;
  ProductCueDecision? _debugDecision;
  Timer? _timeout;
  Timer? _frameWatchdog;
  int _idleFrameTicks = 0;
  DateTime? _lastProcessedAt;
  Future<void>? _inFlight;
  Future<void>? _opening;
  Future<void>? _pauseTask;
  Future<void>? _stopTask;
  int _epoch = 0;
  int _scanGeneration = 0;
  bool _processing = false;
  bool _disposed = false;
  bool _paused = false;
  bool _recovering = false;

  ScanStatus get status => _status;
  ExpressionCue? get cue => _cue;
  ExpressionCueSource? get cueSource => _cueSource;
  ExpressionObservation? get lastObservation => _lastObservation;
  ProductCueDecision? get debugDecision => _debugDecision;
  CameraController? get previewController => _camera.previewController;

  Future<void> start() {
    if (_disposed || _paused || _status == ScanStatus.resultReady) {
      return Future.value();
    }
    if (_opening case final pending?) return pending;
    final pending = _startSession();
    _opening = pending;
    return pending.whenComplete(() {
      if (identical(_opening, pending)) _opening = null;
    });
  }

  Future<void> _startSession() async {
    final epoch = ++_epoch;
    _setStatus(ScanStatus.initializing);
    try {
      final access = await _permission.check();
      if (_disposed || epoch != _epoch) return;
      if (access != CameraAccess.granted) {
        _setStatus(
          access == CameraAccess.permanentlyDenied
              ? ScanStatus.permissionDenied
              : ScanStatus.permissionRequired,
        );
        return;
      }
      await _openCamera(epoch);
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _setStatus(ScanStatus.cameraUnavailable);
        await _stopCamera();
      }
    }
  }

  Future<void> requestCamera() async {
    if (_disposed || _paused) return;
    final epoch = _epoch;
    try {
      final access = await _permission.request();
      if (_disposed || _paused || epoch != _epoch) return;
      if (access == CameraAccess.granted) {
        await start();
      } else {
        _setStatus(
          access == CameraAccess.permanentlyDenied
              ? ScanStatus.permissionDenied
              : ScanStatus.permissionRequired,
        );
      }
    } catch (_) {
      if (!_disposed && !_paused && epoch == _epoch) {
        _setStatus(ScanStatus.permissionDenied);
      }
    }
  }

  Future<void> openSettings() => _permission.openSettings();

  Future<void> retry() async {
    if (!_disposed &&
        !_paused &&
        (_status == ScanStatus.noResult || _status == ScanStatus.resultReady)) {
      ++_scanGeneration;
      _cue = null;
      _cueSource = null;
      _lastObservation = null;
      _debugDecision = null;
      _filter.reset();
      _lastProcessedAt = null;
      _setStatus(ScanStatus.ready);
      _startScanTimeout();
      _startFrameWatchdog();
      return;
    }
    await pause();
    if (_disposed) return;
    _cue = null;
    _cueSource = null;
    _debugDecision = null;
    _filter.reset();
    _paused = false;
    await start();
  }

  Future<void> resume() async {
    if (_disposed || _status != ScanStatus.paused) return;
    final epoch = _epoch;
    await _pauseTask;
    if (_disposed || epoch != _epoch) return;
    _paused = false;
    await start();
  }

  Future<void> pause() {
    if (_disposed) return Future.value();
    if (_pauseTask case final task?) return task;
    _paused = true;
    ++_epoch;
    ++_scanGeneration;
    _timeout?.cancel();
    _frameWatchdog?.cancel();
    _filter.reset();
    _setStatus(ScanStatus.paused);
    late final Future<void> task;
    task = _finishPause().whenComplete(() {
      if (identical(_pauseTask, task)) _pauseTask = null;
    });
    _pauseTask = task;
    return task;
  }

  Future<void> _finishPause() async {
    try {
      await _opening;
    } catch (_) {
      // The camera failed to open; still release any partially opened device.
    }
    await _stopCamera();
  }

  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _timeout?.cancel();
    _frameWatchdog?.cancel();
    await _pauseTask;
    await _opening;
    await _stopCamera();
    await _inFlight;
    await _analyzer.dispose();
    super.dispose();
  }

  Future<void> _openCamera(int epoch) async {
    if (_analyzer case final InitializableExpressionAnalyzer analyzer) {
      await analyzer.initialize();
      if (_disposed || epoch != _epoch) return;
    }
    await _camera
        .start((frame) {
          if (epoch == _epoch) _onFrame(frame);
        })
        .timeout(const Duration(seconds: 7));
    if (_disposed || epoch != _epoch) return;
    _lastProcessedAt = null;
    _debugDecision = null;
    ++_scanGeneration;
    _filter.reset();
    _setStatus(ScanStatus.ready);
    _startScanTimeout();
    _startFrameWatchdog();
  }

  void _startScanTimeout() {
    _timeout?.cancel();
    final scanGeneration = _scanGeneration;
    _timeout = Timer(config.scanTimeout, () {
      if (_disposed || _paused || scanGeneration != _scanGeneration) return;
      ++_scanGeneration;
      _debugDecision = _filter.markUnclear() ?? _debugDecision;
      _frameWatchdog?.cancel();
      _setStatus(ScanStatus.noResult);
    });
  }

  void _startFrameWatchdog() {
    _frameWatchdog?.cancel();
    _idleFrameTicks = 0;
    _frameWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _paused || _recovering || !_expectsFrames) return;
      _idleFrameTicks++;
      if (_idleFrameTicks * 1000 >= config.frameTimeout.inMilliseconds) {
        unawaited(_recoverCamera());
      }
    });
  }

  bool get _expectsFrames => switch (_status) {
    ScanStatus.ready ||
    ScanStatus.noFace ||
    ScanStatus.multipleFaces ||
    ScanStatus.faceNotCentered ||
    ScanStatus.lookAtCamera ||
    ScanStatus.stabilizing => true,
    _ => false,
  };

  Future<void> _recoverCamera() async {
    if (_recovering || _disposed || _paused) return;
    _recovering = true;
    final epoch = ++_epoch;
    ++_scanGeneration;
    _timeout?.cancel();
    _frameWatchdog?.cancel();
    _filter.reset();
    _setStatus(ScanStatus.initializing);
    try {
      await _stopCamera();
      if (_disposed || _paused || epoch != _epoch) return;
      await _openCamera(epoch);
    } catch (_) {
      if (!_disposed && !_paused && epoch == _epoch) {
        _setStatus(ScanStatus.cameraUnavailable);
        await _stopCamera();
      }
    } finally {
      _recovering = false;
    }
  }

  void _onFrame(ExpressionFrame frame) {
    _idleFrameTicks = 0;
    if (_disposed ||
        _processing ||
        (_status != ScanStatus.ready &&
            _status != ScanStatus.noFace &&
            _status != ScanStatus.multipleFaces &&
            _status != ScanStatus.faceNotCentered &&
            _status != ScanStatus.lookAtCamera &&
            _status != ScanStatus.stabilizing)) {
      return;
    }
    final now = DateTime.now();
    if (_lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < config.processEvery) {
      return;
    }
    _lastProcessedAt = now;
    _processing = true;
    final epoch = _epoch;
    final scanGeneration = _scanGeneration;
    _inFlight = _process(frame, epoch, scanGeneration);
  }

  Future<void> _process(
    ExpressionFrame frame,
    int epoch,
    int scanGeneration,
  ) async {
    try {
      final observation = await _analyzer.analyze(frame);
      if (_disposed || epoch != _epoch || scanGeneration != _scanGeneration) {
        return;
      }
      _lastObservation = observation;
      if (kDebugMode) notifyListeners();
      final validation = validateFace(observation);
      if (validation != ScanStatus.stabilizing) {
        _filter.reset();
        _debugDecision = null;
        _setStatus(validation);
        return;
      }
      final stable = _filter.addObservation(observation);
      _debugDecision = _filter.latestDecision;
      if (kDebugMode) notifyListeners();
      if (stable == null) {
        _setStatus(ScanStatus.stabilizing);
      } else {
        _cue = stable;
        _cueSource = observation.modelOutput == null
            ? ExpressionCueSource.mlKit
            : ExpressionCueSource.tflite;
        _timeout?.cancel();
        _frameWatchdog?.cancel();
        ++_scanGeneration;
        _setStatus(ScanStatus.resultReady);
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch && scanGeneration == _scanGeneration) {
        _timeout?.cancel();
        _frameWatchdog?.cancel();
        _setStatus(ScanStatus.failure);
        await _stopCamera();
      }
    } finally {
      _processing = false;
    }
  }

  void _setStatus(ScanStatus value) {
    if (_disposed || _status == value) return;
    _status = value;
    notifyListeners();
  }

  Future<void> _stopCamera() async {
    if (_stopTask case final pending?) return pending;
    final pending = _camera.stop();
    _stopTask = pending;
    try {
      await pending;
    } catch (_) {
      if (!_disposed) _setStatus(ScanStatus.failure);
    } finally {
      if (identical(_stopTask, pending)) _stopTask = null;
    }
  }
}
