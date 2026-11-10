package com.leclair.leclair_home

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * The phone page's remote control. One request stays open to the Foyer Drop server; when a
 * button is pressed on the phone, the server answers and we act on it here.
 *
 * What is possible without system permissions:
 *  - inside Foyer: every button, as real key presses.
 *  - inside other apps (needs the Home button service on): Back, Home and the media buttons
 *    always work. Arrows, OK and typing work by moving the app's own focus, which regular
 *    Android screens support and some apps with custom screens (Netflix, YouTube) do not.
 */
object DropRemote {
    private const val TAG = "FoyerRemote"
    @Volatile private var url = ""
    @Volatile private var token = ""
    @Volatile private var loaded = false
    @Volatile var activity: MainActivity? = null
    @Volatile var activityResumed = false
    @Volatile var service: HomeKeyService? = null
    private var thread: Thread? = null
    private val main = Handler(Looper.getMainLooper())

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("foyer_drop", Context.MODE_PRIVATE)

    /** Called from the app whenever the server link changes. */
    fun configure(ctx: Context, newUrl: String, newToken: String) {
        url = newUrl.trimEnd('/')
        token = newToken
        loaded = true
        prefs(ctx).edit().putString("url", url).putString("token", token).apply()
        ensure(ctx)
    }

    /** Starts the listener if it is not running. Safe to call often. */
    @Synchronized
    fun ensure(ctx: Context) {
        if (!loaded) {
            val p = prefs(ctx)
            url = p.getString("url", "") ?: ""
            token = p.getString("token", "") ?: ""
            loaded = true
        }
        if (thread?.isAlive == true) return
        thread = Thread({ loop() }, "foyer-remote").apply { isDaemon = true; start() }
    }

    private fun wanted() = url.isNotEmpty() && token.isNotEmpty() && (activityResumed || HomeKeyService.running)

    private fun loop() {
        while (true) {
            try {
                if (!wanted()) {
                    Thread.sleep(3000)
                    continue
                }
                val c = URL("$url/api/tv/keys").openConnection() as HttpURLConnection
                c.connectTimeout = 8000
                c.readTimeout = 40000
                c.setRequestProperty("Authorization", "Bearer $token")
                val code = c.responseCode
                if (code == 200) {
                    val body = c.inputStream.bufferedReader().use { it.readText() }
                    val keys = JSONObject(body).optJSONArray("keys")
                    if (keys != null) {
                        for (i in 0 until keys.length()) {
                            val k = keys.getJSONObject(i)
                            val type = k.optString("type")
                            val value = k.optString("value")
                            main.post { act(type, value) }
                        }
                    }
                } else {
                    c.errorStream?.close()
                    // 401 = unlinked, 404 = older server: check back slowly
                    Thread.sleep(if (code == 401 || code == 404) 30000 else 5000)
                }
                c.disconnect()
            } catch (e: InterruptedException) {
                return
            } catch (e: Exception) {
                try { Thread.sleep(5000) } catch (e2: InterruptedException) { return }
            }
        }
    }

    private fun act(type: String, value: String) {
        try {
            if (type == "text") typeText(value) else if (type == "key") press(value)
        } catch (e: Exception) {
            Log.d(TAG, "could not do $type $value: $e")
        }
    }

    private val keyCodes = mapOf(
        "up" to KeyEvent.KEYCODE_DPAD_UP,
        "down" to KeyEvent.KEYCODE_DPAD_DOWN,
        "left" to KeyEvent.KEYCODE_DPAD_LEFT,
        "right" to KeyEvent.KEYCODE_DPAD_RIGHT,
        "ok" to KeyEvent.KEYCODE_DPAD_CENTER,
        "back" to KeyEvent.KEYCODE_BACK,
        "menu" to KeyEvent.KEYCODE_MENU
    )
    private val mediaCodes = mapOf(
        "play" to KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
        "rewind" to KeyEvent.KEYCODE_MEDIA_REWIND,
        "forward" to KeyEvent.KEYCODE_MEDIA_FAST_FORWARD
    )

    private fun press(key: String) {
        val act = activity
        val svc = service
        val ctx: Context = act ?: svc ?: return

        mediaCodes[key]?.let { code ->
            if (activityResumed) return // nothing is playing on Foyer's own screens
            val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val t = SystemClock.uptimeMillis()
            am.dispatchMediaKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0))
            am.dispatchMediaKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, code, 0))
            return
        }
        if (key == "home") {
            if (svc != null) svc.goHomeFromRemote() else act?.goHomeFromRemote()
            return
        }
        // Inside Foyer: real key presses into our own window.
        if (activityResumed && act != null) {
            val code = keyCodes[key] ?: return
            val t = SystemClock.uptimeMillis()
            act.dispatchKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0))
            act.dispatchKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, code, 0))
            return
        }
        // Inside another app: go through the accessibility service.
        if (svc == null) return
        when (key) {
            "back" -> svc.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            "ok" -> click(svc)
            "up" -> move(svc, View.FOCUS_UP)
            "down" -> move(svc, View.FOCUS_DOWN)
            "left" -> move(svc, View.FOCUS_LEFT)
            "right" -> move(svc, View.FOCUS_RIGHT)
        }
    }

    private fun focused(svc: HomeKeyService): AccessibilityNodeInfo? {
        val root = svc.rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
    }

    private fun firstWhere(n: AccessibilityNodeInfo?, depth: Int, test: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (n == null || depth > 40) return null
        if (n.isVisibleToUser && test(n)) return n
        for (i in 0 until n.childCount) {
            val hit = firstWhere(n.getChild(i), depth + 1, test)
            if (hit != null) return hit
        }
        return null
    }

    private fun move(svc: HomeKeyService, direction: Int) {
        val cur = focused(svc)
        if (cur == null) {
            // nothing focused yet: start on the first thing that can take focus
            firstWhere(svc.rootInActiveWindow, 0) { it.isFocusable }?.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            return
        }
        cur.focusSearch(direction)?.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
    }

    private fun click(svc: HomeKeyService) {
        var n = focused(svc)
        var hops = 0
        while (n != null && hops < 6) {
            if (n.isClickable && n.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return
            n = n.parent
            hops++
        }
    }

    private fun typeText(text: String) {
        val svc = service ?: return
        val root = svc.rootInActiveWindow ?: return
        val cur = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        val field = if (cur != null && cur.isEditable) cur else firstWhere(root, 0) { it.isEditable } ?: return
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        field.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }
}
