package com.leclair.leclair_home

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.Calendar

/**
 * Smart idle, the "paused for a while" half: when a show or song stays paused for
 * a while, the TV turns itself off, with the sleep timer's one-minute "still here?"
 * note first (any button keeps it on).
 *
 * Android only tells apps what's playing through the debugging link, so this asks
 * `dumpsys media_session` once a minute, only while the setting is on. HDMI inputs and
 * games have no media session, so they are never turned off. Idea from couch-tv.
 */
object IdleWatch {
    private const val TAG = "FoyerIdle"
    private const val PERIOD = 60_000L
    private val handler = Handler(Looper.getMainLooper())
    private var app: Context? = null

    @Volatile private var minutes = 0     // 0 = off
    @Volatile private var quiet = false   // 11 pm to 6 am: a shorter wait
    private var pausedSig = ""
    private var pausedSince = 0L
    private var firedSig = ""
    @Volatile private var busy = false

    private val tick = Runnable { poll() }

    private fun prefs(c: Context) = c.getSharedPreferences("leclair_home", Context.MODE_PRIVATE)

    /** Picks the setting back up after Foyer restarts. */
    fun restore(c: Context) {
        val p = prefs(c)
        configure(c, p.getInt("idlePausedMin", 0), p.getBoolean("idleQuiet", false), save = false)
    }

    fun configure(c: Context, pausedMinutes: Int, quietHours: Boolean, save: Boolean = true) {
        app = c.applicationContext
        minutes = pausedMinutes.coerceIn(0, 240)
        quiet = quietHours
        if (save) prefs(c).edit().putInt("idlePausedMin", minutes).putBoolean("idleQuiet", quiet).apply()
        handler.removeCallbacks(tick)
        pausedSig = ""; pausedSince = 0L
        if (minutes > 0) handler.postDelayed(tick, PERIOD)
    }

    private fun waitMs(): Long {
        var m = minutes
        if (quiet) {
            val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            if (h >= 23 || h < 6) m = minOf(m, 15)
        }
        return m * 60_000L
    }

    private fun poll() {
        val c = app ?: return
        if (minutes <= 0) return
        handler.postDelayed(tick, PERIOD)
        if (busy || ScreenOff.active || SleepTimer.warning || SleepTimer.endAt != 0L) return
        busy = true
        Thread {
            val out = try {
                val adb = LocalAdb(c.filesDir) { }
                adb.run(listOf("dumpsys media_session | grep -E 'state=PlaybackState'"))
                adb.outputs.firstOrNull() ?: ""
            } catch (e: Exception) { null }
            handler.post {
                busy = false
                if (out != null) check(c, out)
            }
        }.start()
    }

    private fun check(c: Context, out: String) {
        // state=3 playing, state=2 paused (PlaybackState constants). Newer Android
        // prints them as "PLAYING(3)", older as just "3".
        val re = Regex("""state=PlaybackState \{state=[A-Z_]*\(?(\d+)\)?, position=(-?\d+)""")
        val states = re.findAll(out).map { it.groupValues[1].toInt() to it.groupValues[2] }.toList()
        val now = System.currentTimeMillis()
        if (states.any { it.first == 3 } || states.none { it.first == 2 }) {
            pausedSig = ""; pausedSince = 0L; firedSig = ""
            return
        }
        val sig = states.filter { it.first == 2 }.joinToString(",") { it.second }
        if (sig != pausedSig) {
            pausedSig = sig; pausedSince = now
            return
        }
        if (sig == firedSig) return // already asked about this pause
        if (now - pausedSince >= waitMs()) {
            firedSig = sig
            Log.d(TAG, "paused for ${(now - pausedSince) / 60_000} min: turning the TV off in a minute")
            SleepTimer.start(c, 1, "Paused for a while: turning the TV off in 1 minute\nPress any button to keep it on")
        }
    }
}
