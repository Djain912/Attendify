// File: lib/firebase_options.dart
// Contains the configuration for Firebase services.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // Since your previous main.dart only had web configuration explicitly defined,
    // I'm setting the same web configuration for all platforms
    // You should update these with platform-specific configurations if available
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
              'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
              'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyAC1YhOZ_L_1MOHFzb1hSMY2mQNR_DAl8M",
    authDomain: "attendence-b9641.firebaseapp.com",
    projectId: "attendence-b9641",
    storageBucket: "attendence-b9641.firebasestorage.app",
    messagingSenderId: "959288411659",
    appId: "1:959288411659:web:a9e87731207b75493fa90e",
    measurementId: "G-B2TE53WQJW",
  );

  // For other platforms, I'm using the same values as web
  // You should update these with actual values for each platform if available
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyAC1YhOZ_L_1MOHFzb1hSMY2mQNR_DAl8M",
    projectId: "attendence-b9641",
    storageBucket: "attendence-b9641.firebasestorage.app",
    messagingSenderId: "959288411659",
    appId: "1:959288411659:web:a9e87731207b75493fa90e",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyAC1YhOZ_L_1MOHFzb1hSMY2mQNR_DAl8M",
    projectId: "attendence-b9641",
    storageBucket: "attendence-b9641.firebasestorage.app",
    messagingSenderId: "959288411659",
    appId: "1:959288411659:web:a9e87731207b75493fa90e",
    // You'll need to add these values for iOS
    iosClientId: "YOUR_IOS_CLIENT_ID",
    iosBundleId: "YOUR_IOS_BUNDLE_ID",
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: "AIzaSyAC1YhOZ_L_1MOHFzb1hSMY2mQNR_DAl8M",
    projectId: "attendence-b9641",
    storageBucket: "attendence-b9641.firebasestorage.app",
    messagingSenderId: "959288411659",
    appId: "1:959288411659:web:a9e87731207b75493fa90e",
    // You'll need to add these values for macOS
    iosClientId: "YOUR_IOS_CLIENT_ID",
    iosBundleId: "YOUR_IOS_BUNDLE_ID",
  );
}// TODO Implement this library.