import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/jarvis_logo.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'web_permissions_onboarding.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load active user from SharedPreferences — usually <50ms. We used
    // to sleep 1.5s before navigating just to show the logo; removed
    // because on some OEMs the app is killed and relaunched every
    // time the user taps the widget, so that 1.5s was showing up as a
    // "JARVIS banner" on every widget tap. Now the splash shows only
    // as long as auth actually takes.
    await AuthService.loadActiveUser(ref);

    // Web deploy is dedicated to Rakhi's iPhone PWA — skip the user
    // selector and auto-bind her identity. Pallav still sees the
    // regular login flow on his Android APK.
    if (kIsWeb && ref.read(activeUserIdProvider) == null) {
      await AuthService.setActiveUser(AppConstants.rakhiUserId, ref);
    }

    // Navigate based on user state
    final userId = ref.read(activeUserIdProvider);

    if (!mounted) return;

    if (userId != null) {
      // On web, Rakhi's very first launch should be routed through the
      // permissions onboarding screen so she grants notifications + mic
      // + camera up front (iOS Safari only honors each prompt in
      // response to a user gesture, so deferring these to first-use
      // makes the UX feel broken). shouldShow returns false on Android
      // always, and on web after the SharedPreferences flag is set.
      final needsOnboard = await WebPermissionsOnboarding.shouldShow();
      if (!mounted) return;
      if (needsOnboard) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const WebPermissionsOnboarding(),
          ),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const JarvisLogo(fontSize: 40),
            const SizedBox(height: JarvisTheme.md),
            Text(
              'your personal assistant',
              style: JarvisTheme.bodyMedium.copyWith(
                color: JarvisTheme.textMuted,
              ),
            ),
            const SizedBox(height: JarvisTheme.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _animation.value,
                      child: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: JarvisTheme.pallavAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}