package com.leclair.leclair_home

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool

/** Foyer's own soft navigation sounds (Settings > Appearance > Sounds). */
class UiSounds(c: Context) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(3)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()
    private val ids = mapOf(
        "move" to pool.load(c, R.raw.foyer_move, 1),
        "select" to pool.load(c, R.raw.foyer_select, 1),
        "back" to pool.load(c, R.raw.foyer_back, 1)
    )

    fun play(name: String, volume: Double) {
        val id = ids[name] ?: return
        val v = volume.toFloat().coerceIn(0f, 1f)
        pool.play(id, v, v, 1, 0, 1f)
    }

    fun release() = pool.release()
}
