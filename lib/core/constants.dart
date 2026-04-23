// App constants and configuration
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class AppConstants {
  // SharedPreferences keys
  static const String activeUserKey = 'active_user';

  // Firebase collection names
  static const String usersCollection = 'users';
  static const String tasksCollection = 'tasks';
  static const String recurringTasksCollection = 'recurring_tasks';
  static const String thoughtsCollection = 'thoughts';
  static const String goalsCollection = 'goals';
  static const String financeCollection = 'finance';
  static const String mealsCollection = 'meals';
  static const String chatHistoryCollection = 'chat_history';
  static const String remindersCollection = 'reminders';

  // Runtime-loaded env config
  static Map<String, dynamic> _env = {};
  static bool _loaded = false;

  // ── Web-only: compile-time constants injected via
  //    `flutter build web --dart-define-from-file=env.web.json`.
  //    env.web.json intentionally does NOT carry provider API keys —
  //    web builds call Claude/OpenAI through the Firebase Functions
  //    proxy (aiChat / aiTranscribe / aiTTS) so keys never touch the
  //    browser. INGEST_SECRET authenticates those proxy calls;
  //    VAPID_PUBLIC_KEY is the Firebase Cloud Messaging Web Push
  //    certificate so the browser can request push tokens.
  //    Android builds ignore these entirely — loadEnv() reads env.json
  //    from the asset bundle like it always did.
  static const String _webIngestSecret =
      String.fromEnvironment('INGEST_SECRET', defaultValue: '');
  static const String _webVapidPublicKey =
      String.fromEnvironment('VAPID_PUBLIC_KEY', defaultValue: '');

  /// Call once at app startup (in main.dart).
  ///
  /// Android: reads bundled `env.json` asset (unchanged behaviour).
  /// Web: skips the asset load entirely (env.json is swapped to `{}`
  /// by the web-deploy script so nothing sensitive bundles into the JS
  /// anyway — this `kIsWeb` branch is belt-and-suspenders). Values come
  /// from `--dart-define-from-file=env.web.json` via the static const
  /// above; provider keys stay empty and AI calls route through the
  /// proxy Functions.
  static Future<void> loadEnv() async {
    if (_loaded) return;
    if (kIsWeb) {
      _env = {
        'CLAUDE_API_KEY': '',
        'OPENAI_API_KEY': '',
        'TAVILY_API_KEY': '',
        'INGEST_SECRET': _webIngestSecret,
        'VAPID_PUBLIC_KEY': _webVapidPublicKey,
      };
      _loaded = true;
      return;
    }
    try {
      final jsonStr = await rootBundle.loadString('env.json');
      _env = jsonDecode(jsonStr) as Map<String, dynamic>;
      _loaded = true;
    } catch (e) {
      print('Failed to load env.json: $e');
    }
  }

  // API keys (loaded from bundled env.json at runtime on Android;
  // empty on web — see loadEnv above).
  static String get claudeApiKey => _env['CLAUDE_API_KEY'] ?? '';
  static String get openaiApiKey => _env['OPENAI_API_KEY'] ?? '';
  static String get tavilyApiKey => _env['TAVILY_API_KEY'] ?? '';

  /// Auth header for the AI proxy Firebase Functions (web build only).
  /// On Android this is empty and unused — the native path hits
  /// api.anthropic.com / api.openai.com directly.
  static String get ingestSecret => _env['INGEST_SECRET'] ?? '';

  /// Firebase Cloud Messaging Web Push public key (web build only).
  /// On Android this is empty — FCM on Android uses google-services.json.
  /// Generated in Firebase Console → Cloud Messaging → Web Push certs.
  static String get vapidPublicKey => _env['VAPID_PUBLIC_KEY'] ?? '';

  // AI Models
  static const String claudeModel = 'claude-haiku-4-5-20251001';
  static const String whisperModel = 'whisper-1';
  static const String ttsModel = 'tts-1';
  
  // API endpoints (Android / native). These hit providers directly using
  // bundled env.json keys — Pallav's APK path, unchanged.
  static const String claudeApiUrl = 'https://api.anthropic.com/v1/messages';
  static const String openaiApiUrl = 'https://api.openai.com/v1';

  // AI proxy endpoints (Flutter Web / PWA only). Rakhi's web build routes
  // every AI call through these Firebase Functions so provider keys never
  // touch the browser. Auth is the X-Ingest-Secret header. See
  // functions/index.js → aiChat / aiTranscribe / aiTTS.
  static const String _functionsBase =
      'https://us-central1-jarvis-78573.cloudfunctions.net';
  static const String aiChatUrl = '$_functionsBase/aiChat';
  static const String aiTranscribeUrl = '$_functionsBase/aiTranscribe';
  static const String aiTtsUrl = '$_functionsBase/aiTTS';

  /// Test endpoint that fires an FCM push to the caller's user. Used by
  /// the home-screen logo long-press to verify push-token registration.
  static const String testPushUrl = '$_functionsBase/sendTestPush';
  
  // App version
  static const String appVersion = '1.0.0';
  
  // User IDs
  static const String pallavUserId = 'pallav';
  static const String rakhiUserId = 'rakhi';
  
  // Task categories
  static const List<String> taskCategories = [
    'HVAC Sales',
    'Personal',
    'Health',
    'Finance',
    'Travel',
    'Study',
    'Home',
    'Internal',
    'General',
  ];
  
  // Thought categories
  static const List<String> thoughtCategories = [
    'Books',
    'Finance',
    'Personal',
    'Work',
    'Cooking',
    'General',
  ];
  
  // Finance categories (Pallav only)
  static const List<String> financeCategories = [
    'Gold',
    'Stocks',
    'MF',
    'Savings',
  ];
  
  // Meal types (Rakhi only)
  static const List<String> mealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
  ];
  
  // Days of week
  static const List<String> daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  
  // Recurring frequencies
  static const List<String> recurringFrequencies = [
    'daily',
    'weekly',
    'monthly',
  ];
  
  // Priority levels
  static const List<String> priorityLevels = [
    'low',
    'medium',
    'high',
  ];
  
  // Goal statuses
  static const List<String> goalStatuses = [
    'active',
    'paused',
    'done',
  ];
}