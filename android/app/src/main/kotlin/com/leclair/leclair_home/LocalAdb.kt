package com.leclair.leclair_home

import android.util.Base64
import java.io.DataInputStream
import java.io.File
import java.math.BigInteger
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec

/**
 * Minimal ADB client that talks to this device's own adbd on port 5555, so the
 * Tune-up screen can run `pm disable-user` / `pm grant` without a computer.
 * Needs "ADB debugging" turned on; the TV asks once to allow this app's key.
 */
class LocalAdb(private val dir: File, private val log: (String) -> Unit) {
    private companion object {
        const val CNXN = 0x4e584e43
        const val AUTH = 0x48545541
        const val OPEN = 0x4e45504f
        const val OKAY = 0x59414b4f
        const val CLSE = 0x45534c43
        const val WRTE = 0x45545257
        const val VERSION = 0x01000000
        const val MAXDATA = 256 * 1024
        const val PORT = 5555
    }

    private class Msg(val cmd: Int, val arg0: Int, val arg1: Int, val data: ByteArray)

    private lateinit var sock: Socket
    private lateinit var input: DataInputStream
    private var nextId = 1

    fun run(commands: List<String>) {
        // make the key first: generating it on a slow stick can take a while
        val kp = keys()
        var last: Exception? = null
        for (h in hosts()) {
            try {
                if (attempt(h, kp, commands)) return
            } catch (e: Exception) {
                last = e
                log("$h: ${e.javaClass.simpleName}")
            }
        }
        throw last ?: ConnectException("ECONNREFUSED")
    }

    /** Returns true when the commands ran. Throws if the connection failed before that. */
    private fun attempt(host: String, kp: KeyPair, commands: List<String>): Boolean {
        log("Connecting to $host:$PORT")
        sock = Socket()
        sock.connect(InetSocketAddress(host, PORT), 2500)
        sock.soTimeout = 15000
        sock.tcpNoDelay = true
        try {
            input = DataInputStream(sock.getInputStream())
            handshake(kp)
            sock.soTimeout = 60000
            log("Connected.")
            for (c in commands) {
                log("$ $c")
                val out = try {
                    shell(c).trim()
                } catch (e: java.io.EOFException) {
                    if (c.trim() == "reboot") { log("Restarting…"); return true }
                    throw e
                }
                if (out.isNotEmpty()) out.lines().take(6).forEach { log(it.take(160)) }
            }
            return true
        } finally {
            try { sock.close() } catch (e: Exception) { }
        }
    }

    // ── connection ──

    private fun hosts(): List<String> {
        val h = arrayListOf("127.0.0.1")
        try {
            for (ni in NetworkInterface.getNetworkInterfaces()) {
                for (a in ni.inetAddresses) {
                    if (!a.isLoopbackAddress && a.address.size == 4) a.hostAddress?.let { h.add(it) }
                }
            }
        } catch (e: Exception) { }
        return h
    }

    private fun send(cmd: Int, a0: Int, a1: Int, data: ByteArray = ByteArray(0)) {
        var sum = 0
        for (b in data) sum += (b.toInt() and 0xff)
        val bb = ByteBuffer.allocate(24 + data.size).order(ByteOrder.LITTLE_ENDIAN)
        bb.putInt(cmd).putInt(a0).putInt(a1).putInt(data.size).putInt(sum).putInt(cmd.inv())
        bb.put(data)
        val o = sock.getOutputStream()
        o.write(bb.array())
        o.flush()
    }

    private fun recv(): Msg {
        val h = ByteArray(24)
        input.readFully(h)
        val bb = ByteBuffer.wrap(h).order(ByteOrder.LITTLE_ENDIAN)
        val cmd = bb.int
        val a0 = bb.int
        val a1 = bb.int
        val len = bb.int
        if (len < 0 || len > 4 * 1024 * 1024) throw java.io.IOException("bad ADB message")
        val data = ByteArray(len)
        if (len > 0) input.readFully(data)
        return Msg(cmd, a0, a1, data)
    }

    // ── auth ──

    private fun keys(): KeyPair {
        val pk = File(dir, "adbkey.pk8")
        val pub = File(dir, "adbkey.pub")
        if (pk.exists() && pub.exists()) {
            try {
                val kf = KeyFactory.getInstance("RSA")
                return KeyPair(
                    kf.generatePublic(X509EncodedKeySpec(pub.readBytes())),
                    kf.generatePrivate(PKCS8EncodedKeySpec(pk.readBytes()))
                )
            } catch (e: Exception) { }
        }
        val g = KeyPairGenerator.getInstance("RSA")
        g.initialize(2048)
        val kp = g.generateKeyPair()
        pk.writeBytes(kp.private.encoded)
        pub.writeBytes(kp.public.encoded)
        return kp
    }

    private fun sign(token: ByteArray, kp: KeyPair): ByteArray {
        // adb signs the 20-byte token as if it were a SHA-1 digest
        val prefix = byteArrayOf(
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14
        )
        val s = Signature.getInstance("NONEwithRSA")
        s.initSign(kp.private)
        s.update(prefix + token)
        return s.sign()
    }

    /** Android's "mincrypt" RSA public key blob, base64, as adbd expects. */
    private fun publicKeyText(k: RSAPublicKey): ByteArray {
        val n = k.modulus
        val r32 = BigInteger.ONE.shiftLeft(32)
        val n0inv = r32.subtract(n.mod(r32).modInverse(r32)).toInt()
        val rr = BigInteger.ONE.shiftLeft(4096).mod(n)
        val bb = ByteBuffer.allocate(4 + 4 + 256 + 256 + 4).order(ByteOrder.LITTLE_ENDIAN)
        bb.putInt(64)
        bb.putInt(n0inv)
        for (i in 0 until 64) bb.putInt(n.shiftRight(32 * i).toInt())
        for (i in 0 until 64) bb.putInt(rr.shiftRight(32 * i).toInt())
        bb.putInt(k.publicExponent.toInt())
        val b64 = Base64.encodeToString(bb.array(), Base64.NO_WRAP)
        return (b64 + " leclair@home\u0000").toByteArray()
    }

    private fun handshake(kp: KeyPair) {
        log("Sending hello")
        send(CNXN, VERSION, MAXDATA, "host::\u0000".toByteArray())
        var signed = false
        var keySent = false
        while (true) {
            val m = try { recv() } catch (e: java.io.EOFException) {
                log("Stick hung up during sign-in (signed=$signed, keySent=$keySent)")
                throw e
            }
            log("Got " + String(byteArrayOf(m.cmd.toByte(), (m.cmd shr 8).toByte(), (m.cmd shr 16).toByte(), (m.cmd shr 24).toByte())) + " " + m.arg0)
            if (m.cmd == CNXN) return
            if (m.cmd == AUTH && m.arg0 == 1) {
                if (!signed) {
                    signed = true
                    log("Signing in with this app's key")
                    send(AUTH, 2, 0, sign(m.data, kp))
                } else if (!keySent) {
                    keySent = true
                    log("Look at the TV and choose Always allow.")
                    sock.soTimeout = 90000
                    send(AUTH, 3, 0, publicKeyText(kp.public as RSAPublicKey))
                } else {
                    throw java.io.IOException("Authorization was declined on the TV")
                }
            }
        }
    }

    // ── shell ──

    private fun shell(cmd: String): String {
        val local = nextId++
        send(OPEN, local, 0, "shell:$cmd\u0000".toByteArray())
        val sb = StringBuilder()
        while (true) {
            val m = recv()
            if (m.arg1 != local && m.cmd != CLSE) continue
            when (m.cmd) {
                WRTE -> {
                    sb.append(String(m.data))
                    send(OKAY, local, m.arg0)
                }
                CLSE -> return sb.toString()
            }
        }
    }
}
