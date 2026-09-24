import 'dart:ui';

import 'package:image/image.dart' as img;

import 'expression_scan_logic.dart';

/// Converts a supported camera frame into the same upright coordinate space
/// used by ML Kit, then returns a padded square face crop for local inference.
class CameraFrameTransformer {
  const CameraFrameTransformer({this.cropPadding = 0.12});

  final double cropPadding;

  Rect? cropRect(Size uprightSize, Rect boundingBox) {
    final side = boundingBox.width > boundingBox.height
        ? boundingBox.width
        : boundingBox.height;
    if (!side.isFinite || side <= 0) return null;
    final paddedSide = side * (1 + cropPadding * 2);
    final rect = Rect.fromCenter(
      center: boundingBox.center,
      width: paddedSide,
      height: paddedSide,
    );
    if (rect.left < 0 ||
        rect.top < 0 ||
        rect.right > uprightSize.width ||
        rect.bottom > uprightSize.height) {
      return null;
    }
    return rect;
  }

  img.Image? faceCrop(ExpressionFrame frame, Rect boundingBox) {
    if (cropPadding < 0 || frame.width <= 0 || frame.height <= 0) return null;
    final source = _decode(frame);
    if (source == null) return null;
    final upright = frame.rotationDegrees == 0
        ? source
        : img.copyRotate(source, angle: frame.rotationDegrees);

    // ML Kit reports bounds after the InputImage rotation has been applied.
    final expectedWidth =
        frame.rotationDegrees == 90 || frame.rotationDegrees == 270
        ? frame.height
        : frame.width;
    final expectedHeight =
        frame.rotationDegrees == 90 || frame.rotationDegrees == 270
        ? frame.width
        : frame.height;
    if (upright.width != expectedWidth || upright.height != expectedHeight) {
      return null;
    }

    final rect = cropRect(
      Size(upright.width.toDouble(), upright.height.toDouble()),
      boundingBox,
    );
    if (rect == null) return null;

    final cropLeft = rect.left.floor();
    final cropTop = rect.top.floor();
    final cropRight = rect.right.ceil().clamp(0, upright.width).toInt();
    final cropBottom = rect.bottom.ceil().clamp(0, upright.height).toInt();
    final cropWidth = cropRight - cropLeft;
    final cropHeight = cropBottom - cropTop;
    if (cropWidth <= 0 || cropHeight <= 0) return null;
    return img.copyCrop(
      upright,
      x: cropLeft,
      y: cropTop,
      width: cropWidth,
      height: cropHeight,
    );
  }

  img.Image? _decode(ExpressionFrame frame) {
    // NV21 starts with the Y plane. The model needs grayscale, so using that
    // plane avoids unnecessary RGB conversion on every camera frame.
    if (frame.formatCode == 17) {
      if (frame.bytesPerRow < frame.width ||
          frame.bytes.length < frame.bytesPerRow * frame.height) {
        return null;
      }
      return img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.bytes.buffer,
        bytesOffset: frame.bytes.offsetInBytes,
        numChannels: 1,
        rowStride: frame.bytesPerRow,
        order: img.ChannelOrder.red,
      );
    }
    // iOS camera frames are provided as one BGRA plane.
    if (frame.formatCode == 1111970369) {
      if (frame.bytesPerRow < frame.width * 4 ||
          frame.bytes.length < frame.bytesPerRow * frame.height) {
        return null;
      }
      return img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.bytes.buffer,
        bytesOffset: frame.bytes.offsetInBytes,
        numChannels: 4,
        rowStride: frame.bytesPerRow,
        order: img.ChannelOrder.bgra,
      );
    }
    return null;
  }
}

/// Maps ML Kit's upright image coordinates into a cropped preview viewport.
class ExpressionPreviewGeometry {
  const ExpressionPreviewGeometry({
    required this.sourceSize,
    required this.viewportSize,
    required this.mirrored,
  });

  final Size sourceSize;
  final Size viewportSize;
  final bool mirrored;

  double get scale {
    final horizontal = viewportSize.width / sourceSize.width;
    final vertical = viewportSize.height / sourceSize.height;
    return horizontal > vertical ? horizontal : vertical;
  }

  double get offsetX => (sourceSize.width * scale - viewportSize.width) / 2;
  double get offsetY => (sourceSize.height * scale - viewportSize.height) / 2;

  Rect mapRect(Rect sourceRect) {
    final left = mirrored
        ? sourceSize.width - sourceRect.right
        : sourceRect.left;
    return Rect.fromLTWH(
      left * scale - offsetX,
      sourceRect.top * scale - offsetY,
      sourceRect.width * scale,
      sourceRect.height * scale,
    );
  }
}
