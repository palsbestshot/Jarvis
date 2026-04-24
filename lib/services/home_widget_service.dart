// Pushes today's task state into the Android home-screen widget.
//
// The widget is a RemoteViews layout in Android that reads from
// SharedPreferences (home_widget's backing store). We call this service
// from the Board screen whenever tasks change so the widget stays fresh
// without scheduled polling.
//
// Also manages the feedback flash — when Jarvis creates a task/thought,
// we show a 4-second confirmation message on the centre bar, then revert
// to the default "Ask Jarvis…" hint.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

class HomeWidgetService {
  static const String _androidWidgetName = 'TaskWidgetProvider';

  // Keys that the Kotlin TaskWidgetProvider reads.
  static const _kDone = 'tasks_done';
  static const _kTotal = 'tasks_total';
  static const _kDateLabel = 'tasks_date_label';
  static const _kFeedback = 'feedback_message';
  static const _kChatHint = 'widget_chat_hint';
  static const _kMicHint = 'widget_mic_hint';

  static const List<String> _chatHints = [
    'Tap to message…',
    'What would Jarvis do?',
    'Ask me anything, sir.',
    'Running the board quietly…',
  ];

  /// Cached current counts so feedback revert doesn't need to re-query.
  static int _lastDone = 0;
  static int _lastTotal = 0;

  /// Push the latest task state to the widget. Safe to call frequently —
  /// home_widget only repaints when values actually change.
  ///
  /// NEVER throws. The home_widget plugin can throw MissingPluginException
  /// on OEMs that don't fully support app widgets (some Xiaomi/Honor
  /// skins), and bubbling that to the board StreamBuilder crashes the
  /// tab. All exceptions are swallowed with a debug log.
  static Future<void> pushToday({
    required int done,
    required int total,
  }) async {
    _lastDone = done;
    _lastTotal = total;
    try {
      final today = DateFormat('EEE, d MMM').format(DateTime.now());
      final hint = _chatHints[
          DateTime.now().millisecondsSinceEpoch ~/ 60000 % _chatHints.length];
      await HomeWidget.saveWidgetData<int>(_kDone, done);
      await HomeWidget.saveWidgetData<int>(_kTotal, total);
      await HomeWidget.saveWidgetData<String>(_kDateLabel, today);
      await HomeWidget.saveWidgetData<String>(_kChatHint, hint);
      await HomeWidget.saveWidgetData<String>(_kMicHint, '🎙️');
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
    } catch (e) {
      // ignore: avoid_print
      print('HomeWidget pushToday failed (non-fatal): $e');
    }
  }

  /// Derive today's counts from a Firestore snapshot of pending tasks and
  /// push. Call this from a StreamBuilder in the board screen.
  ///
  /// Also never throws — same rationale as pushToday.
  static Future<void> pushFromSnapshot(QuerySnapshot snapshot) async {
    try {
      final today = _istDateKey();
      int done = 0;
      int total = 0;
      for (final doc in snapshot.docs) {
        // Defensive cast — Firestore guarantees Map<String, dynamic> but
        // a rogue doc with unusual shape shouldn't crash the board.
        final data = doc.data();
        if (data is! Map<String, dynamic>) continue;
        final dueDate = (data['due_date'] ?? '').toString();
        if (dueDate != today) continue;
        total++;
        if ((data['status'] ?? '').toString() == 'done') done++;
      }
      await pushToday(done: done, total: total);
    } catch (e) {
      // ignore: avoid_print
      print('HomeWidget pushFromSnapshot failed (non-fatal): $e');
    }
  }

  /// Flash a short confirmation on the widget's centre bar — "Task
  /// created: <title>" etc. — then auto-revert after `duration`.
  /// The bar text is Jarvis's message; the ring + count stay unchanged.
  ///
  /// Swallows all exceptions — the chat flow must not crash if the widget
  /// plugin is unavailable.
  static Future<void> showFeedback(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    try {
      await HomeWidget.saveWidgetData<String>(
        _kFeedback,
        trimmed.length > 90 ? '${trimmed.substring(0, 87)}…' : trimmed,
      );
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
    } catch (e) {
      // ignore: avoid_print
      print('HomeWidget showFeedback failed (non-fatal): $e');
      return;
    }
    // Revert to the default hint after `duration`. Fire-and-forget.
    Future.delayed(duration, () async {
      try {
        await HomeWidget.saveWidgetData<String>(_kFeedback, '');
        await HomeWidget.updateWidget(
          name: _androidWidgetName,
          androidName: _androidWidgetName,
        );
      } catch (_) {/* swallow — nothing to revert on failure */}
    });
  }

  static String _istDateKey() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }
}
