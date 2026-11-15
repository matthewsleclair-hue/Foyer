package com.leclair.leclair_home

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Screen off: the picture goes black while the sound keeps playing (music, a podcast,
 * a show to fall asleep to with the sleep timer). It's a black layer over everything,
 * drawn by the remote helper, so it works over any app. On an OLED TV black pixels
 * are truly off. Any button brings the picture back (and does nothing else).
 */
object ScreenOff {
    private const val TAG = "FoyerScreenOff"
    private val handler = Handler(Looper.getMainLooper())
    private var layer: View? = null
    private var hint: View? = null

    val active: Boolean get() = layer != null

    /** Returns false when the remote helper isn't running (the overlay needs it). */
    fun on(c: Context): Boolean {
        val svc = HomeKeyService.instance ?: return false
        if (layer != null) return true
        return try {
            val wm = svc.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val dp = { v: Float -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, svc.resources.displayMetrics) }
            val root = FrameLayout(svc).apply { setBackgroundColor(Color.BLACK) }
            val t = TextView(svc).apply {
                text = Lang.t(svc, "Screen off. The sound keeps playing.\nPress any button to bring the picture back.",
                    "Écran éteint. Le son continue.\nAppuyez sur n'importe quel bouton pour ramener l'image.")
                setTextColor(Color.argb(150, 255, 255, 255))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                gravity = Gravity.CENTER
            }
            root.addView(t, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(48f).toInt() })
            @Suppress("DEPRECATION")
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.OPAQUE
            ).apply { screenBrightness = 0f }
            wm.addView(root, lp)
            layer = root
            hint = t
            // the note fades away so the screen is fully black
            handler.postDelayed({ hint?.animate()?.alpha(0f)?.setDuration(1200)?.start() }, 4000)
            svc.refreshFilter() // so the next button press reaches us
            true
        } catch (e: Exception) {
            Log.d(TAG, "could not black the screen: $e")
            false
        }
    }

    fun off() {
        val v = layer ?: return
        layer = null
        hint = null
        try {
            (HomeKeyService.instance?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.removeView(v)
        } catch (_: Exception) { }
        HomeKeyService.instance?.refreshFilter()
    }

    /** Any button while the screen is off: picture back on. True when the key was used for that. */
    fun onKey(): Boolean {
        if (!active) return false
        handler.post { off() }
        return true
    }
}
