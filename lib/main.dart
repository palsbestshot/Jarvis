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

  // Set up system UI. Colours pulled from JarvisTheme getters so the
  // light-pink web palette and the dark Android palette both Just Work.
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
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
      debugShowCheckedModeBanner: false,
      // On web (Rakhi's iPhone PWA) scale every text size up so it's
      // comfortably legible on a 375pt Safari viewport. Android stays
      // at 1.0. Wrap the whole app via builder so every screen's text,
      // including Material-default widgets, picks up the scale.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(JarvisTheme.rootTextScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}