package com.leclair.leclair_home

import android.content.Context

/** The language Foyer TV is set to (Settings → Appearance → Language), for the few
 *  words the Android side shows by itself: the sleep note, Screen off, toasts. */
object Lang {
    fun fr(c: Context): Boolean = try {
        val raw = c.applicationContext.getSharedPreferences("leclair_home", Context.MODE_PRIVATE).getString("json", "") ?: ""
        raw.contains("\"lang\":\"fr\"")
    } catch (_: Exception) { false }

    fun t(c: Context, en: String, fr: String): String = if (fr(c)) fr else en
}
