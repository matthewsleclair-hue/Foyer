package com.leclair.leclair_home

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper

/**
 * The fireplace's crackle: a 48-second loop (res/raw/foyer_fire.ogg, tagged ANDROID_LOOP so
 * Android repeats it without a gap), faded in and out so it never starts or stops abruptly.
 */
object FireSound {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var level = 0f      // what's playing now
    private var target = 0f     // where the fade is heading
    private var stopAtZero = false

    private val step = object : Runnable {
        override fun run() {
            val p = player ?: return
            val d = target - level
            level = if (kotlin.math.abs(d) < 0.04f) target else level + d * 0.18f
            try { p.setVolume(level, level) } catch (e: Exception) { }
            if (level == target) {
                if (stopAtZero && target == 0f) release()
                return
            }
            handler.postDelayed(this, 40)
        }
    }

    /** volume 0..1. Starts the loop if needed and fades to that volume. */
    fun play(c: Context, volume: Float) {
        stopAtZero = false
        target = volume.coerceIn(0f, 1f)
        if (player == null) {
            try {
                val p = MediaPlayer.create(
                    c.applicationContext, R.raw.foyer_fire,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                    0
                ) ?: return
                p.isLooping = true
                level = 0f
                p.setVolume(0f, 0f)
                p.start()
                player = p
            } catch (e: Exception) {
                return
            }
        }
        handler.removeCallbacks(step)
        handler.post(step)
    }

    /** Fades out, then lets go of the player. */
    fun stop() {
        if (player == null) return
        stopAtZero = true
        target = 0f
        handler.removeCallbacks(step)
        handler.post(step)
    }

    private fun release() {
        handler.removeCallbacks(step)
        try { player?.stop() } catch (e: Exception) { }
        try { player?.release() } catch (e: Exception) { }
        player = null
        level = 0f
    }

    /** Foyer left the screen: stop right away. */
    fun cut() = release()
}
