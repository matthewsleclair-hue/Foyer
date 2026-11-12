package com.leclair.leclair_home

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * Lets Foyer see which song is playing in Spotify, YouTube Music and other music apps.
 * Android only shares that with a "notification listener"; Foyer doesn't read any
 * notifications, it just needs to be one. Switched on over the debugging link.
 */
class MediaListener : NotificationListenerService()

/**
 * Now playing: the song, artist and cover of whatever music is playing behind Foyer,
 * with play/pause, next and previous. A paused song stays for ten minutes.
 * Idea from couch-tv (github.com/Seagey/couch-tv, MIT).
 */
object NowPlaying {
    private const val TAG = "FoyerNowPlaying"
    private const val PAUSED_KEEP_MS = 10 * 60_000L

    private val lastPlaying = HashMap<String, Long>()

    /** Video apps that label videos with an "artist" (the channel): not music. */
    private val videoApps = setOf("com.google.android.youtube.tv", "com.amazon.firetv.youtube", "com.google.android.youtube")
    private var artKey = ""
    private var artBytes: ByteArray? = null
    @Volatile private var asked = false

    private fun component(c: Context) = ComponentName(c, MediaListener::class.java)

    private fun allowed(c: Context): Boolean {
        val list = Settings.Secure.getString(c.contentResolver, "enabled_notification_listeners") ?: ""
        return list.split(':').any { ComponentName.unflattenFromString(it) == component(c) }
    }

    /** Switches the listener on over the debugging link (once per run). Background thread. */
    private fun ensure(c: Context): Boolean {
        if (allowed(c)) return true
        if (asked) return false
        asked = true
        try {
            LocalAdb(c.filesDir) { }.run(listOf("cmd notification allow_listener ${component(c).flattenToString()}"))
        } catch (e: Exception) {
            Log.d(TAG, "could not switch the listener on: $e")
        }
        return allowed(c)
    }

    private fun controllers(c: Context): List<MediaController> {
        val msm = c.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        return try { msm.getActiveSessions(component(c)) } catch (e: SecurityException) { emptyList() }
    }

    private fun isMusic(m: MediaMetadata?): Boolean {
        if (m == null) return false
        val title = m.getString(MediaMetadata.METADATA_KEY_TITLE) ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
        val artist = m.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
        return !title.isNullOrBlank() && !artist.isNullOrBlank()
    }

    /** The music playing now (or paused in the last ten minutes), or null. Background thread. */
    private fun pick(c: Context): MediaController? {
        val now = System.currentTimeMillis()
        val music = controllers(c).filter {
            it.packageName != c.packageName && it.packageName !in videoApps && isMusic(it.metadata)
        }
        for (m in music) if (m.playbackState?.state == PlaybackState.STATE_PLAYING) lastPlaying[m.packageName] = now
        return music.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: music.filter { now - (lastPlaying[it.packageName] ?: 0L) < PAUSED_KEEP_MS }
                .maxByOrNull { lastPlaying[it.packageName] ?: 0L }
    }

    fun get(c: Context): Map<String, Any?> {
        if (!ensure(c)) return mapOf("ok" to false)
        val m = pick(c) ?: return mapOf("ok" to true)
        val md = m.metadata ?: return mapOf("ok" to true)
        val title = md.getString(MediaMetadata.METADATA_KEY_TITLE) ?: md.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: ""
        val artist = md.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: md.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
        val pm = c.packageManager
        val label = try { pm.getApplicationLabel(pm.getApplicationInfo(m.packageName, 0)).toString() } catch (e: Exception) { m.packageName }
        val key = "${m.packageName}|$title|$artist"
        if (key != artKey) {
            artKey = key
            val bmp: Bitmap? = md.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: md.getBitmap(MediaMetadata.METADATA_KEY_ART)
                ?: md.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
            artBytes = bmp?.let {
                try {
                    val s = Bitmap.createScaledBitmap(it, 240, (240 * it.height / it.width.coerceAtLeast(1)).coerceAtLeast(1), true)
                    ByteArrayOutputStream().also { o -> s.compress(Bitmap.CompressFormat.JPEG, 88, o) }.toByteArray()
                } catch (e: Exception) { null }
            }
        }
        return mapOf(
            "ok" to true,
            "package" to m.packageName,
            "app" to label,
            "title" to title,
            "artist" to artist,
            "playing" to (m.playbackState?.state == PlaybackState.STATE_PLAYING),
            "art" to artBytes
        )
    }

    /** toggle, next or previous, sent to the same music app. */
    fun control(c: Context, action: String, pkg: String?): Boolean {
        val m = controllers(c).firstOrNull { it.packageName == pkg } ?: pick(c) ?: return false
        val t = m.transportControls
        when (action) {
            "toggle" -> if (m.playbackState?.state == PlaybackState.STATE_PLAYING) t.pause() else t.play()
            "next" -> t.skipToNext()
            "previous" -> t.skipToPrevious()
            else -> return false
        }
        return true
    }
}
