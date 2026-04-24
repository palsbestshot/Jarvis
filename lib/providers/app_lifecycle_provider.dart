import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current app lifecycle state, mirrored from HomeScreen's
/// WidgetsBindingObserver so any provider can ask "is the app in the
/// foreground?" without wiring its own observer. Written by HomeScreen
/// on every didChangeAppLifecycleState; read by chat_provider to decide
/// whether to fire a local notification for an incoming assistant reply.
final appLifecycleProvider =
    StateProvider<AppLifecycleState>((ref) => AppLifecycleState.resumed);
