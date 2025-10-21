import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDsKBjUHmQH08YiH5SdcQcBZbgMbsSri88',
    appId: '1:494039887423:android:b3f75375d7f0c79c24128a',
    messagingSenderId: '494039887423',
    projectId: 'carpal-b1f78',
    storageBucket: 'carpal-b1f78.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDqBTxFEN0F_YxhWCTcVOqImGIHhGfbimI',
    appId: '1:494039887423:ios:bcbc5dd6ff771bba24128a',
    messagingSenderId: '494039887423',
    projectId: 'carpal-b1f78',
    storageBucket: 'carpal-b1f78.appspot.com',
    iosBundleId: 'com.carpal.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDsKBjUHmQH08YiH5SdcQcBZbgMbsSri88',
    appId: '1:494039887423:web:1234567890abcdef24128a',
    messagingSenderId: '494039887423',
    projectId: 'carpal-b1f78',
    authDomain: 'carpal-b1f78.firebaseapp.com',
    storageBucket: 'carpal-b1f78.appspot.com',
  );
}
