package com.leclair.leclair_home

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import android.widget.Toast

/**
 * Sleep timer: puts the TV to sleep after a while, even while another app is playing.
 * A minute before, a small note shows over whatever is on screen; any button keeps
 * watching. The remote helper keeps Foyer running in the background, so a plain
 * Handler is enough (and needs no exact-alarm permission).
 */
object SleepTimer {
    private const val TAG = "FoyerSleep"
    private const val KEY = "sleepAt"
    private val handler = Handler(Looper.getMainLooper())
    private var app: Context? = null
    private var overlay: View? = null

    /** When the TV goes to sleep (ms since 1970), or 0 when the timer is off. */
    @Volatile var endAt = 0L
        private set

    /** True while the "going to sleep in a minute" note is on screen. */
    val warning: Boolean get() = overlay != null

    private val warn = Runnable { showWarning() }
    private val fire = Runnable { sleepNow() }

    private fun prefs(c: Context) = c.getSharedPreferences("leclair_home", Context.MODE_PRIVATE)

    /** Picks up a timer that was running before Foyer restarted. */
    fun restore(c: Context) {
        app = c.applicationContext
        val at = prefs(c).getLong(KEY, 0L)
        if (at > System.currentTimeMillis() + 5000 && endAt == 0L) schedule(c, at)
        else if (at != 0L && at <= System.currentTimeMillis()) prefs(c).edit().remove(KEY).apply()
    }

    /** Starts (or replaces) the timer. 0 minutes turns it off. */
    fun start(c: Context, minutes: Int) {
        app = c.applicationContext
        if (minutes <= 0) return cancel(c)
        schedule(c, System.currentTimeMillis() + minutes * 60_000L)
    }

    /** For a remote button: off -> 30 min, on -> 30 more (up to 3 hours). */
    fun bump(c: Context) {
        val now = System.currentTimeMillis()
        val left = if (endAt > now) endAt - now else 0L
        val next = ((left + 30 * 60_000L).coerceAtMost(180 * 60_000L))
        schedule(c, now + next)
        toast(c, "Sleep timer: ${(next / 60_000L)} minutes")
    }

    fun cancel(c: Context) {
        handler.removeCallbacks(warn)
        handler.removeCallbacks(fire)
        endAt = 0L
        prefs(c).edit().remove(KEY).apply()
        hideWarning()
    }

    private fun schedule(c: Context, at: Long) {
        app = c.applicationContext
        handler.removeCallbacks(warn)
        handler.removeCallbacks(fire)
        hideWarning()
        endAt = at
        prefs(c).edit().putLong(KEY, at).apply()
        val left = at - System.currentTimeMillis()
        if (left > 70_000L) handler.postDelayed(warn, left - 60_000L) else handler.post(warn)
        handler.postDelayed(fire, left.coerceAtLeast(0L))
        Log.d(TAG, "sleep in ${left / 1000}s")
    }

    /** Any button while the note is up: keep watching. Returns true when the key was used for that. */
    fun onKey(c: Context): Boolean {
        if (!warning) return false
        cancel(c)
        toast(c, "Sleep timer off. Enjoy the show.")
        HomeKeyService.instance?.refreshFilter()
        return true
    }

    private fun showWarning() {
        val svc = HomeKeyService.instance ?: return
        if (overlay != null) return
        try {
            val wm = svc.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val dp = { v: Float -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, svc.resources.displayMetrics) }
            val t = TextView(svc).apply {
                text = "Going to sleep in 1 minute\nPress any button to keep watching"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                gravity = Gravity.CENTER
                setPadding(dp(28f).toInt(), dp(18f).toInt(), dp(28f).toInt(), dp(18f).toInt())
                background = GradientDrawable().apply {
                    cornerRadius = dp(26f)
                    setColor(Color.argb(220, 20, 20, 28))
                    setStroke(dp(1.5f).toInt(), Color.argb(90, 255, 255, 255))
                }
            }
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                y = dp(60f).toInt()
            }
            wm.addView(t, lp)
            overlay = t
            svc.refreshFilter() // so a button press can reach us
        } catch (e: Exception) {
            Log.d(TAG, "no warning: $e")
        }
    }

    private fun hideWarning() {
        val v = overlay ?: return
        overlay = null
        try {
            val svc = HomeKeyService.instance
            (svc?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.removeView(v)
        } catch (e: Exception) { }
    }

    private fun sleepNow() {
        val c = app ?: return
        hideWarning()
        endAt = 0L
        prefs(c).edit().remove(KEY).apply()
        HomeKeyService.instance?.refreshFilter()
        Log.d(TAG, "sleeping")
        // The sleep key also turns the TV off over HDMI on most sets.
        Thread {
            var ok = false
            try {
                LocalAdb(c.filesDir) { }.run(listOf("input keyevent KEYCODE_SLEEP"))
                ok = true
            } catch (e: Exception) { }
            if (!ok) handler.post {
                try {
                    if (Build.VERSION.SDK_INT >= 28) {
                        HomeKeyService.instance?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                    }
                } catch (e: Exception) { }
            }
        }.start()
    }

    private fun toast(c: Context, msg: String) {
        handler.post {
            try { Toast.makeText(c.applicationContext, msg, Toast.LENGTH_LONG).show() } catch (e: Exception) { }
        }
    }
}
