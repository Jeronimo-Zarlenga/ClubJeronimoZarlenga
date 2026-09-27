import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/club_app.dart';
import 'services/firebase_bootstrap.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseConfigured = await FirebaseBootstrap.initialize();
  if (firebaseConfigured) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  runApp(ClubApp(firebaseConfigured: firebaseConfigured));
}
