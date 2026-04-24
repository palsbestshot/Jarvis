import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../providers/avatar_emoji_provider.dart';

class UserAvatar extends ConsumerWidget {
  final UserProfile user;
  final double size;
  final bool showRing;

  const UserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.showRing = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = ref.watch(avatarEmojiProvider(user.id)).valueOrNull;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: user.accentColor.withOpacity(0.2),
        border: showRing
            ? Border.all(
                color: user.accentColor,
                width: 2,
              )
            : null,
      ),
      child: Center(
        child: emoji != null
            ? Text(
                emoji,
                style: TextStyle(fontSize: size * 0.55),
              )
            : Text(
                user.name[0].toUpperCase(),
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: size * 0.5,
                  fontWeight: FontWeight.w400,
                  color: user.accentColor,
                ),
              ),
      ),
    );
  }
}
