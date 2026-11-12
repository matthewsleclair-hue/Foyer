package com.leclair.leclair_home

import android.animation.ObjectAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * Score alerts in the top corner over whatever is playing. Drawn by the remote helper,
 * which may draw over other apps; without it, a plain toast.
 *
 *   ┃ (🏒)  GOAL · TOR
 *   ┃       TOR  2 – 1  MTL
 *   ┃       2nd period · 12:34
 *   ▔▔▔▔▔▔▔▔▔▔▔▔ (timer bar)
 */
object Alerts {
    private val handler = Handler(Looper.getMainLooper())
    private var view: View? = null
    private val hide = Runnable { fadeOut() }

    private const val SECONDS = 8

    /** Called from Dart with: emoji, event, away, awayScore, home, homeScore, detail, side, color, line, size. */
    fun show(c: Context, a: Map<String, Any?>) {
        handler.post { build(c, a) }
    }

    private fun s(a: Map<String, Any?>, k: String) = (a[k] as? String) ?: ""

    /** Team colour from ESPN, lifted so dark navy or maroon still reads on a dark card. */
    private fun accent(hex: String): Int {
        val base = try {
            if (hex.length == 6) Color.parseColor("#$hex") else Color.rgb(255, 212, 59)
        } catch (e: Exception) {
            Color.rgb(255, 212, 59)
        }
        val hsv = FloatArray(3)
        Color.colorToHSV(base, hsv)
        // grey/black/white team colours: fall back to Foyer's warm yellow
        if (hsv[1] < 0.18f) return Color.rgb(255, 212, 59)
        hsv[1] = hsv[1].coerceIn(0.4f, 0.62f)
        hsv[2] = hsv[2].coerceAtLeast(0.96f)
        return Color.HSVToColor(hsv)
    }

    private fun withAlpha(c: Int, a: Int) = Color.argb(a, Color.red(c), Color.green(c), Color.blue(c))

    private fun build(c: Context, a: Map<String, Any?>) {
        val svc = HomeKeyService.instance
        val event = s(a, "event")
        val line = s(a, "line")
        val away = s(a, "away")
        val home = s(a, "home")
        val scoreLine = if (away.isNotEmpty()) "$away ${s(a, "awayScore")} – ${s(a, "homeScore")} $home" else line
        if (svc == null) {
            try { Toast.makeText(c.applicationContext, "$event\n$scoreLine", Toast.LENGTH_LONG).show() } catch (e: Exception) { }
            return
        }
        removeNow()
        try {
            val k = when ((a["size"] as? Number)?.toInt() ?: 1) { 0 -> 0.65f; 2 -> 1f; else -> 0.8f }
            val dm = svc.resources.displayMetrics
            val dp = { v: Float -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v * k, dm) }
            val acc = accent(s(a, "color"))
            val side = s(a, "side")

            fun text(t: String, sp: Float, color: Int, bold: Boolean = true, spacing: Float = 0f) = TextView(svc).apply {
                text = t
                setTextColor(color)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, sp * k)
                typeface = if (bold) Typeface.create("sans-serif-medium", Typeface.BOLD) else Typeface.create("sans-serif", Typeface.NORMAL)
                letterSpacing = spacing
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                includeFontPadding = false
            }

            // card
            val card = LinearLayout(svc).apply {
                orientation = LinearLayout.VERTICAL
                background = GradientDrawable(
                    GradientDrawable.Orientation.LEFT_RIGHT,
                    intArrayOf(Color.argb(242, 16, 18, 28), Color.argb(236, 26, 29, 44))
                ).apply {
                    cornerRadius = dp(24f)
                    setStroke(dp(1f).toInt().coerceAtLeast(1), Color.argb(70, 255, 255, 255))
                }
                clipToOutline = true
                elevation = dp(10f)
            }

            val row = LinearLayout(svc).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(16f).toInt(), dp(28f).toInt(), dp(14f).toInt())
            }
            // team-colour stripe down the left edge
            row.addView(View(svc).apply {
                background = GradientDrawable().apply { setColor(acc); cornerRadius = dp(3f) }
            }, LinearLayout.LayoutParams(dp(5f).toInt(), dp(64f).toInt()).apply {
                marginStart = dp(12f).toInt(); marginEnd = dp(16f).toInt()
            })
            // sport badge
            val badge = FrameLayout(svc).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(withAlpha(acc, 46))
                    setStroke(dp(1.5f).toInt(), withAlpha(acc, 140))
                }
            }
            badge.addView(text(s(a, "emoji"), 24f, Color.WHITE, bold = false).apply { gravity = Gravity.CENTER },
                FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            row.addView(badge, LinearLayout.LayoutParams(dp(56f).toInt(), dp(56f).toInt()).apply { marginEnd = dp(18f).toInt() })

            val col = LinearLayout(svc).apply { orientation = LinearLayout.VERTICAL }
            col.addView(text(event, 13f, acc, spacing = 0.14f))

            if (away.isNotEmpty()) {
                val score = LinearLayout(svc).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.BOTTOM
                    setPadding(0, dp(5f).toInt(), 0, dp(4f).toInt())
                }
                val dim = Color.argb(200, 255, 255, 255)
                fun num(v: String, lit: Boolean) = text(v, 30f, if (lit) acc else Color.WHITE)
                fun abbr(v: String, lit: Boolean) = text(v, 19f, if (lit) Color.WHITE else dim).apply {
                    setPadding(dp(4f).toInt(), 0, dp(4f).toInt(), dp(3f).toInt())
                }
                score.addView(abbr(away, side == "away"))
                score.addView(text(" ", 19f, dim))
                score.addView(num(s(a, "awayScore"), side == "away"))
                score.addView(text("  –  ", 22f, Color.argb(120, 255, 255, 255), bold = false).apply {
                    setPadding(0, 0, 0, dp(3f).toInt())
                })
                score.addView(num(s(a, "homeScore"), side == "home"))
                score.addView(text(" ", 19f, dim))
                score.addView(abbr(home, side == "home"))
                col.addView(score)
            } else if (line.isNotEmpty()) {
                col.addView(text(line, 22f, Color.WHITE).apply { setPadding(0, dp(6f).toInt(), 0, dp(4f).toInt()) })
            }
            val detail = s(a, "detail")
            if (detail.isNotEmpty()) col.addView(text(detail, 13.5f, Color.argb(150, 255, 255, 255), bold = false))
            row.addView(col)
            card.addView(row)

            // timer bar that runs down while the alert is up
            val bar = View(svc).apply { setBackgroundColor(withAlpha(acc, 210)) }
            card.addView(bar, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(3f).toInt().coerceAtLeast(2)))

            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                x = dp(40f).toInt()
                y = dp(34f).toInt()
            }
            (svc.getSystemService(Context.WINDOW_SERVICE) as WindowManager).addView(card, lp)
            view = card

            // slide in from the right and fade up
            card.alpha = 0f
            card.translationX = dp(70f)
            card.animate().alpha(1f).translationX(0f).setDuration(380).setInterpolator(DecelerateInterpolator(2f)).start()
            bar.post {
                bar.pivotX = 0f
                ObjectAnimator.ofFloat(bar, "scaleX", 1f, 0f).apply {
                    duration = SECONDS * 1000L
                    interpolator = LinearInterpolator()
                    start()
                }
            }
            handler.removeCallbacks(hide)
            handler.postDelayed(hide, SECONDS * 1000L)
        } catch (e: Exception) { }
    }

    private fun fadeOut() {
        val v = view ?: return
        v.animate().alpha(0f).translationX(v.width * 0.15f).setDuration(300).withEndAction {
            if (view === v) removeNow()
        }.start()
    }

    private fun removeNow() {
        handler.removeCallbacks(hide)
        val v = view ?: return
        view = null
        try {
            (HomeKeyService.instance?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.removeView(v)
        } catch (e: Exception) { }
    }
}
