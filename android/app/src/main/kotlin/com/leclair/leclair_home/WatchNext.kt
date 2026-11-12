package com.leclair.leclair_home

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Keep watching: Android's Watch Next list, the "continue watching" rows that streaming
 * apps keep for the TV (the show, the episode, how far in, a picture and a link back in).
 * Reading it needs READ_TV_LISTINGS, which Foyer gives itself once over the TV's
 * debugging link. Read only. Idea from couch-tv (github.com/Seagey/couch-tv, MIT).
 */
object WatchNext {
    private const val TAG = "FoyerKeep"
    private val URI: Uri = Uri.parse("content://android.media.tv/watch_next_program")
    private val PERMISSION =
        if (Build.VERSION.SDK_INT >= 29) "android.permission.READ_TV_LISTINGS"
        else "com.android.providers.tv.permission.READ_EPG_DATA"

    /** Pictures already made small, by address. */
    private val art = object : LinkedHashMap<String, ByteArray>(32, 0.75f, true) {
        override fun removeEldestEntry(e: MutableMap.MutableEntry<String, ByteArray>?) = size > 40
    }

    private fun granted(c: Context) = c.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED

    /** Gives Foyer the permission over the debugging link (once). */
    private fun ensure(c: Context): Boolean {
        if (granted(c)) return true
        try {
            LocalAdb(c.filesDir) { }.run(listOf("pm grant ${c.packageName} $PERMISSION"))
        } catch (e: Exception) {
            Log.d(TAG, "could not grant $PERMISSION: $e")
        }
        return granted(c)
    }

    /** Newest first, at most [max], one per show. Runs on a background thread. */
    fun list(c: Context, max: Int, skip: Set<String>): Map<String, Any?> {
        if (!ensure(c)) return mapOf("ok" to false, "why" to "permission")
        val pm = c.packageManager
        val out = ArrayList<Map<String, Any?>>()
        val seen = HashSet<String>()
        try {
            val cols = arrayOf(
                "_id", "package_name", "title", "episode_title", "season_display_number",
                "episode_display_number", "poster_art_uri", "thumbnail_uri", "last_playback_position_millis",
                "duration_millis", "last_engagement_time_utc_millis", "watch_next_type"
            )
            c.contentResolver.query(URI, cols, null, null, "last_engagement_time_utc_millis DESC")?.use { cur ->
                while (cur.moveToNext() && out.size < max) {
                    val pkg = cur.getString(1) ?: continue
                    if (pkg == c.packageName || pkg in skip) continue
                    val title = cur.getString(2)?.takeIf { it.isNotBlank() } ?: continue
                    if (!seen.add("$pkg|${title.lowercase()}")) continue
                    // the app must still be here and openable
                    if (pm.getLeanbackLaunchIntentForPackage(pkg) == null && pm.getLaunchIntentForPackage(pkg) == null) continue
                    val label = try {
                        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                    } catch (e: Exception) { pkg }
                    val pos = cur.getLong(8)
                    val dur = cur.getLong(9)
                    val pic = cur.getString(7)?.takeIf { it.isNotBlank() } ?: cur.getString(6)?.takeIf { it.isNotBlank() }
                    out.add(
                        mapOf(
                            "id" to cur.getLong(0),
                            "package" to pkg,
                            "app" to label,
                            "title" to title,
                            "episodeTitle" to cur.getString(3),
                            "season" to cur.getString(4),
                            "episode" to cur.getString(5),
                            "engaged" to cur.getLong(10),
                            "progress" to if (dur > 0 && pos > 0) (pos.toDouble() / dur).coerceIn(0.0, 1.0) else null,
                            "image" to pic?.let { picture(c, it) }
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "watch next unreadable: $e")
            return mapOf("ok" to false, "why" to "${e.message}")
        }
        return mapOf("ok" to true, "items" to out)
    }

    /** A small JPEG of the card's picture (content:// or web), or null. */
    private fun picture(c: Context, raw: String): ByteArray? {
        synchronized(art) { art[raw]?.let { return it } }
        val bytes: ByteArray = (try {
            val u = Uri.parse(raw)
            when (u.scheme) {
                "content", "android.resource", "file" -> c.contentResolver.openInputStream(u)?.use { it.readBytes() }
                "http", "https" -> (URL(raw).openConnection() as HttpURLConnection).run {
                    connectTimeout = 5000; readTimeout = 7000
                    inputStream.use { it.readBytes() }
                }
                else -> null
            }
        } catch (e: Exception) { null }) ?: return null
        val small: ByteArray = (try {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, o)
            var s = 1
            while (o.outWidth / (s * 2) >= 360) s *= 2
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = s })
                ?: return null
            val w = 360
            val h = (bmp.height * w / bmp.width.coerceAtLeast(1)).coerceAtLeast(1)
            val scaled = if (bmp.width > w) Bitmap.createScaledBitmap(bmp, w, h, true) else bmp
            ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
        } catch (e: Exception) { null }) ?: return null
        synchronized(art) { art[raw] = small }
        return small
    }

    /** Opens a card: its own link, only ever in the app that owns it, else just that app. */
    fun open(c: Context, id: Long): Boolean {
        var pkg: String? = null
        var link: String? = null
        try {
            c.contentResolver.query(ContentUris.withAppendedId(URI, id), arrayOf("package_name", "intent_uri"), null, null, null)
                ?.use { cur -> if (cur.moveToFirst()) { pkg = cur.getString(0); link = cur.getString(1) } }
        } catch (e: Exception) { }
        val owner = pkg ?: return false
        link?.let { raw ->
            try {
                val i = Intent.parseUri(raw, Intent.URI_INTENT_SCHEME)
                if (i.component != null && i.component!!.packageName != owner) i.component = null
                i.setPackage(owner)
                i.selector = null
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (i.resolveActivity(c.packageManager) != null) {
                    c.startActivity(i)
                    return true
                }
            } catch (e: Exception) { Log.d(TAG, "card link failed: $e") }
        }
        val pm = c.packageManager
        val i = pm.getLeanbackLaunchIntentForPackage(owner) ?: pm.getLaunchIntentForPackage(owner) ?: return false
        return try { c.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true } catch (e: Exception) { false }
    }
}
