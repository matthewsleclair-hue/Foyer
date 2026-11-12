package com.leclair.leclair_home

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * Small notes in the top corner over whatever is playing (score alerts).
 * Drawn by the remote helper, which may draw over other apps; without it, a plain toast.
 */
object Alerts {
    private val handler = Handler(Looper.getMainLooper())
    private var view: View? = null
    private val hide = Runnable { remove() }

    /** size: 0 small, 1 medium, 2 large. */
    fun show(c: Context, title: String, line: String, seconds: Int = 8, size: Int = 2) {
        handler.post {
            val svc = HomeKeyService.instance
            if (svc == null) {
                try { Toast.makeText(c.applicationContext, "$title\n$line", Toast.LENGTH_LONG).show() } catch (e: Exception) { }
                return@post
            }
            remove()
            try {
                val k = when (size) { 0 -> 0.75f; 1 -> 1f; else -> 1.4f }
                val dp = { v: Float -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v * k, svc.resources.displayMetrics) }
                val box = LinearLayout(svc).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(22f).toInt(), dp(14f).toInt(), dp(26f).toInt(), dp(16f).toInt())
                    background = GradientDrawable().apply {
                        cornerRadius = dp(22f)
                        setColor(Color.argb(232, 18, 20, 30))
                        setStroke(dp(1.5f).toInt(), Color.argb(110, 255, 255, 255))
                    }
                }
                box.addView(TextView(svc).apply {
                    text = title
                    setTextColor(Color.rgb(255, 212, 59))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f * k)
                    typeface = Typeface.DEFAULT_BOLD
                })
                box.addView(TextView(svc).apply {
                    text = line
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 21f * k)
                    typeface = Typeface.DEFAULT_BOLD
                })
                val lp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.END
                    x = dp(36f).toInt()
                    y = dp(30f).toInt()
                    windowAnimations = android.R.style.Animation_Toast
                }
                (svc.getSystemService(Context.WINDOW_SERVICE) as WindowManager).addView(box, lp)
                view = box
                handler.removeCallbacks(hide)
                handler.postDelayed(hide, seconds * 1000L)
            } catch (e: Exception) { }
        }
    }

    private fun remove() {
        val v = view ?: return
        view = null
        try {
            (HomeKeyService.instance?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.removeView(v)
        } catch (e: Exception) { }
    }
}
