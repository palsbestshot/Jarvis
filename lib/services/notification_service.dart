import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../core/constants.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late FlutterLocalNotificationsPlugin _localNotifications;
  StreamSubscription? _tokenRefreshSubscription;
  StreamSubscription? _taskSubscription;
  String? _currentUserId;
  static bool _tzInitialized = false;

  NotificationService() {
    _localNotifications = FlutterLocalNotificationsPlugin();
    // Local notifications (flutter_local_notifications) are Android-only
    // — the web plugin is a stub that throws MissingPluginException on
    // most methods. On web, Rakhi's reminders arrive via FCM web push
    // (wired in Phase 6) instead. Skip init entirely for web.
    if (!kIsWeb) {
      _initializeLocalNotifications();
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Initialize timezone
    if (!_tzInitialized) {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      _tzInitialized = true;
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap({'payload': response.payload});
      },
    );

    // Create notification channels
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'jarvis_channel',
          'JARVIS Notifications',
          description: 'Reminders and briefings from JARVIS',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'jarvis_tasks',
          'Task Reminders',
          description: 'Reminders for upcoming and overdue tasks',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      // Request exact alarm permission (Android 12+)
      await androidPlugin.requestExactAlarmsPermission();
      await androidPlugin.requestNotificationsPermission();
    }
  }

  Future<void> initialize(String userId) async {
    _currentUserId = userId;

    // Set foreground notification presentation options
    await FirebaseMessaging.instance
      .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

    // Request notification permission for Android 13+
    NotificationSettings settings = await FirebaseMessaging.instance
      .requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

    print('DEBUG Notification permission: ${settings.authorizationStatus}');

    // Get FCM token. Native builds use the default projects FCM/google-
    // services config; web builds must pass the VAPID public key so the
    // browser can subscribe to Firebase push. The two tokens live in
    // different Firestore docs (`primary` for Android, `web` for the
    // PWA) so both platforms can coexist for the same user without
    // overwriting each other.
    try {
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken(
              vapidKey: AppConstants.vapidPublicKey,
            )
          : await FirebaseMessaging.instance.getToken();
      if (token != null) {
        final docId = kIsWeb ? 'web' : 'primary';
        final platform = kIsWeb ? 'web' : 'android';
        await FirebaseFirestore.instance
            .collection('users/$userId/device_tokens')
            .doc(docId)
            .set({
              'fcm_token': token,
              'updated_at': FieldValue.serverTimestamp(),
              'platform': platform,
            });
      } else if (kIsWeb) {
        // Most common cause: VAPID key not set, or user denied
        // notification permission (Safari). Surface to console so
        // devtools shows why the iPhone isn't getting pushes.
        print(
          'DEBUG Web FCM token null — check VAPID_PUBLIC_KEY in env.web.json '
          'and notification permission grant',
        );
      }
    } catch (e) {
      print('DEBUG FCM token save error: $e');
    }

    // Listen for token refresh
    _tokenRefreshSubscription = _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _saveFCMToken(userId, newToken);
    });

    // Foreground handler + local task reminder scheduling both depend
    // on flutter_local_notifications, which is Android-only. On web the
    // browser + service worker render FCM pushes directly, and task
    // reminders (Phase 6) will arrive via scheduled Cloud Functions
    // instead of client-side zonedSchedule.
    if (!kIsWeb) {
      // Configure foreground message handler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        if (notification != null && android != null) {
          await _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'jarvis_channel',
                'JARVIS Notifications',
                channelDescription: 'Reminders and briefings from JARVIS',
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
            ),
          );
        }
      });

      // Start listening for tasks and scheduling reminders
      _listenForTasks(userId);
    }

    // Configure onMessageOpenedApp handler (works on web + Android)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data);
    });
  }

  // ─── Local Task Reminders ──────────────────────────────────────────────────

  void _listenForTasks(String userId) {
    _taskSubscription?.cancel();

    // Listen to pending tasks in real-time
    _taskSubscription = _firestore
        .collection('users/$userId/tasks')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      _scheduleTaskReminders(snapshot.docs);
    });
  }

  Future<void> _scheduleTaskReminders(List<QueryDocumentSnapshot> taskDocs) async {
    // Cancel all existing task reminders (IDs 10000-19999)
    for (int i = 10000; i < 10000 + 100; i++) {
      await _localNotifications.cancel(i);
    }

    int notificationId = 10000;
    final now = tz.TZDateTime.now(tz.local);

    for (final doc in taskDocs) {
      if (notificationId >= 10100) break; // Max 100 scheduled reminders

      final data = doc.data() as Map<String, dynamic>;
      final title = data['title'] as String? ?? 'Task';
      final priority = data['priority'] as String? ?? 'medium';
      final dueDateStr = data['due_date'] as String?;
      final dueTimeStr = data['due_time'] as String?;
      final howToClose = data['how_to_close'] as String?;

      // Parse due date + time
      DateTime? dueDate;

      // First try due_time (has both date and time)
      if (dueTimeStr != null && dueTimeStr.isNotEmpty) {
        try {
          dueDate = DateTime.parse(dueTimeStr);
        } catch (_) {}
      }

      // Fall back to due_date string (YYYY-MM-DD → default to 9 AM)
      if (dueDate == null && dueDateStr != null && dueDateStr.isNotEmpty) {
        try {
          final dateParts = dueDateStr.split('-');
          if (dateParts.length == 3) {
            dueDate = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              9, 0, // Default to 9:00 AM
            );
          } else {
            dueDate = DateTime.parse(dueDateStr);
          }
        } catch (_) {}
      }

      // Also check Firestore Timestamp format
      if (dueDate == null && data['due_date'] is Timestamp) {
        dueDate = (data['due_date'] as Timestamp).toDate();
      }

      if (dueDate == null) continue;

      final tzDueDate = tz.TZDateTime.from(dueDate, tz.local);
      print('DEBUG: Scheduling for task "$title" at $tzDueDate (now=$now)');

      // Schedule reminder based on priority
      // High: 1 hour before + at due time
      // Medium: at due time
      // Low: at due time
      final body = howToClose != null && howToClose.isNotEmpty
          ? 'How to close: $howToClose'
          : 'Task is due now. Tap to view.';

      if (priority == 'high') {
        // 1 hour before
        final earlyReminder = tzDueDate.subtract(const Duration(hours: 1));
        if (earlyReminder.isAfter(now)) {
          await _scheduleNotification(
            id: notificationId++,
            title: '⚡ Upcoming: $title',
            body: 'Due in 1 hour. $body',
            scheduledDate: earlyReminder,
          );
        }
      }

      // At due time
      if (tzDueDate.isAfter(now)) {
        await _scheduleNotification(
          id: notificationId++,
          title: priority == 'high' ? '🔴 Due now: $title' : '📋 Due now: $title',
          body: body,
          scheduledDate: tzDueDate,
        );
      }

      // 30 min after due (overdue nudge) for high/medium
      if (priority != 'low') {
        final overdueReminder = tzDueDate.add(const Duration(minutes: 30));
        if (overdueReminder.isAfter(now)) {
          await _scheduleNotification(
            id: notificationId++,
            title: '⏰ Overdue: $title',
            body: 'This task is past due. $body',
            scheduledDate: overdueReminder,
          );
        }
      }
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
  }) async {
    try {
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jarvis_tasks',
            'Task Reminders',
            channelDescription: 'Reminders for upcoming and overdue tasks',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
      );
    } catch (e) {
      print('Failed to schedule notification $id: $e');
    }
  }

  /// Schedule a test notification N minutes from now
  Future<void> scheduleTestNotification({int minutesFromNow = 2}) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutesFromNow));

    await _scheduleNotification(
      id: 99999,
      title: '✅ JARVIS Test Notification',
      body: 'Notifications are working! Scheduled $minutesFromNow min ago.',
      scheduledDate: scheduledDate,
    );

    print('DEBUG: Test notification scheduled for $scheduledDate');
  }

  /// Show an immediate notification (for testing)
  Future<void> showTestNotification() async {
    await _localNotifications.show(
      99998,
      '✅ JARVIS Instant Test',
      'Local notifications are working!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'jarvis_tasks',
          'Task Reminders',
          channelDescription: 'Reminders for upcoming and overdue tasks',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  // ─── Utility ───────────────────────────────────────────────────────────────

  Future<void> _saveFCMToken(String userId, [String? token]) async {
    try {
      final fcmToken = token ??
          (kIsWeb
              ? await _firebaseMessaging.getToken(
                  vapidKey: AppConstants.vapidPublicKey,
                )
              : await _firebaseMessaging.getToken());
      if (fcmToken == null) return;

      if (kIsWeb) {
        // Web token goes into a dedicated `web` doc so Pallav's Android
        // primary token in the same collection isn't overwritten if he
        // ever previews Rakhi's PWA on his laptop.
        await _firestore
            .doc('users/$userId/device_tokens/web')
            .set({
              'fcm_token': fcmToken,
              'updated_at': FieldValue.serverTimestamp(),
              'platform': 'web',
            });
        return;
      }

      // Android legacy path — byte-identical to the previous behaviour:
      // use the token string itself as the doc ID. sendFCMToUser picks
      // the newest doc by updated_at, so stale entries never send.
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('device_tokens')
          .doc(fcmToken)
          .set({
            'fcm_token': fcmToken,
            'updated_at': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'];
    print('Notification tapped with type: $type');
  }

  Future<void> dispose() async {
    _tokenRefreshSubscription?.cancel();
    _taskSubscription?.cancel();
  }
}
