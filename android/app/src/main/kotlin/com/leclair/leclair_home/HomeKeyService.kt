package com.leclair.leclair_home

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
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
        const val TAG = "FoyerHome"
        const val AMAZON_HOME = "com.amazon.tv.launcher"
    }

    private var lastUp = 0L
    private var lastRedirect = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        serviceInfo = info
        Log.d(TAG, "service connected")
    }

    private fun openFoyer() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            )
        } catch (e: Exception) {
            Log.d(TAG, "could not open Foyer: $e")
        }
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_HOME) {
            Log.d(TAG, "HOME key action=${event.action}")
        }
        if (event.keyCode != KeyEvent.KEYCODE_HOME) return false
        if (event.action == KeyEvent.ACTION_UP) {
            val now = System.currentTimeMillis()
            val double = now - lastUp < 450
            lastUp = if (double) 0L else now
            if (double) {
                // double-press = escape hatch to the stock Fire TV home
                allowAmazonUntil = now + 6000
                try {
                    startActivity(
                        Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                            .setPackage(AMAZON_HOME)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    )
                } catch (e: Exception) { }
            } else {
                openFoyer()
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
        if (pkg != AMAZON_HOME) return
        val cls = event.className?.toString() ?: ""
        Log.d(TAG, "Amazon window: type=${event.eventType} $cls")
        // Settings, search etc. from Amazon are fine; only the home screen is redirected.
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && !cls.contains("Home")) return
        val now = System.currentTimeMillis()
        if (now < allowAmazonUntil || now - lastRedirect < 600) return
        lastRedirect = now
        Log.d(TAG, "redirecting to Foyer")
        openFoyer()
    }

    override fun onInterrupt() {}
}
