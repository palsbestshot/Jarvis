import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../widgets/jarvis_logo.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: JarvisTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(JarvisTheme.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: JarvisTheme.xxl),
              const JarvisLogo(fontSize: 40),
              const SizedBox(height: JarvisTheme.sm),
              Text(
                'your personal assistant',
                style: JarvisTheme.bodyMedium.copyWith(
                  color: JarvisTheme.textMuted,
                ),
              ),
              const SizedBox(height: 60),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    return isNarrow
                        ? _buildVerticalLayout()
                        : _buildHorizontalLayout();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalLayout() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildUserCard(UserProfile.pallav),
        const SizedBox(width: JarvisTheme.xl),
        _buildUserCard(UserProfile.rakhi),
      ],
    );
  }

  Widget _buildVerticalLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildUserCard(UserProfile.pallav),
        const SizedBox(height: JarvisTheme.xl),
        _buildUserCard(UserProfile.rakhi),
      ],
    );
  }

  Widget _buildUserCard(UserProfile user) {
    return Consumer(
      builder: (context, ref, child) {
        return GestureDetector(
          onTap: () async {
            await AuthService.setActiveUser(user.id, ref);
            if (context.mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            }
          },
          child: Container(
            width: 160,
            height: 200,
            decoration: BoxDecoration(
              color: JarvisTheme.surface,
              borderRadius: BorderRadius.circular(JarvisTheme.medium),
              border: Border.all(
                color: user.accentColor.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  user.name[0].toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 48,
                    color: user.accentColor,
                  ),
                ),
                const SizedBox(height: JarvisTheme.md),
                Text(
                  user.name,
                  style: JarvisTheme.headingMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}