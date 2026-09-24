import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'expression_scan_logic.dart';
import 'camera_frame_transformer.dart';
import 'tflite_expression_classifier.dart';

/// The only feature class that owns native ML Kit objects.
class MlKitExpressionAnalyzer
    implements ExpressionAnalyzer, InitializableExpressionAnalyzer {
  MlKitExpressionAnalyzer({
    FaceDetector? detector,
    CameraFrameTransformer? frameTransformer,
    TfliteExpressionClassifier? classifier,
    this.enableTflite = true,
  }) : _frameTransformer = frameTransformer ?? const CameraFrameTransformer(),
       _classifier = classifier ?? TfliteExpressionClassifier(),
       _detector =
           detector ??
           FaceDetector(
             options: FaceDetectorOptions(
               enableClassification: true,
               enableTracking: true,
               performanceMode: FaceDetectorMode.fast,
             ),
           );

  final FaceDetector _detector;
  final CameraFrameTransformer _frameTransformer;
  final TfliteExpressionClassifier _classifier;
  final bool enableTflite;
  bool _tfliteAvailable = false;

  bool get isTfliteAvailable => _tfliteAvailable;

  @override
  Future<void> initialize() async {
    if (!enableTflite || _tfliteAvailable) return;
    try {
      await _classifier.initialize();
      _tfliteAvailable = _classifier.isInitialized;
    } catch (error) {
      _tfliteAvailable = false;
      if (kDebugMode) {
        debugPrint(
          'Expression model unavailable; using ML Kit fallback: $error',
        );
      }
    }
  }

  @override
  Future<ExpressionObservation> analyze(ExpressionFrame frame) async {
    final rotation = InputImageRotationValue.fromRawValue(
      frame.rotationDegrees,
    );
    final format = InputImageFormatValue.fromRawValue(frame.formatCode);
    if (rotation == null || format == null) {
      throw ArgumentError('Unsupported expression frame metadata.');
    }
    final image = InputImage.fromBytes(
      bytes: frame.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: frame.bytesPerRow,
      ),
    );
    final faces = await _detector.processImage(image);
    if (faces.length != 1) {
      return ExpressionObservation(
        faceCount: faces.length,
        isFaceCentered: false,
        isFacingCamera: false,
        smileProbability: null,
        timestamp: frame.timestamp,
      );
    }

    final face = faces.single;
    final isRotated =
        frame.rotationDegrees == 90 || frame.rotationDegrees == 270;
    final imageWidth = (isRotated ? frame.height : frame.width).toDouble();
    final imageHeight = (isRotated ? frame.width : frame.height).toDouble();
    final centerX = face.boundingBox.center.dx / imageWidth;
    final centerY = face.boundingBox.center.dy / imageHeight;
    final widthRatio = face.boundingBox.width / imageWidth;
    final isCentered =
        centerX >= 0.3 &&
        centerX <= 0.7 &&
        centerY >= 0.25 &&
        centerY <= 0.75 &&
        widthRatio >= 0.22 &&
        widthRatio <= 0.78;
    final yaw = face.headEulerAngleY;
    final roll = face.headEulerAngleZ;
    final isFacingCamera =
        yaw != null && roll != null && yaw.abs() <= 18 && roll.abs() <= 18;
    final positioningHint = widthRatio < .22
        ? 'Move a little closer.'
        : widthRatio > .78
        ? 'Move slightly farther away.'
        : !isCentered
        ? 'Center your face in the guide.'
        : !isFacingCamera
        ? 'Look toward the camera and keep your head level.'
        : null;

    ExpressionModelOutput? modelOutput;
    Rect? cropBox;
    Uint8List? debugCropPng;
    if (_tfliteAvailable && isCentered && isFacingCamera) {
      try {
        final crop = _frameTransformer.faceCrop(frame, face.boundingBox);
        if (crop != null) {
          if (kDebugMode) {
            cropBox = _frameTransformer.cropRect(
              Size(imageWidth, imageHeight),
              face.boundingBox,
            );
            debugCropPng = Uint8List.fromList(img.encodePng(crop));
          }
          final startedAt = DateTime.now();
          modelOutput = _classifier.classify(crop);
          if (kDebugMode) {
            debugPrint(
              'Expression inference ${DateTime.now().difference(startedAt).inMilliseconds}ms; '
              'scores=${modelOutput.scores}',
            );
          }
        }
      } catch (error) {
        // TFLite is optional. One failed frame must not end a manual check-in.
        if (kDebugMode) debugPrint('Expression inference skipped: $error');
      }
    }

    return ExpressionObservation(
      faceCount: 1,
      isFaceCentered: isCentered,
      isFacingCamera: isFacingCamera,
      smileProbability: face.smilingProbability,
      modelOutput: modelOutput,
      faceBox: kDebugMode ? face.boundingBox : null,
      uprightSize: kDebugMode ? Size(imageWidth, imageHeight) : null,
      cropBox: cropBox,
      debugCropPng: debugCropPng,
      rawSize: kDebugMode
          ? Size(frame.width.toDouble(), frame.height.toDouble())
          : null,
      rotationDegrees: kDebugMode ? frame.rotationDegrees : null,
      positioningHint: positioningHint,
      timestamp: frame.timestamp,
    );
  }

  @override
  Future<void> dispose() async {
    _classifier.dispose();
    await _detector.close();
  }
}
