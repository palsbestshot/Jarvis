import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending action from a tapped notification. Set by NotificationService
/// when a push/local notification is tapped (foreground, background, or
/// cold-start); consumed by HomeScreen which switches to the chat tab.
///
/// Per product decision: every notification tap lands on Jarvis chat,
/// regardless of the notification type (task reminder, briefing, chat
/// reply, etc.). The value is always 'chat' for now but the provider
/// is typed String? so we can add action variants later without
/// reshaping the plumbing.
final notificationActionProvider = StateProvider<String?>((ref) => null);
