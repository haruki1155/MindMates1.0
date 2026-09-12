import 'dart:io';

import 'package:image/image.dart' as image;

const sourcePath = 'assets/images/APP LOGO/MindMate_LOGO.jpg';

void main() {
  final source = image.decodeImage(File(sourcePath).readAsBytesSync());
  if (source == null) {
    throw StateError('Could not decode $sourcePath.');
  }

  const androidIcons = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
  };
  const iosIcons = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  const macosIcons = <String, int>{
    'app_icon_16.png': 16,
    'app_icon_32.png': 32,
    'app_icon_64.png': 64,
    'app_icon_128.png': 128,
    'app_icon_256.png': 256,
    'app_icon_512.png': 512,
    'app_icon_1024.png': 1024,
  };
  const webIcons = <String, int>{
    'web/favicon.png': 32,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
  };

  _writePngs(source, androidIcons);
  _writePngs(
    source,
    iosIcons.map(
      (name, size) =>
          MapEntry('ios/Runner/Assets.xcassets/AppIcon.appiconset/$name', size),
    ),
  );
  _writePngs(
    source,
    macosIcons.map(
      (name, size) => MapEntry(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/$name',
        size,
      ),
    ),
  );
  _writePngs(source, webIcons);

  final windowsIcon = image.copyResize(
    source,
    width: 256,
    height: 256,
    interpolation: image.Interpolation.cubic,
  );
  File('windows/runner/resources/app_icon.ico')
    ..createSync(recursive: true)
    ..writeAsBytesSync(image.encodeIco(windowsIcon));
}

void _writePngs(image.Image source, Map<String, int> outputs) {
  for (final output in outputs.entries) {
    final resized = image.copyResize(
      source,
      width: output.value,
      height: output.value,
      interpolation: image.Interpolation.cubic,
    );
    File(output.key)
      ..createSync(recursive: true)
      ..writeAsBytesSync(image.encodePng(resized));
  }
}
