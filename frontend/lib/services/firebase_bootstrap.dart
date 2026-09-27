import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class FirebaseBootstrap {
  static const _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyB3t9wHvsMOQLeZDVGM4Kf0TH6C3xj6UiE',
  );
  static const _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'club-jeronimo-zarlenga',
  );
  static const _senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '724479043069',
  );
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
    defaultValue: '1:724479043069:android:05646c0700f9661b1fa594',
  );
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static bool get isConfigured => _options != null;

  static FirebaseOptions? get _options {
    if (_apiKey.isEmpty || _projectId.isEmpty || _senderId.isEmpty) {
      return null;
    }

    final appId = switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidAppId,
      TargetPlatform.iOS => _iosAppId,
      TargetPlatform.macOS => _iosAppId,
      _ => kIsWeb ? _webAppId : '',
    };
    if (appId.isEmpty) return null;

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: kIsWeb ? '$_projectId.firebaseapp.com' : null,
      iosBundleId: switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => _iosBundleId,
        _ => null,
      },
    );
  }

  static Future<bool> initialize() async {
    final options = _options;
    if (options == null) return false;
    await Firebase.initializeApp(options: options);
    return true;
  }
}
