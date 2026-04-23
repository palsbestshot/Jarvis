import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending widget action — 'chat' or 'voice' — waiting for ChatScreen
/// to pick up. Written by HomeScreen once a jarvis:// URI is drained
/// from the MainActivity queue; cleared by ChatScreen after acting.
///
/// Using a Riverpod StateProvider here (instead of a ValueNotifier
/// passed down the widget tree) sidesteps three fragile patterns that
/// made widget taps silently do nothing:
///   1. The signal being bumped before ChatScreen was listening.
///   2. Signal firing during a build cycle triggering a legal-but-useless
///      state change.
///   3. ChatScreen being rebuilt after a hot-reload and missing the bump.
///
/// With the state provider, ChatScreen reads the current action in build
/// and acts on it; it doesn't care when it was set. Clearing the state
/// to null marks it consumed.
final widgetActionProvider = StateProvider<String?>((ref) => null);
