package com.leclair.leclair_home

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast

/**
 * Safety net: a home screen that crashes as it opens must never hold the TV in a loop.
 *
 * Two things are written down straight away (commit, not apply), so they survive the
 * process dying:
 *  - every start of Foyer that never settled (didn't keep running for SETTLE_MS),
 *  - every crash Java sees.
 *
 * Two of those within a few minutes and Foyer steps aside: the TV's own home screen
 * is switched back on and opened, and the Home button helper stops pulling Foyer back,
 * for ASIDE_MS. After that, the next Home press tries Foyer again. Once Foyer runs
 * cleanly, the TV's own home is switched off again (only if Foyer switched it on).
 *
 * Idea from couch-tv (github.com/Seagey/couch-tv, MIT).
 */
object CrashGuard {
    private const val TAG = "FoyerGuard"
    private const val PREFS = "foyer_crash_guard"
    private const val WINDOW_MS = 3 * 60_000L   // two failures within this ...
    private const val ASIDE_MS = 5 * 60_000L    // ... and Foyer steps aside this long
    const val SETTLE_MS = 20_000L               // a start that lives this long is healthy
    private const val LIMIT = 2
    private const val GOOGLE_HOME = "com.google.android.apps.tv.launcherx"
    private const val AMAZON_HOME = "com.amazon.tv.launcher"

    @Volatile private var installed = false
    @Volatile private var startedThisProcess = false
    @Volatile private var recorded = false
    private val handler = Handler(Looper.getMainLooper())

    private fun prefs(c: Context) = c.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun times(c: Context, key: String): List<Long> =
        (prefs(c).getString(key, "") ?: "").split(',').mapNotNull { it.toLongOrNull() }

    private fun add(c: Context, key: String) {
        val now = System.currentTimeMillis()
        val keep = times(c, key).filter { now - it < WINDOW_MS } + now
        prefs(c).edit().putString(key, keep.joinToString(",")).commit()
    }

    /** True while Foyer is standing aside for the TV's own home. */
    fun aside(c: Context): Boolean = System.currentTimeMillis() < prefs(c).getLong("asideUntil", 0L)

    /** Records crashes from here on. Safe to call more than once. */
    fun install(c: Context) {
        if (installed) return
        installed = true
        val app = c.applicationContext
        val before = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            if (!recorded) {
                recorded = true
                try { add(app, "crashes") } catch (_: Exception) { }
            }
            before?.uncaughtException(t, e)
        }
    }

    /**
     * Called first thing when Foyer's screen is created. Returns true when Foyer should
     * step aside instead of opening (the caller then finishes).
     */
    fun onStart(a: Activity): Boolean {
        install(a)
        val p = prefs(a)
        val now = System.currentTimeMillis()
        if (!startedThisProcess) {
            startedThisProcess = true
            // the last start never settled: it died early
            if (p.getLong("pending", 0L) != 0L) add(a, "unsettled")
            p.edit().putLong("pending", now).commit()
            handler.postDelayed({ settled(a.applicationContext) }, SETTLE_MS)
        }
        if (aside(a)) {
            openStockHome(a)
            return true
        }
        val fails = (times(a, "crashes") + times(a, "unsettled")).filter { now - it < WINDOW_MS }
        if (fails.size >= LIMIT) {
            Log.w(TAG, "Foyer failed ${fails.size} times in a few minutes: stepping aside")
            p.edit()
                .putLong("asideUntil", now + ASIDE_MS)
                .remove("crashes").remove("unsettled")
                .commit()
            toast(a, "Foyer had a problem, so the TV's own home is on for a few minutes.")
            openStockHome(a)
            return true
        }
        return false
    }

    /** Foyer has been running cleanly: forget the pending start, tidy up after stepping aside. */
    private fun settled(c: Context) {
        val p = prefs(c)
        p.edit().putLong("pending", 0L).apply()
        if (p.getBoolean("reenabledGoogle", false) && !aside(c)) {
            Thread {
                try {
                    LocalAdb(c.filesDir) { }.run(listOf("pm disable-user --user 0 $GOOGLE_HOME"))
                    p.edit().putBoolean("reenabledGoogle", false).apply()
                    Log.d(TAG, "Foyer is healthy again: Google's home is off again")
                } catch (e: Exception) { Log.d(TAG, "could not switch Google's home off: $e") }
            }.start()
        }
    }

    /** Opens the TV's own home. On Google TV it may have to be switched back on first. */
    private fun openStockHome(a: Activity) {
        val app = a.applicationContext
        if (tryOpen(app, AMAZON_HOME) || tryOpen(app, GOOGLE_HOME)) return
        Thread {
            var ok = false
            try {
                LocalAdb(app.filesDir) { }.run(listOf("pm enable $GOOGLE_HOME"))
                prefs(app).edit().putBoolean("reenabledGoogle", true).commit()
                ok = true
            } catch (e: Exception) { Log.d(TAG, "could not switch Google's home on: $e") }
            handler.post {
                if (!(ok && tryOpen(app, GOOGLE_HOME))) {
                    // last resort: the TV's settings, so the remote can still reach everything
                    try {
                        app.startActivity(Intent(android.provider.Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: Exception) { }
                }
            }
        }.start()
    }

    private fun tryOpen(c: Context, pkg: String): Boolean = try {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).setPackage(pkg)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (c.packageManager.resolveActivity(i, 0) == null) false
        else { c.startActivity(i); true }
    } catch (_: Exception) { false }

    private fun toast(c: Context, msg: String) {
        try { Toast.makeText(c.applicationContext, msg, Toast.LENGTH_LONG).show() } catch (_: Exception) { }
    }
}
