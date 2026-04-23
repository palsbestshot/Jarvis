import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import './core/theme.dart';
import './core/constants.dart';
import './firebase_options.dart';
import './screens/splash_screen.dart';

// Background message handler for Firebase Cloud Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background message: ${message.messageId}');
}

Future<void> main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set up system UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: JarvisTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Load API keys from bundled env.json
  await AppConstants.loadEnv();

  // Initialize Firebase.
  //  - Android: passing no options lets firebase_core read google-
  //    services.json at runtime, exactly as it always has.
  //  - Web: Firebase.initializeApp() with no options fails in the
  //    browser. Pass DefaultFirebaseOptions.web so Rakhi's PWA finds
  //    the project. Values match web/firebase-messaging-sw.js.
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      await Firebase.initializeApp();
      // FCM background handler is Android-only; on web the service
      // worker at /firebase-messaging-sw.js does the equivalent.
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    print('Firebase initialization error: $e');
    // Continue without Firebase for now
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS v2',
      theme: JarvisTheme.themeData,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}