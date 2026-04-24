// Streams users/{userId}.avatar_emoji from Firestore so every surface
// that shows the profile pill (Home top bar, Finance header, Settings
// row, task sheet delegate avatar) stays in sync after the picker
// updates it.
//
// Emits null when the field isn't set yet — callers fall back to the
// user's initial letter in that case.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';

final _firestoreProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

final avatarEmojiProvider =
    StreamProvider.family<String?, String>((ref, userId) {
  final svc = ref.watch(_firestoreProvider);
  return svc.avatarEmojiStream(userId);
});
