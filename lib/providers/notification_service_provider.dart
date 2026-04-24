import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

/// App-wide NotificationService singleton. Holds the FCM + local
/// notifications plumbing. Previously instantiated directly in
/// HomeScreen.initState, which meant other providers (chat_provider)
/// had no way to reach it — moving to a provider lets chat_provider
/// fire a local notification when a reply lands while the app is
/// backgrounded.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(ref: ref);
  ref.onDispose(() => service.dispose());
  return service;
});
