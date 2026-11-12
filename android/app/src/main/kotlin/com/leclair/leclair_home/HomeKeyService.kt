package com.leclair.leclair_home

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Keeps Foyer as the home screen on Fire OS, where Amazon's launcher can't be disabled:
 *  1. If the Home key reaches us, we open Foyer directly (double-press opens Amazon's home).
 *  2. Whenever Amazon's home screen comes to the front, we bring Foyer back to the front.
 * Enabled from Settings > Fire TV tools > Home button.
 */
class HomeKeyService : AccessibilityService() {
    companion object {
        /** Until this time (ms), Amazon's home may stay open (set when the user asks for it). */
        @Volatile var allowAmazonUntil = 0L
        @Volatile var running = false
        const val TAG = "FoyerHome"
        const val AMAZON_HOME = "com.amazon.tv.launcher"
        /** Google TV's own home screen (Streamer, Chromecast with Google TV...). */
        const val GOOGLE_HOME = "com.google.android.apps.tv.launcherx"
        @Volatile var instance: HomeKeyService? = null
    }

    private val fireTv by lazy {
        packageManager.hasSystemFeature("amazon.hardware.fire_tv") ||
            (android.os.Build.MANUFACTURER ?: "").equals("Amazon", ignoreCase = true)
    }

    /** Home redirect is only needed while a stock home screen is still around. */
    private fun needHome() = fireTv || !RemoteKeys.googleHomeOff

    /**
     * Listening to every key adds a tiny delay to each press, so on Google TV
     * it's only switched on when custom buttons or the Home redirect need it.
     */
    fun refreshFilter() {
        try {
            val info = serviceInfo ?: return
            val want = needHome() || RemoteKeys.wanted() || RemoteKeys.learn != null
            val f = if (want) info.flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
            else info.flags and AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS.inv()
            if (f != info.flags) {
                info.flags = f
                serviceInfo = info
            }
        } catch (e: Exception) { }
    }

    private var lastUp = 0L
    private var lastRedirect = 0L
    private val handler = Handler(Looper.getMainLooper())
    private val retry = Runnable { openFoyer() }

    /** Re-launch Foyer a few times so it lands in front as soon as Amazon's home starts. */
    private fun fightForFront() {
        handler.removeCallbacks(retry)
        for (d in longArrayOf(0, 150, 350, 650, 1000, 1500, 2200, 3000)) handler.postDelayed(retry, d)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        serviceInfo = info
        running = true
        instance = this
        RemoteKeys.reload(this)
        refreshFilter()
        DropRemote.service = this
        DropRemote.ensure(this)
        Log.d(TAG, "service connected")
    }

    /** Home pressed on the phone page's remote. */
    fun goHomeFromRemote() = fightForFront()

    private fun openFoyer() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .putExtra("goHome", true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            )
        } catch (e: Exception) {
            Log.d(TAG, "could not open Foyer: $e")
        }
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (RemoteKeys.onKey(this, event)) return true
        if (event.keyCode != KeyEvent.KEYCODE_HOME) return false
        // Foyer is the real home screen: Android already sends Home here.
        if (!needHome()) return false
        Log.d(TAG, "HOME key action=${event.action}")
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            val now = System.currentTimeMillis()
            val double = now - lastUp < 450
            lastUp = if (double) 0L else now
            if (double) {
                handler.removeCallbacks(retry)
                // double-press = escape hatch to the stock Fire TV home
                allowAmazonUntil = now + 6000
                for (stock in listOf(AMAZON_HOME, GOOGLE_HOME)) {
                    try {
                        startActivity(
                            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                                .setPackage(stock)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        )
                        break
                    } catch (e: Exception) { }
                }
            } else {
                fightForFront()
            }
        }
        return true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg: String? = when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> event.packageName?.toString()
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> try { rootInActiveWindow?.packageName?.toString() } catch (e: Exception) { null }
            else -> null
        }
        if (pkg != AMAZON_HOME && pkg != GOOGLE_HOME) return
        val cls = event.className?.toString() ?: ""
        Log.d(TAG, "stock home window: $pkg type=${event.eventType} $cls")
        // Settings, search etc. from Amazon are fine; only the home screen is redirected.
        if (pkg == AMAZON_HOME && event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && !cls.contains("Home")) return
        val now = System.currentTimeMillis()
        if (now < allowAmazonUntil || now - lastRedirect < 600) return
        lastRedirect = now
        Log.d(TAG, "redirecting to Foyer")
        fightForFront()
    }

    override fun onDestroy() {
        running = false
        if (instance === this) instance = null
        if (DropRemote.service === this) DropRemote.service = null
        super.onDestroy()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        running = false
        if (instance === this) instance = null
        if (DropRemote.service === this) DropRemote.service = null
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}
}
