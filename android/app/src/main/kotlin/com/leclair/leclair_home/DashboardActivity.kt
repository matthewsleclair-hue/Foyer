package com.leclair.leclair_home

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
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
            override fun onPageFinished(view: WebView, url: String?) {
                // a clear outline on whatever is selected, so the remote can see where it is
                view.evaluateJavascript(
                    "(function(){if(document.getElementById('foyer-focus'))return;var s=document.createElement('style');" +
                        "s.id='foyer-focus';s.textContent='*:focus{outline:4px solid #63E6BE !important;outline-offset:3px !important}';" +
                        "document.head.appendChild(s);})();", null
                )
            }
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
        Toast.makeText(this, "Up and down scroll (or move between boxes) · OK types or presses · Back closes", Toast.LENGTH_LONG).show()
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

    /**
     * Up/Down: on a page with typing boxes (a sign-in page), move between the boxes and
     * buttons; on a normal dashboard, scroll.
     */
    private fun upDown(dir: Int) {
        val js = """
            (function(dir){
              var vis=function(e){var r=e.getBoundingClientRect();return r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight&&getComputedStyle(e).visibility!='hidden';};
              var boxes=[].slice.call(document.querySelectorAll('input:not([type=hidden]):not([type=checkbox]):not([type=radio]),textarea')).filter(vis);
              if(!boxes.length) return 'scroll';
              var all=[].slice.call(document.querySelectorAll('input:not([type=hidden]),textarea,select,button,a[href],[tabindex]:not([tabindex="-1"])')).filter(vis);
              var i=all.indexOf(document.activeElement);
              var n=i<0?(dir>0?0:all.length-1):Math.min(all.length-1,Math.max(0,i+dir));
              all[n].focus();all[n].scrollIntoView({block:'center'});
              return 'moved';
            })($dir);
        """.trimIndent()
        web.evaluateJavascript(js) { r -> if (r != null && r.contains("scroll")) scroll(if (dir > 0) 420 else -420) }
    }

    /** OK: on a typing box, open the keyboard; on anything else, press it. */
    private fun ok() {
        val js = """
            (function(){
              var e=document.activeElement;
              if(!e||e===document.body) return 'none';
              var t=(e.tagName||'').toLowerCase(), ty=(e.type||'').toLowerCase();
              if(t=='textarea'||(t=='input'&&['checkbox','radio','button','submit','reset'].indexOf(ty)<0)){e.focus();return 'box';}
              e.click();return 'clicked';
            })();
        """.trimIndent()
        web.evaluateJavascript(js) { r ->
            when {
                r == null -> {}
                r.contains("box") -> {
                    web.requestFocus()
                    (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
                        .showSoftInput(web, InputMethodManager.SHOW_IMPLICIT)
                }
                r.contains("none") -> {
                    // nothing selected in the page: let the web view handle OK itself
                    web.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER))
                    web.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_CENTER))
                }
            }
        }
    }

    private fun isOk(code: Int) =
        code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER || code == KeyEvent.KEYCODE_NUMPAD_ENTER

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // while the on-screen keyboard is typing into the page, leave every key to it
        if (imeOpen()) return super.dispatchKeyEvent(event)
        if (isOk(event.keyCode)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) ok()
            return true
        }
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DPAD_UP -> { upDown(-1); return true }
                KeyEvent.KEYCODE_DPAD_DOWN -> { upDown(1); return true }
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

    private fun imeOpen(): Boolean = try {
        val r = android.graphics.Rect()
        window.decorView.getWindowVisibleDisplayFrame(r)
        // the keyboard covers part of the screen
        r.height() < window.decorView.height * 0.85
    } catch (e: Exception) { false }

    override fun onDestroy() {
        try {
            (web.parent as? ViewGroup)?.removeView(web)
            web.destroy()
        } catch (e: Exception) { }
        super.onDestroy()
    }
}
