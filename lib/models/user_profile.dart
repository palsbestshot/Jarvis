import 'package:flutter/material.dart';

class UserProfile {
  final String id; // "pallav" | "rakhi"
  final String name;
  final String accentHex; // "#E8A045" | "#D47BA0"
  final String ttsVoice; // "nova" | "echo"
  final String personalityType;
  final List<String> boardSections;
  // Default emoji for the top-bar avatar. Set via the avatar picker sheet
  // in Settings; the live value is read from Firestore users/{id}.avatar_emoji
  // and overrides this default at runtime (see avatarEmojiProvider).
  final String? avatarEmoji;

  const UserProfile({
    required this.id,
    required this.name,
    required this.accentHex,
    required this.ttsVoice,
    required this.personalityType,
    required this.boardSections,
    this.avatarEmoji,
  });

  Color get accentColor {
    final hex = accentHex.replaceAll('#', '');
    return Color(int.parse('0xFF$hex'));
  }

  // Static configs — no Firestore needed for these
  static final pallav = UserProfile(
    id: 'pallav',
    name: 'Pallav',
    accentHex: '#E8A045',
    ttsVoice: 'nova',
    personalityType: 'direct_coach',
    boardSections: ['Tasks', 'Time', 'Habits', 'Thoughts', 'Finance', 'Goals'],
  );

  static final rakhi = UserProfile(
    id: 'rakhi',
    name: 'Rakhi',
    accentHex: '#D47BA0',
    ttsVoice: 'echo',
    personalityType: 'warm_companion',
    // Sections she asked for (no Time / email — those are Pallav-only via
    // the Claude tool gating in claude_service.dart):
    //   Tasks | Habits | Thoughts | Finance | Goals | Meal Plans
    boardSections: [
      'Tasks',
      'Habits',
      'Thoughts',
      'Finance',
      'Goals',
      'Meal Plans',
    ],
  );

  // Get user by ID
  static UserProfile? fromId(String id) {
    switch (id) {
      case 'pallav':
        return pallav;
      case 'rakhi':
        return rakhi;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'UserProfile(id: $id, name: $name)';
}