package com.leclair.leclair_home

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast

/**
 * Shows a web dashboard (Homarr) full screen, from the button above the fireplace.
 * Up/Down scroll, Left/Right/OK move between and press things, Menu reloads,
 * Back goes back a page or closes. Sign-ins are remembered.
 */
class DashboardActivity : Activity() {
    private lateinit var web: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra("url") ?: run { finish(); return }
        // zoom below 100% lays the page out wider, then shrinks it to fit: more of the dashboard fits
        val zoom = (intent.getIntExtra("zoom", 75).coerceIn(40, 150)) / 100f

        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)

        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        web = WebView(this)
        web.setBackgroundColor(Color.BLACK)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            loadWithOverviewMode = true
            useWideViewPort = true
            builtInZoomControls = false
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = false
        }
        web.webChromeClient = WebChromeClient()
        root.addView(web)
        setContentView(root)

        // size the page at screen / zoom, then scale it back down to the screen
        root.post {
            val w = root.width
            val h = root.height
            web.layoutParams = FrameLayout.LayoutParams((w / zoom).toInt(), (h / zoom).toInt())
            web.pivotX = 0f
            web.pivotY = 0f
            web.scaleX = zoom
            web.scaleY = zoom
            web.requestLayout()
        }
        web.loadUrl(url)
        web.requestFocus()
        Toast.makeText(this, "Up and down scroll · Menu refreshes · Back closes", Toast.LENGTH_LONG).show()
    }

    private fun scroll(dy: Int) {
        // Dashboards often scroll an inner panel instead of the page, so scroll whichever one can.
        val js = """
            (function(d){
              var best=document.scrollingElement||document.body, most=0;
              document.querySelectorAll('*').forEach(function(x){
                var s=getComputedStyle(x).overflowY;
                if((s=='auto'||s=='scroll')&&x.scrollHeight>x.clientHeight+40&&x.clientHeight>most){best=x;most=x.clientHeight;}
              });
              best.scrollBy({top:d,behavior:'smooth'});
            })($dy);
        """.trimIndent()
        web.evaluateJavascript(js, null)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DPAD_UP -> { scroll(-420); return true }
                KeyEvent.KEYCODE_DPAD_DOWN -> { scroll(420); return true }
                KeyEvent.KEYCODE_MENU -> { web.reload(); return true }
                KeyEvent.KEYCODE_BACK -> {
                    if (web.canGoBack()) web.goBack() else finish()
                    return true
                }
            }
        }
        if (event.keyCode == KeyEvent.KEYCODE_DPAD_UP || event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN ||
            event.keyCode == KeyEvent.KEYCODE_MENU || event.keyCode == KeyEvent.KEYCODE_BACK) return true
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        try {
            (web.parent as? ViewGroup)?.removeView(web)
            web.destroy()
        } catch (e: Exception) { }
        super.onDestroy()
    }
}
