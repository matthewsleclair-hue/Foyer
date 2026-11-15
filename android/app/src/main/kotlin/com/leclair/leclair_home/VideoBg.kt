package com.leclair.leclair_home

import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/** Video background: a muted clip that loops behind the home screen. MediaPlayer draws into
 *  a Flutter texture, so Foyer shows it like any picture. One at a time. */
class VideoBg(private val engine: FlutterEngine) {
    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var player: MediaPlayer? = null
    private val main = Handler(Looper.getMainLooper())

    /** Answers {id, width, height} once the clip is playing, or null when it won't play. */
    fun start(url: String, result: MethodChannel.Result) {
        stop()
        val e = engine.renderer.createSurfaceTexture()
        entry = e
        val s = Surface(e.surfaceTexture())
        surface = s
        var answered = false
        fun answer(v: Any?) { if (!answered) { answered = true; main.post { result.success(v) } } }
        try {
            player = MediaPlayer().apply {
                setDataSource(url)
                setSurface(s)
                isLooping = true
                setVolume(0f, 0f)
                setOnPreparedListener { mp ->
                    e.surfaceTexture().setDefaultBufferSize(mp.videoWidth.coerceAtLeast(1), mp.videoHeight.coerceAtLeast(1))
                    mp.start()
                    answer(mapOf("id" to e.id(), "width" to mp.videoWidth, "height" to mp.videoHeight))
                }
                setOnErrorListener { _, _, _ -> answer(null); if (entry === e) stop(); true }
                prepareAsync()
            }
        } catch (_: Exception) {
            answer(null)
            stop()
        }
        // a link that never answers: give up after 20 seconds
        main.postDelayed({ if (!answered) { answer(null); if (entry === e) stop() } }, 20_000)
    }

    fun pause() { try { player?.takeIf { it.isPlaying }?.pause() } catch (_: Exception) { } }
    fun resume() { try { player?.start() } catch (_: Exception) { } }

    fun stop() {
        try { player?.release() } catch (_: Exception) { }
        player = null
        try { surface?.release() } catch (_: Exception) { }
        surface = null
        try { entry?.release() } catch (_: Exception) { }
        entry = null
    }
}
