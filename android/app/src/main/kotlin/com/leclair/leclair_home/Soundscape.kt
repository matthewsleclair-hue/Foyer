package com.leclair.leclair_home

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random

/**
 * Soundscapes: rain, ocean waves, a crackling fire or brown noise, made by the TV itself
 * (no video, no internet, nothing to download). Plays until stopped, or until the TV
 * goes to sleep. Idea from couch-tv (github.com/Seagey/couch-tv, MIT).
 */
object Soundscape {
    private const val TAG = "FoyerSoundscape"
    private const val RATE = 44100

    @Volatile var kind: String = ""
        private set
    @Volatile private var running = false
    private var thread: Thread? = null

    @Volatile private var generation = 0

    fun play(k: String) {
        stop()
        if (k !in setOf("rain", "ocean", "fire", "brown")) return
        kind = k
        running = true
        val g = ++generation
        thread = Thread({ loop(k, g) }, "soundscape").apply { start() }
    }

    /** Fades out over a second on its own thread (never blocks the caller). */
    fun stop() {
        running = false
        thread = null
        kind = ""
    }

    private fun loop(k: String, g: Int) {
        val min = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val track = try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
                )
                .setAudioFormat(
                    AudioFormat.Builder().setSampleRate(RATE).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build()
                )
                .setBufferSizeInBytes(maxOf(min, 16384))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            Log.d(TAG, "no audio: $e"); if (g == generation) kind = ""; return
        }
        val gen = Gen(k)
        val n = 2048
        val buf = ShortArray(n * 2)
        var t = 0L
        var fadeOut = -1
        try {
            track.play()
            while (true) {
                // stopped, or replaced by another soundscape: one second to fade away
                if ((!running || g != generation) && fadeOut < 0) fadeOut = RATE
                for (i in 0 until n) {
                    val fadeIn = minOf(1.0, t / (RATE * 2.5))
                    val f = if (fadeOut >= 0) maxOf(0.0, fadeOut.toDouble() / RATE) else 1.0
                    gen.next(t)
                    val v = fadeIn * f * 32767
                    buf[2 * i] = (gen.l * v).coerceIn(-32767.0, 32767.0).toInt().toShort()
                    buf[2 * i + 1] = (gen.r * v).coerceIn(-32767.0, 32767.0).toInt().toShort()
                    t++
                    if (fadeOut > 0) fadeOut--
                }
                track.write(buf, 0, buf.size)
                if (fadeOut == 0) break
            }
        } catch (e: Exception) {
            Log.d(TAG, "stopped: $e")
        } finally {
            try { track.stop() } catch (_: Exception) { }
            track.release()
        }
    }

    /** The sound makers. Everything is gentle filtered noise; levels stay well under clipping. */
    private class Gen(val k: String) {
        val rnd = Random(System.nanoTime())
        var brownL = 0.0; var brownR = 0.0
        var lpL = 0.0; var lpR = 0.0
        var hpPrevL = 0.0; var hpPrevR = 0.0; var hpL = 0.0; var hpR = 0.0
        // short sounds layered on top: raindrops, crackles
        var burst = 0.0; var burstDecay = 0.0; var burstPan = 0.5; var burstLp = 0.0
        var swellPhase = rnd.nextDouble() * 2 * PI
        var swellPeriod = 8.0 + rnd.nextDouble() * 4

        fun white() = rnd.nextDouble() * 2 - 1

        fun brown(prev: Double): Double = ((prev + 0.02 * white()) / 1.02)

        var l = 0.0
        var r = 0.0

        private fun out(a: Double, b: Double) { l = a; r = b }

        fun next(t: Long) {
            brownL = brown(brownL); brownR = brown(brownR)
            when (k) {
                "brown" -> out(brownL * 3.2, brownR * 3.2)
                "ocean" -> {
                    // waves: brown noise that swells in and draws back every 8-12 seconds
                    val secs = t.toDouble() / RATE
                    var s = 0.5 + 0.5 * sin(2 * PI * secs / swellPeriod + swellPhase)
                    s = s * s
                    if (t % (RATE * 12L) == 0L) swellPeriod = 8.0 + rnd.nextDouble() * 4
                    val wl = white(); val wr = white()
                    lpL += 0.08 * (wl - lpL); lpR += 0.08 * (wr - lpR) // the hiss as a wave breaks
                    val amp = 0.18 + 0.82 * s
                    out((brownL * 3.0 + lpL * 0.35 * s) * amp, (brownR * 3.0 + lpR * 0.35 * s) * amp)
                }
                "rain" -> {
                    // steady soft hiss (band-limited noise) plus drops here and there
                    val wl = white(); val wr = white()
                    lpL += 0.35 * (wl - lpL); lpR += 0.35 * (wr - lpR)
                    hpL = 0.97 * (hpL + lpL - hpPrevL); hpPrevL = lpL
                    hpR = 0.97 * (hpR + lpR - hpPrevR); hpPrevR = lpR
                    if (burst < 0.01 && rnd.nextDouble() < 0.0009) {
                        burst = 0.25 + rnd.nextDouble() * 0.35
                        burstDecay = exp(-1.0 / (RATE * (0.004 + rnd.nextDouble() * 0.01)))
                        burstPan = rnd.nextDouble()
                    }
                    burstLp += 0.5 * (white() * burst - burstLp)
                    burst *= burstDecay
                    val d = burstLp
                    out(hpL * 0.32 + brownL * 0.8 + d * (1 - burstPan), hpR * 0.32 + brownR * 0.8 + d * burstPan)
                }
                else -> { // fire: a low rumble, a soft roar, and crackles and pops
                    val wl = white()
                    lpL += 0.05 * (wl - lpL)
                    if (burst < 0.02 && rnd.nextDouble() < 0.0012) {
                        val pop = rnd.nextDouble() < 0.15
                        burst = if (pop) 0.7 + rnd.nextDouble() * 0.3 else 0.2 + rnd.nextDouble() * 0.4
                        burstDecay = exp(-1.0 / (RATE * (if (pop) 0.012 else 0.0025 + rnd.nextDouble() * 0.004)))
                        burstPan = 0.25 + rnd.nextDouble() * 0.5
                    }
                    val c = white() * burst
                    burst *= burstDecay
                    val base = brownL * 2.2 + lpL * 0.25
                    out(base + c * (1 - burstPan), base + c * burstPan)
                }
            }
        }
    }
}
