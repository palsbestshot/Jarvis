// WebPermissionsOnboarding — first-launch permission gate on the Web
// build. Shows Rakhi three clear "Allow" buttons for notifications,
// microphone, and camera. Each tap triggers the native browser prompt
// (iOS Safari honors these only in response to a user gesture). After
// she's responded to each, the "Continue" button moves her to the
// home screen and a SharedPreferences flag is set so this screen
// never shows again.
//
// Design rules:
//   - Never block Rakhi. If she denies something, the button shows
//     "Denied — settings only" but Continue is still enabled.
//   - Don't loop. If the screen has been seen even once (flag set),
//     skip it entirely on subsequent launches — iOS Safari handles
//     re-prompting through its own Settings UI.
//   - Don't ship to Android. Splash screen gates this route behind
//     kIsWeb; the file is safe to import either way (the platform-
//     specific mic/camera bits are in web_permissions.dart via a
//     conditional import).

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../services/notification_service.dart';
import '../services/web_permissions.dart';
import '../widgets/jarvis_logo.dart';
import 'home_screen.dart';

/// SharedPreferences key for "Rakhi has seen the onboarding once". We
/// don't track per-user — the web build is single-user (Rakhi) by
/// design.
const String kWebOnboardPrefKey = 'web_permissions_onboarded_v1';

enum _PermState { idle, requesting, granted, denied }

class WebPermissionsOnboarding extends ConsumerStatefulWidget {
  const WebPermissionsOnboarding({super.key});

  /// True if we should route the user through this screen on this
  /// launch. Returns false on native (splash skips the route anyway),
  /// false if already seen, and true if FCM authorization is still
  /// notDetermined (fresh install). If notifications are already
  /// granted or denied but flag isn't set, we still show it once so
  /// Rakhi can tap mic + camera too.
  static Future<bool> shouldShow() async {
    if (!kIsWeb) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(kWebOnboardPrefKey) == true) return false;
      return true;
    } catch (_) {
      // SharedPreferences failure shouldn't block launch.
      return false;
    }
  }

  @override
  ConsumerState<WebPermissionsOnboarding> createState() =>
      _WebPermissionsOnboardingState();
}

class _WebPermissionsOnboardingState
    extends ConsumerState<WebPermissionsOnboarding> {
  _PermState _notif = _PermState.idle;
  _PermState _mic = _PermState.idle;
  _PermState _camera = _PermState.idle;

  Future<void> _requestNotifications() async {
    setState(() => _notif = _PermState.requesting);
    try {
      final settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final ok =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      setState(() => _notif = ok ? _PermState.granted : _PermState.denied);

      // If granted, also kick off the FCM token save so subsequent
      // sends reach her iPhone without a second initialize round.
      if (ok) {
        final userId = ref.read(activeUserIdProvider);
        if (userId != null) {
          // Fire-and-forget; NotificationService handles token save +
          // Firestore write + token refresh listener registration.
          NotificationService().initialize(userId);
        }
      }
    } catch (_) {
      setState(() => _notif = _PermState.denied);
    }
  }

  Future<void> _requestMic() async {
    setState(() => _mic = _PermState.requesting);
    final ok = await requestMicrophoneWeb();
    if (!mounted) return;
    setState(() => _mic = ok ? _PermState.granted : _PermState.denied);
  }

  Future<void> _requestCamera() async {
    setState(() => _camera = _PermState.requesting);
    final ok = await requestCameraWeb();
    if (!mounted) return;
    setState(() => _camera = ok ? _PermState.granted : _PermState.denied);
  }

  Future<void> _continue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kWebOnboardPrefKey, true);
    } catch (_) {/* non-fatal — worst case she sees this screen again */}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = JarvisTheme.rakhiAccent;
    return Scaffold(
      backgroundColor: JarvisTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(JarvisTheme.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: JarvisTheme.md),
                  const Center(child: JarvisLogo(fontSize: 44)),
                  const SizedBox(height: JarvisTheme.sm),
                  Text(
                    'Welcome, Rakhi',
                    textAlign: TextAlign.center,
                    style: JarvisTheme.headingLarge,
                  ),
                  const SizedBox(height: JarvisTheme.xs),
                  Text(
                    "Grant these three permissions so Jarvis can buzz you "
                    "with reminders and you can talk / snap photos without "
                    "fighting the browser later.",
                    textAlign: TextAlign.center,
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: JarvisTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: JarvisTheme.lg),
                  _permCard(
                    accent: accent,
                    icon: Icons.notifications_active,
                    title: 'Notifications',
                    subtitle:
                        'Morning meal nudge, task reminders. Arrives on the home screen even when the app is closed.',
                    state: _notif,
                    onAllow: _requestNotifications,
                  ),
                  const SizedBox(height: JarvisTheme.md),
                  _permCard(
                    accent: accent,
                    icon: Icons.mic,
                    title: 'Microphone',
                    subtitle:
                        'Tap the mic in chat and speak — Jarvis transcribes your Hinglish and replies. Hands-free cooking.',
                    state: _mic,
                    onAllow: _requestMic,
                  ),
                  const SizedBox(height: JarvisTheme.md),
                  _permCard(
                    accent: accent,
                    icon: Icons.camera_alt,
                    title: 'Camera',
                    subtitle:
                        'Snap a photo of today\'s meal, a grocery receipt, or the fridge — Jarvis understands pictures too.',
                    state: _camera,
                    onAllow: _requestCamera,
                  ),
                  const SizedBox(height: JarvisTheme.xl),
                  ElevatedButton(
                    onPressed: _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(JarvisTheme.small),
                      ),
                    ),
                    child: Text(
                      _anyGranted
                          ? 'Continue to Jarvis'
                          : 'Skip for now',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: JarvisTheme.sm),
                  TextButton(
                    onPressed: _continue,
                    child: Text(
                      "I'll decide later in Settings",
                      style: TextStyle(color: JarvisTheme.textMuted),
                    ),
                  ),
                  const SizedBox(height: JarvisTheme.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _anyGranted =>
      _notif == _PermState.granted ||
      _mic == _PermState.granted ||
      _camera == _PermState.granted;

  Widget _permCard({
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required _PermState state,
    required VoidCallback onAllow,
  }) {
    Widget trailing;
    switch (state) {
      case _PermState.requesting:
        trailing = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        );
        break;
      case _PermState.granted:
        trailing = Icon(Icons.check_circle, color: accent);
        break;
      case _PermState.denied:
        trailing = Icon(Icons.cancel_outlined, color: JarvisTheme.textMuted);
        break;
      case _PermState.idle:
        trailing = TextButton(
          onPressed: onAllow,
          style: TextButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withOpacity(0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JarvisTheme.small),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('Allow'),
          ),
        );
    }
    return Container(
      padding: const EdgeInsets.all(JarvisTheme.md),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(JarvisTheme.medium),
        border: Border.all(
          color: state == _PermState.granted
              ? accent.withOpacity(0.6)
              : JarvisTheme.surface2,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(JarvisTheme.small),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: JarvisTheme.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: JarvisTheme.bodyLarge.copyWith(
                      color: JarvisTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(
                  state == _PermState.denied
                      ? '$subtitle\n(Denied — change in Safari Settings → Jarvis.)'
                      : subtitle,
                  style: JarvisTheme.bodySmall.copyWith(
                    color: JarvisTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: JarvisTheme.sm),
          trailing,
        ],
      ),
    );
  }
}
