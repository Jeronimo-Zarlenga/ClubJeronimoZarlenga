import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  final _foregroundMessages = StreamController<RemoteMessage>.broadcast();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  String? _registeredToken;

  Stream<RemoteMessage> get foregroundMessages => _foregroundMessages.stream;

  Future<void> start(ApiService api) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) {
        await api.registerNotificationToken(token);
        _registeredToken = token;
      }
      _tokenSubscription = messaging.onTokenRefresh.listen((freshToken) async {
        try {
          await api.registerNotificationToken(freshToken);
          _registeredToken = freshToken;
        } on ApiException {
          return;
        }
      });
      _messageSubscription = FirebaseMessaging.onMessage.listen(
        _foregroundMessages.add,
      );
    } on FirebaseException {
      return;
    } on ApiException {
      return;
    }
  }

  Future<void> stop(ApiService api) async {
    final token =
        _registeredToken ?? await FirebaseMessaging.instance.getToken();
    if (token != null) {
      try {
        await api.unregisterNotificationToken(token);
      } on ApiException {
        // A revoked or expired session must not block signing out.
      }
    }
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    _tokenSubscription = null;
    _messageSubscription = null;
    _registeredToken = null;
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _foregroundMessages.close();
  }
}
