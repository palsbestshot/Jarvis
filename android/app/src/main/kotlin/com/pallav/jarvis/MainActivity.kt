package com.pallav.jarvis

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Handles widget taps as well as the normal Flutter app lifecycle.
 *
 * When the TaskWidgetProvider fires a PendingIntent with a jarvis://
 * URI, the OS delivers it here (MainActivity is the app's only
 * Activity). Depending on cold-start vs warm-start, the URI arrives
 * via getIntent() or onNewIntent().
 *
 * Delivery to Flutter is PULL-BASED. Every URI goes into a queue.
 * Flutter's HomeScreen, once initialised, calls `consumePendingUri`
 * on a short interval (or once on init) to drain the queue.
 *
 * We deliberately do NOT push URIs to Flutter via invokeMethod. Early
 * in engine startup the MethodChannel exists (because configureFlutterEngine
 * runs before any Dart widget does), but HomeScreen hasn't attached a
 * MethodCallHandler yet — pushes at that moment vanish into the void.
 * Pull-based is the only path that's race-free.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.pallav.jarvis/widget"
    }

    private val pendingUris = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Flutter drains the queue one URI at a time. Call
                // repeatedly until it returns null.
                "consumePendingUri" -> {
                    val uri = pendingUris.firstOrNull()
                    if (uri != null) pendingUris.removeAt(0)
                    result.success(uri)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Launch intent may carry a jarvis:// URI (cold start via
        // widget tap). Queue it for Flutter to pick up.
        captureUri(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Warm start — widget tapped while app was already running.
        // HomeScreen has a short-interval poll (500ms for 4s after
        // resume) that will pick this up within a beat.
        captureUri(intent)
    }

    private fun captureUri(intent: Intent?) {
        val data: Uri? = intent?.data ?: return
        if (data?.scheme != "jarvis") return
        pendingUris.add(data.toString())
    }
}
