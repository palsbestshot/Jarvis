// Deprecated — Agent mode moved to chat screen
// This file is kept for reference but is no longer used in the app
// Agent functionality is now integrated into the chat screen via mode switcher

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(activeUserProvider);
    final accentColor = user?.accentColor ?? JarvisTheme.pallavAccent;

    return Scaffold(
      backgroundColor: JarvisTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 64,
              color: accentColor,
            ),
            const SizedBox(height: JarvisTheme.lg),
            Text(
              'Agent coming in Phase 2',
              style: JarvisTheme.headingLarge.copyWith(
                color: accentColor,
              ),
            ),
            const SizedBox(height: JarvisTheme.md),
            Text(
              'AI agent for automation and smart assistance',
              style: JarvisTheme.bodyMedium.copyWith(
                color: JarvisTheme.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: JarvisTheme.lg),
            Container(
              padding: const EdgeInsets.all(JarvisTheme.lg),
              decoration: BoxDecoration(
                color: JarvisTheme.surface,
                borderRadius: BorderRadius.circular(JarvisTheme.medium),
              ),
              child: Column(
                children: [
                  Text(
                    'Agent capabilities:',
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: JarvisTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: JarvisTheme.md),
                  _buildCapability('Task automation', accentColor),
                  _buildCapability('Smart reminders', accentColor),
                  _buildCapability('Voice commands', accentColor),
                  _buildCapability('Context awareness', accentColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapability(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JarvisTheme.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: color,
          ),
          const SizedBox(width: JarvisTheme.sm),
          Text(
            text,
            style: JarvisTheme.bodyMedium.copyWith(
              color: JarvisTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}