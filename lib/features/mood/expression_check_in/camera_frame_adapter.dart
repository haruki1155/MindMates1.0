import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'expression_scan_logic.dart';

/// Converts the supported single-plane camera stream to app-owned frame data.
class CameraFrameAdapter {
  const CameraFrameAdapter({required this.platform});

  final TargetPlatform platform;

  ExpressionFrame? toFrame({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation orientation,
  }) {
    if (image.width <= 0 || image.height <= 0 || image.planes.length != 1) {
      return null;
    }

    final rawFormat = image.format.raw;
    final formatCode = switch (platform) {
      TargetPlatform.android when rawFormat == 17 => 17,
      // CameraX can label a requested NV21 single-plane buffer as YUV420.
      TargetPlatform.android when rawFormat == 35 => 17,
      TargetPlatform.iOS when rawFormat == 1111970369 => 1111970369,
      _ => null,
    };
    if (formatCode == null) return null;

    final deviceDegrees = switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final rotationDegrees = platform == TargetPlatform.iOS
        ? camera.sensorOrientation
        : camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + deviceDegrees) % 360
        : (camera.sensorOrientation - deviceDegrees + 360) % 360;
    if (rotationDegrees % 90 != 0) return null;

    final plane = image.planes.single;
    if (plane.bytes.isEmpty || plane.bytesPerRow <= 0) return null;
    return ExpressionFrame(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      rotationDegrees: rotationDegrees,
      formatCode: formatCode,
      timestamp: DateTime.now(),
    );
  }
}
