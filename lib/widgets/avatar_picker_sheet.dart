// Avatar picker — shown from Settings row "Your face".
// 6 preset emojis per user, tapped → written to Firestore via
// FirestoreService.setAvatarEmoji, which avatarEmojiProvider streams.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../providers/avatar_emoji_provider.dart';
import '../services/firestore_service.dart';

class _AvatarOption {
  final String emoji;
  final String label;
  const _AvatarOption(this.emoji, this.label);
}

const _pallavOptions = <_AvatarOption>[
  _AvatarOption('🦁', 'Lion'),
  _AvatarOption('🧔🏽', 'You'),
  _AvatarOption('♟️', 'Strategist'),
  _AvatarOption('🏔️', 'Mountain'),
  _AvatarOption('🔧', 'Engineer'),
  _AvatarOption('⚡', 'Focus'),
];

const _rakhiOptions = <_AvatarOption>[
  _AvatarOption('🌸', 'Cherry'),
  _AvatarOption('🌷', 'Tulip'),
  _AvatarOption('🦋', 'Butterfly'),
  _AvatarOption('🍓', 'Berry'),
  _AvatarOption('🧁', 'Cupcake'),
  _AvatarOption('☕', 'Chai'),
];

Future<void> showAvatarPickerSheet({
  required BuildContext context,
  required UserProfile user,
}) {
  final isRakhi = user.id == 'rakhi';
  final bg = isRakhi ? JarvisTheme.rakhiSurface : JarvisTheme.surface;
  final textPrimary =
      isRakhi ? JarvisTheme.rakhiTextPrimary : JarvisTheme.textPrimary;
  final textSecondary =
      isRakhi ? JarvisTheme.rakhiTextSecondary : JarvisTheme.textSecondary;
  final options = isRakhi ? _rakhiOptions : _pallavOptions;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C000000),
    builder: (ctx) {
      return _AvatarPickerSheet(
        user: user,
        bg: bg,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        options: options,
      );
    },
  );
}

class _AvatarPickerSheet extends ConsumerWidget {
  final UserProfile user;
  final Color bg;
  final Color textPrimary;
  final Color textSecondary;
  final List<_AvatarOption> options;

  const _AvatarPickerSheet({
    required this.user,
    required this.bg,
    required this.textPrimary,
    required this.textSecondary,
    required this.options,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(avatarEmojiProvider(user.id)).valueOrNull;
    final accent = user.accentColor;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: textSecondary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Your face',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 22,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick an emoji — shows up on your top bar',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 14,
              children: options.map((o) {
                final selected = o.emoji == current;
                return GestureDetector(
                  onTap: () async {
                    await FirestoreService().setAvatarEmoji(user.id, o.emoji);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? accent
                              : (bg == JarvisTheme.surface
                                  ? JarvisTheme.surface2
                                  : JarvisTheme.rakhiSurface2),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: accent.withOpacity(0.45),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            o.emoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        o.label,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 10,
                          letterSpacing: 0.5,
                          color: selected ? accent : textSecondary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
