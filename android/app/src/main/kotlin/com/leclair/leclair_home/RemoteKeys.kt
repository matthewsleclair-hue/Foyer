package com.leclair.leclair_home

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import org.json.JSONObject

/**
 * Custom remote buttons (Settings > Remote buttons). Caught by HomeKeyService,
 * which already listens to the remote.
 *
 * Saved in Foyer's settings as "remoteKeys": {"313": "com.plexapp.android", "313L": "foyer"}.
 * "<code>" = pressed, "<code>L" = held. A value is an app package, "foyer" for
 * Foyer's home, or "" for what the button normally does.
 */
object RemoteKeys {
    const val YOUTUBE = 190 // KEYCODE_BUTTON_3 on Google TV remotes
    const val NETFLIX = 191 // KEYCODE_BUTTON_4
    const val STAR = 313 // KEYCODE_MACRO_1, the Streamer's customizable button

    /** What a known button opens when nobody changed it. */
    private val usual = mapOf(
        YOUTUBE to "com.google.android.youtube.tv",
        NETFLIX to "com.netflix.ninja"
    )

    /** Keys Foyer never takes over: moving around, OK, Back, volume, power. */
    private val never = setOf(
        KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT,
        KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_HOME, KeyEvent.KEYCODE_VOLUME_UP,
        KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_VOLUME_MUTE, KeyEvent.KEYCODE_POWER,
        KeyEvent.KEYCODE_SLEEP, KeyEvent.KEYCODE_WAKEUP, KeyEvent.KEYCODE_TV_POWER
    )

    @Volatile private var map: Map<String, String> = emptyMap()
    @Volatile private var loaded = false
    @Volatile private var youtubeDead = false

    /** Google's home screen is switched off (Foyer is the real home). */
    val googleHomeOff: Boolean get() = youtubeDead

    /** Set while Settings > Remote buttons waits for "press the button". */
    @Volatile var learn: ((Int) -> Unit)? = null
        set(v) {
            field = v
            handler.post { HomeKeyService.instance?.refreshFilter() }
        }

    private val handler = Handler(Looper.getMainLooper())
    private var downAt = 0L
    private var heldFired = false

    fun ensure(c: Context) {
        if (!loaded) reload(c)
    }

    fun reload(c: Context) {
        val out = HashMap<String, String>()
        try {
            val raw = c.getSharedPreferences("leclair_home", Context.MODE_PRIVATE).getString("json", "") ?: ""
            val rk = if (raw.isEmpty()) null else JSONObject(raw).optJSONObject("remoteKeys")
            rk?.keys()?.forEach { k -> out[k] = rk.optString(k, "") }
        } catch (e: Exception) { }
        map = out
        // With Google's home switched off, nothing answers the YouTube button, so Foyer does.
        youtubeDead = try {
            val s = c.packageManager.getApplicationEnabledSetting(HomeKeyService.GOOGLE_HOME)
            s == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER ||
                s == PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        } catch (e: Exception) { false }
        loaded = true
        HomeKeyService.instance?.refreshFilter()
    }

    private fun pressAction(code: Int): String? {
        val k = code.toString()
        if (map.containsKey(k)) return map[k]?.ifEmpty { null }
        // with Google's home off, the YouTube and Netflix buttons go dead unless Foyer answers
        if (youtubeDead && usual.containsKey(code)) return usual[code]
        return null
    }

    private fun heldAction(code: Int): String? = map["${code}L"]?.ifEmpty { null }

    /** True if the service should listen to every key (costs a little speed, so only when needed). */
    fun wanted(): Boolean = map.values.any { it.isNotEmpty() } || youtubeDead

    /** Called for every key the remote sends. Returns true when Foyer handled it. */
    fun onKey(svc: HomeKeyService, e: KeyEvent): Boolean {
        val code = e.keyCode
        if (code in never) return false
        learn?.let { cb ->
            if (e.action == KeyEvent.ACTION_DOWN && e.repeatCount == 0) {
                learn = null
                handler.post { cb(code) }
            }
            return true
        }
        val press = pressAction(code)
        val held = heldAction(code)
        if (press == null && held == null) return false
        if (held == null) {
            // press only: act right away
            if (e.action == KeyEvent.ACTION_DOWN && e.repeatCount == 0) handler.post { run(svc, press!!) }
            return true
        }
        when (e.action) {
            KeyEvent.ACTION_DOWN -> {
                if (e.repeatCount == 0) {
                    downAt = e.eventTime
                    heldFired = false
                } else if (!heldFired && e.eventTime - downAt > 450) {
                    heldFired = true
                    handler.post { run(svc, held) }
                }
            }
            KeyEvent.ACTION_UP -> {
                if (!heldFired) {
                    if (e.eventTime - downAt > 450) {
                        handler.post { run(svc, held) }
                    } else {
                        // the button's usual job, since Foyer kept the press
                        val p = press ?: usual[code]
                        if (p != null) handler.post { run(svc, p) }
                    }
                }
                heldFired = false
            }
        }
        return true
    }

    private fun run(c: Context, action: String) {
        try {
            if (action == "foyer") {
                c.startActivity(
                    Intent(c, MainActivity::class.java).putExtra("goHome", true)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                )
                return
            }
            val pm = c.packageManager
            val i = pm.getLeanbackLaunchIntentForPackage(action) ?: pm.getLaunchIntentForPackage(action) ?: return
            c.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) { }
    }
}
