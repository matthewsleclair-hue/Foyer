package com.leclair.leclair_home

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import kotlin.random.Random

/**
 * A tiny web page on the home Wi-Fi so people can type on their phone instead of with the remote.
 * It only runs while a typing box is open, and the address includes a random 4-digit code.
 */
class PhoneInput(private val onText: (String) -> Unit) {
    @Volatile private var server: ServerSocket? = null
    private var pin = ""
    private var title = ""
    private var hint = ""

    /** Starts the page and returns its address, or null if the stick has no Wi-Fi address. */
    fun start(title: String, hint: String): String? {
        stop()
        this.title = title
        this.hint = hint
        pin = (1000 + Random.nextInt(9000)).toString()
        var ss: ServerSocket? = null
        for (p in 8765..8775) {
            try { ss = ServerSocket(p); break } catch (e: Exception) { }
        }
        val s = ss ?: return null
        val ip = localIp()
        if (ip == null) { try { s.close() } catch (e: Exception) { }; return null }
        server = s
        Thread { loop(s) }.apply { isDaemon = true }.start()
        return "http://$ip:${s.localPort}/$pin"
    }

    fun stop() {
        try { server?.close() } catch (e: Exception) { }
        server = null
    }

    private fun localIp(): String? {
        var fallback: String? = null
        try {
            for (ni in NetworkInterface.getNetworkInterfaces()) {
                if (!ni.isUp || ni.isLoopback) continue
                for (a in ni.inetAddresses) {
                    if (a is Inet4Address && !a.isLoopbackAddress) {
                        val ip = a.hostAddress ?: continue
                        if (ni.name.startsWith("wlan") || ni.name.startsWith("eth")) return ip
                        if (fallback == null) fallback = ip
                    }
                }
            }
        } catch (e: Exception) { }
        return fallback
    }

    private fun loop(s: ServerSocket) {
        while (!s.isClosed) {
            try {
                val c = s.accept()
                try { handle(c) } catch (e: Exception) { } finally { try { c.close() } catch (e: Exception) { } }
            } catch (e: Exception) {
                return
            }
        }
    }

    private fun readLine(i: InputStream): String? {
        val b = ByteArrayOutputStream()
        while (true) {
            val x = i.read()
            if (x < 0) return if (b.size() == 0) null else b.toString("UTF-8")
            if (x == '\n'.code) return b.toString("UTF-8").trimEnd('\r')
            if (b.size() > 8192) return null
            b.write(x)
        }
    }

    private fun handle(c: Socket) {
        c.soTimeout = 5000
        val i = c.getInputStream()
        val first = readLine(i) ?: return
        val parts = first.split(" ")
        if (parts.size < 2) return
        val method = parts[0]
        val path = parts[1].substringBefore('?')
        var len = 0
        while (true) {
            val h = readLine(i) ?: break
            if (h.isEmpty()) break
            if (h.lowercase().startsWith("content-length:")) len = h.substring(15).trim().toIntOrNull() ?: 0
        }
        if (!path.startsWith("/$pin")) {
            reply(c, 404, "<p>Wrong address. Use the one shown on the TV.</p>")
            return
        }
        if (method == "POST") {
            val n = len.coerceIn(0, 6000)
            val body = ByteArray(n)
            var got = 0
            while (got < n) {
                val r = i.read(body, got, n - got)
                if (r < 0) break
                got += r
            }
            val form = String(body, 0, got, Charsets.UTF_8)
            var text = ""
            for (kv in form.split("&")) {
                if (kv.startsWith("t=")) text = URLDecoder.decode(kv.substring(2), "UTF-8")
            }
            text = text.trim()
            if (text.isNotEmpty()) onText(text)
            reply(c, 200, page(sent = text.isNotEmpty()))
        } else {
            reply(c, 200, page(sent = false))
        }
    }

    private fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

    private fun page(sent: Boolean): String = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Foyer</title>
<style>
body{font-family:-apple-system,Helvetica,Arial,sans-serif;background:#101746;color:#fff;margin:0;padding:28px}
h1{font-size:28px;margin:0 0 6px}p{color:#cfd6ff;margin:0 0 18px}
input{width:100%;box-sizing:border-box;font-size:22px;padding:16px;border-radius:14px;border:0;margin-bottom:14px}
button{width:100%;font-size:22px;padding:16px;border-radius:14px;border:0;background:#ffb454;color:#201000;font-weight:700}
.ok{background:#1f6f43;padding:12px 16px;border-radius:12px;margin-bottom:16px}
</style></head><body>
<h1>Foyer</h1><p>${esc(title)}</p>
${if (sent) "<div class=\"ok\">Sent to your TV. You can send again if you need to.</div>" else ""}
<form method="post"><input name="t" placeholder="${esc(hint)}" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" autofocus>
<button type="submit">Send to TV</button></form></body></html>"""

    private fun reply(c: Socket, code: Int, html: String) {
        val body = html.toByteArray(Charsets.UTF_8)
        val head = "HTTP/1.1 $code ${if (code == 200) "OK" else "Not Found"}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n"
        val o = c.getOutputStream()
        o.write(head.toByteArray(Charsets.UTF_8))
        o.write(body)
        o.flush()
    }
}
