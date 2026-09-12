import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

class DevelopmentFirebaseOptions {
  const DevelopmentFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Development Firebase is configured for Android only.',
      );
    }
    return android;
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyD4utPqhhMfzEawaXorlqqZ2wuVqRVX-vA',
    appId: '1:1004916101316:android:e4c840c1c3070222c73991',
    messagingSenderId: '1004916101316',
    projectId: 'mindmate-dev-4e91c',
    storageBucket: 'mindmate-dev-4e91c.firebasestorage.app',
  );
}
