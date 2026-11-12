package com.leclair.leclair_home

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface

/**
 * The TV's own settings, shown inside Foyer (channel "leclair/system").
 * Things an app may do itself live here; things that need more rights go
 * through on-device ADB from the Dart side.
 */
class TvSystem(private val act: Activity, private val ch: MethodChannel) {
    private val audio by lazy { act.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val bt: BluetoothAdapter? by lazy {
        (act.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    }
    private var finder: BroadcastReceiver? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "info" -> result.success(info())
                "volume" -> result.success(volume())
                "setVolume" -> {
                    val v = call.argument<Int>("level") ?: 0
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, v, AudioManager.FLAG_SHOW_UI)
                    result.success(volume())
                }
                "stepVolume" -> {
                    val up = call.argument<Boolean>("up") ?: true
                    audio.adjustStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                        AudioManager.FLAG_SHOW_UI
                    )
                    result.success(volume())
                }
                "mute" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    audio.adjustStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        if (on) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE,
                        AudioManager.FLAG_SHOW_UI
                    )
                    result.success(volume())
                }
                "displayModes" -> result.success(displayModes())
                "btState" -> result.success(btState())
                "btScan" -> result.success(btScan())
                "btStop" -> { btStop(); result.success(true) }
                "btPair" -> result.success(btPair(call.argument<String>("address") ?: ""))
                "btForget" -> result.success(btForget(call.argument<String>("address") ?: ""))
                "openPage" -> result.success(openPage(call.argument<String>("page") ?: ""))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("system", "${e.javaClass.simpleName}: ${e.message}", null)
        }
    }

    fun stop() = btStop()

    // ── about ──

    private fun info(): Map<String, Any?> {
        val cr = act.contentResolver
        val stat = StatFs(Environment.getDataDirectory().path)
        val mem = ActivityManager.MemoryInfo()
        (act.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mem)
        val cm = act.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        var link = "none"
        try {
            val caps = if (Build.VERSION.SDK_INT >= 23) cm.getNetworkCapabilities(cm.activeNetwork) else null
            link = when {
                caps == null -> "none"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                else -> "other"
            }
        } catch (e: Exception) { }
        val ips = ArrayList<String>()
        try {
            for (ni in NetworkInterface.getNetworkInterfaces()) {
                if (!ni.isUp || ni.isLoopback) continue
                for (a in ni.inetAddresses) {
                    val h = a.hostAddress ?: continue
                    if (!h.contains(':')) ips.add(h)
                }
            }
        } catch (e: Exception) { }
        var name = Settings.Global.getString(cr, "device_name")
        if (name.isNullOrBlank()) name = Build.MODEL
        return mapOf(
            "name" to name,
            "model" to (Build.MODEL ?: ""),
            "maker" to (Build.MANUFACTURER ?: ""),
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "security" to (if (Build.VERSION.SDK_INT >= 23) Build.VERSION.SECURITY_PATCH else ""),
            "storageFree" to stat.availableBytes,
            "storageTotal" to stat.totalBytes,
            "ramFree" to mem.availMem,
            "ramTotal" to mem.totalMem,
            "uptime" to SystemClock.elapsedRealtime(),
            "link" to link,
            "ips" to ips,
            "soundEffects" to (Settings.System.getInt(cr, Settings.System.SOUND_EFFECTS_ENABLED, 1) == 1),
            "screensaver" to (Settings.Secure.getInt(cr, "screensaver_enabled", 1) == 1),
            "screenOff" to Settings.System.getInt(cr, Settings.System.SCREEN_OFF_TIMEOUT, -1),
            "sleep" to Settings.Secure.getInt(cr, "sleep_timeout", -1),
            "devOptions" to (Settings.Global.getInt(cr, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1),
            "adbOn" to (Settings.Global.getInt(cr, Settings.Global.ADB_ENABLED, 0) == 1)
        )
    }

    // ── sound ──

    private fun volume(): Map<String, Any?> = mapOf(
        "level" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
        "max" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
        "fixed" to (Build.VERSION.SDK_INT >= 21 && audio.isVolumeFixed),
        "muted" to (Build.VERSION.SDK_INT >= 23 && audio.isStreamMute(AudioManager.STREAM_MUSIC))
    )

    // ── display ──

    @Suppress("DEPRECATION")
    private fun displayModes(): Map<String, Any?> {
        val d = act.windowManager.defaultDisplay
        if (Build.VERSION.SDK_INT < 23) return mapOf("modes" to emptyList<Any>())
        val cur = d.mode
        val modes = d.supportedModes.map {
            mapOf("id" to it.modeId, "w" to it.physicalWidth, "h" to it.physicalHeight, "hz" to it.refreshRate.toDouble())
        }
        var hdr = emptyList<Int>()
        try { hdr = d.hdrCapabilities?.supportedHdrTypes?.toList() ?: emptyList() } catch (e: Exception) { }
        return mapOf(
            "modes" to modes,
            "current" to mapOf("id" to cur.modeId, "w" to cur.physicalWidth, "h" to cur.physicalHeight, "hz" to cur.refreshRate.toDouble()),
            "hdr" to hdr
        )
    }

    // ── bluetooth ──

    private fun btAllowed(): Boolean =
        Build.VERSION.SDK_INT < 31 ||
            (act.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                act.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED)

    private fun kind(d: BluetoothDevice): String {
        val c = try { d.bluetoothClass?.majorDeviceClass } catch (e: SecurityException) { null } ?: return "other"
        return when (c) {
            0x0400 -> "audio"
            0x0500 -> "input"
            0x0200 -> "phone"
            0x0100 -> "computer"
            else -> "other"
        }
    }

    @SuppressLint("MissingPermission")
    private fun dev(d: BluetoothDevice): Map<String, Any?> = mapOf(
        "address" to d.address,
        "name" to (d.name ?: d.address),
        "kind" to kind(d),
        "paired" to (d.bondState == BluetoothDevice.BOND_BONDED)
    )

    @SuppressLint("MissingPermission")
    private fun btState(): Map<String, Any?> {
        val a = bt ?: return mapOf("present" to false)
        if (!btAllowed()) return mapOf("present" to true, "allowed" to false)
        return mapOf(
            "present" to true,
            "allowed" to true,
            "on" to a.isEnabled,
            "name" to a.name,
            "scanning" to a.isDiscovering,
            "paired" to a.bondedDevices.map { dev(it) }
        )
    }

    @SuppressLint("MissingPermission")
    private fun btScan(): Boolean {
        val a = bt ?: return false
        if (!btAllowed() || !a.isEnabled) return false
        if (finder == null) {
            val r = object : BroadcastReceiver() {
                @Suppress("DEPRECATION")
                override fun onReceive(c: Context, i: Intent) {
                    when (i.action) {
                        BluetoothDevice.ACTION_FOUND, BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                            val d: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33)
                                i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                            else i.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                            if (d != null) {
                                val m = HashMap(dev(d))
                                m["bond"] = d.bondState
                                ch.invokeMethod(if (i.action == BluetoothDevice.ACTION_FOUND) "btFound" else "btBond", m)
                            }
                        }
                        BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> ch.invokeMethod("btDone", null)
                    }
                }
            }
            val f = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            if (Build.VERSION.SDK_INT >= 33) act.registerReceiver(r, f, Context.RECEIVER_EXPORTED)
            else act.registerReceiver(r, f)
            finder = r
        }
        if (a.isDiscovering) a.cancelDiscovery()
        return a.startDiscovery()
    }

    @SuppressLint("MissingPermission")
    private fun btStop() {
        try { if (btAllowed()) bt?.cancelDiscovery() } catch (e: Exception) { }
        finder?.let { try { act.unregisterReceiver(it) } catch (e: Exception) { } }
        finder = null
    }

    @SuppressLint("MissingPermission")
    private fun btPair(address: String): Boolean {
        val a = bt ?: return false
        if (!btAllowed()) return false
        try { a.cancelDiscovery() } catch (e: Exception) { }
        return a.getRemoteDevice(address).createBond()
    }

    @SuppressLint("MissingPermission")
    private fun btForget(address: String): Boolean {
        val a = bt ?: return false
        if (!btAllowed()) return false
        return try {
            val d = a.getRemoteDevice(address)
            d.javaClass.getMethod("removeBond").invoke(d) as? Boolean ?: false
        } catch (e: Exception) { false }
    }

    // ── stock pages, for the few things Foyer can't do itself ──

    private fun openPage(page: String): Boolean {
        HomeKeyService.allowAmazonUntil = System.currentTimeMillis() + 300000
        val actions = when (page) {
            "wifi" -> listOf(Settings.ACTION_WIFI_SETTINGS)
            "bluetooth" -> listOf(Settings.ACTION_BLUETOOTH_SETTINGS)
            "display" -> listOf(Settings.ACTION_DISPLAY_SETTINGS)
            "sound" -> listOf(Settings.ACTION_SOUND_SETTINGS)
            "date" -> listOf(Settings.ACTION_DATE_SETTINGS)
            "accounts" -> listOf(Settings.ACTION_SYNC_SETTINGS, "android.settings.ACCOUNT_SYNC_SETTINGS")
            "privacy" -> listOf(Settings.ACTION_PRIVACY_SETTINGS)
            "keyboard" -> listOf(Settings.ACTION_INPUT_METHOD_SETTINGS)
            "accessibility" -> listOf(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "language" -> listOf(Settings.ACTION_LOCALE_SETTINGS)
            "update" -> listOf("android.settings.SYSTEM_UPDATE_SETTINGS", Settings.ACTION_DEVICE_INFO_SETTINGS)
            "apps" -> listOf(Settings.ACTION_APPLICATION_SETTINGS)
            "storage" -> listOf(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
            "about" -> listOf(Settings.ACTION_DEVICE_INFO_SETTINGS)
            else -> emptyList<String>()
        } + Settings.ACTION_SETTINGS
        for (a in actions) {
            try {
                act.startActivity(Intent(a).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: Exception) { }
        }
        return false
    }
}
