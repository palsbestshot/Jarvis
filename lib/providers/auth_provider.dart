import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../core/constants.dart';

// Simple Riverpod StateProvider for active user ID
final activeUserIdProvider = StateProvider<String?>((ref) => null);

// Provider that derives UserProfile from activeUserId
final activeUserProvider = Provider<UserProfile?>((ref) {
  final userId = ref.watch(activeUserIdProvider);
  if (userId == null) return null;
  return UserProfile.fromId(userId);
});

// Provider to load and save user preference
class AuthService {
  static Future<void> loadActiveUser(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(AppConstants.activeUserKey);
    if (userId != null) {
      ref.read(activeUserIdProvider.notifier).state = userId;
    }
  }

  static Future<void> setActiveUser(String userId, WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.activeUserKey, userId);
    ref.read(activeUserIdProvider.notifier).state = userId;
  }

  static Future<void> clearActiveUser(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.activeUserKey);
    ref.read(activeUserIdProvider.notifier).state = null;
  }
}