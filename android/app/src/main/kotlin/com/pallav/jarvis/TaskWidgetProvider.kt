package com.pallav.jarvis

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import android.util.TypedValue
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home-screen widget for Jarvis — a circle with completion ring + count,
 * a tap-to-chat text bar in the middle, and a mic icon on the right.
 *
 * EVERY operation is wrapped in try/catch. The widget lifecycle runs
 * in the main app process; an uncaught exception here was crashing
 * the whole app (reported: "app crashes once widget is there, works
 * fine once widget is deleted"). Never propagate throwables.
 *
 * PendingIntents are built manually here — we do NOT use home_widget's
 * HomeWidgetLaunchIntent helper. Reasons:
 *   - Full control over FLAG_IMMUTABLE + unique requestCode per target
 *     (Android de-dupes PendingIntents with the same requestCode,
 *     which was making only one of the three taps fire).
 *   - No dependency on a plugin whose version we don't pin tightly.
 *   - MainActivity handles the resulting intent directly via its own
 *     jarvis:// intent filter and forwards the URI to Flutter through
 *     a MethodChannel (see MainActivity.kt).
 */
class TaskWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "TaskWidgetProvider"
        // Unique requestCode per tap target. Android's PendingIntent
        // system treats two PendingIntents with the same (context,
        // requestCode, intent-filter-data) as identical. If we passed
        // 0 for all three, only one would ever fire.
        private const val REQ_RING = 101
        private const val REQ_CHAT_BAR = 102
        private const val REQ_MIC = 103
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // Outer safety net — anything that escapes from inside is
        // logged and swallowed. Never let a widget bug crash the app.
        try {
            renderAll(context, appWidgetManager, appWidgetIds)
        } catch (t: Throwable) {
            Log.e(TAG, "onUpdate failed", t)
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        // Catch ALL inbound intents — including any background or
        // system-scheduled ones — so even a malformed broadcast can't
        // crash us.
        try {
            super.onReceive(context, intent)
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive failed for action=${intent?.action}", t)
        }
    }

    private fun renderAll(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // ── 1. Read data ─────────────────────────────────────────
        var done = 0
        var total = 0
        var feedback: String? = null
        try {
            val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)
            done = prefs.getInt("tasks_done", 0)
            total = prefs.getInt("tasks_total", 0)
            feedback = prefs.getString("feedback_message", null)
                ?.takeIf { it.isNotBlank() }
        } catch (t: Throwable) {
            Log.w(TAG, "HomeWidgetPlugin.getData threw; using defaults", t)
        }

        // ── 2. Render the ring bitmap ────────────────────────────
        val ringSizePx = dpToPx(context, 60f)
        val ringBitmap = try {
            ProgressRingRenderer.render(done, total, ringSizePx)
        } catch (t: Throwable) {
            Log.e(TAG, "Ring render failed", t)
            null
        }

        // ── 3. Choose bar text ───────────────────────────────────
        // If we have a fresh "feedback_message" (set by the chat
        // after creating a task/thought), show that — else the
        // default nudge.
        val barText = feedback ?: "Ask Jarvis or add a task…"
        val barTextColor =
            if (feedback != null) 0xFFF5F0E8.toInt()
            else 0xFFA89880.toInt()

        // ── 4. Apply to each widget instance ─────────────────────
        for (widgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.task_widget)
                if (ringBitmap != null) {
                    views.setImageViewBitmap(R.id.widget_ring, ringBitmap)
                }
                views.setTextViewText(R.id.widget_count_done, done.toString())
                views.setTextViewText(R.id.widget_count_total, "of $total")
                views.setTextViewText(R.id.widget_chat_bar, barText)
                views.setTextColor(R.id.widget_chat_bar, barTextColor)

                // Three distinct tap targets. Unique requestCodes are
                // critical — see companion object comment.
                // Ring tap → jump directly to the tasks/board tab,
                // not just open the app. User explicitly wanted the
                // progress ring to feel like a shortcut to their task
                // list, since that's what the ring visualises.
                views.setOnClickPendingIntent(
                    R.id.widget_ring_container,
                    buildLaunchIntent(context, REQ_RING, "jarvis://tasks")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_chat_bar,
                    buildLaunchIntent(context, REQ_CHAT_BAR, "jarvis://chat")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_mic_button,
                    buildLaunchIntent(context, REQ_MIC, "jarvis://voice")
                )

                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (t: Throwable) {
                Log.e(TAG, "Widget render failed for id=$widgetId", t)
            }
        }
    }

    /**
     * Build a PendingIntent that launches MainActivity, optionally
     * with a jarvis:// deep-link URI. FLAG_IMMUTABLE is required on
     * Android 12+ (S, API 31+); without it, the system silently
     * drops the PendingIntent — making the widget look static
     * ("only looks like image").
     */
    private fun buildLaunchIntent(
        context: Context,
        requestCode: Int,
        uri: String?
    ): PendingIntent {
        // FLAG_ACTIVITY_NEW_TASK is required when starting an Activity
        // from a non-Activity context (like an AppWidgetProvider).
        // FLAG_ACTIVITY_SINGLE_TOP cooperates with launchMode="singleTask"
        // on MainActivity so a warm tap calls onNewIntent on the existing
        // instance rather than creating a new one — no splash flash,
        // no "JARVIS banner" reappearing on every widget tap.
        // We deliberately DO NOT use FLAG_ACTIVITY_CLEAR_TOP: that flag
        // destroys the existing MainActivity and forces a fresh onCreate,
        // which was causing the jarring re-launch animation the user
        // complained about.
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            if (uri != null) {
                action = Intent.ACTION_VIEW
                data = Uri.parse(uri)
            }
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun dpToPx(context: Context, dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            context.resources.displayMetrics
        ).toInt()
    }
}
