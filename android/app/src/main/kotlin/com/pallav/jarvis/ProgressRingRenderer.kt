package com.pallav.jarvis

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF

/**
 * Paints a task-completion ring as a Bitmap for the home-screen widget.
 * Background ring is dim, the completed arc uses the user's accent.
 */
object ProgressRingRenderer {

    private const val BG_COLOR = 0xFF181512.toInt()
    private const val ACCENT_COLOR = 0xFFE8A045.toInt()

    fun render(done: Int, total: Int, sizePx: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val strokeWidth = (sizePx * 0.09f).coerceAtLeast(4f)
        val pad = strokeWidth / 2f
        val rect = RectF(pad, pad, sizePx - pad, sizePx - pad)

        // Background ring — full circle in muted colour
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = BG_COLOR
            style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawArc(rect, 0f, 360f, false, bgPaint)

        if (total > 0 && done > 0) {
            val progress = (done.toFloat() / total.toFloat()).coerceIn(0f, 1f)
            val sweep = 360f * progress
            val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = ACCENT_COLOR
                style = Paint.Style.STROKE
                this.strokeWidth = strokeWidth
                strokeCap = Paint.Cap.ROUND
            }
            canvas.drawArc(rect, -90f, sweep, false, accentPaint)
        }

        return bitmap
    }
}
