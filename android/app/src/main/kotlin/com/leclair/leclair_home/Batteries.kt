package com.leclair.leclair_home

import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothManager
import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.view.InputDevice
import kotlin.math.roundToInt

/** Battery levels of the remote, game controllers and other Bluetooth things, for the
 *  low-battery note and the Bluetooth page. Whatever reports a level; others are skipped. */
object Batteries {
    fun read(c: Context): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()
        // 1. input devices that report a battery (Android 12+): remotes, DualSense, Xbox pads
        if (Build.VERSION.SDK_INT >= 31) {
            try {
                val im = c.getSystemService(Context.INPUT_SERVICE) as InputManager
                for (id in im.inputDeviceIds) {
                    val d = im.getInputDevice(id) ?: continue
                    if (d.isVirtual || !d.isExternal) continue
                    val b = d.batteryState
                    if (!b.isPresent) continue
                    val cap = b.capacity
                    if (cap.isNaN() || cap < 0f) continue
                    val name = d.name ?: continue
                    if (!seen.add(name.lowercase())) continue
                    val pad = (d.sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
                        (d.sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
                    out.add(mapOf("name" to name, "level" to (cap * 100f).roundToInt(), "kind" to if (pad) "controller" else "remote"))
                }
            } catch (_: Exception) { }
        }
        // 2. paired Bluetooth devices that share their level (headphones, some remotes)
        try {
            val bm = c.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            for (d in bm.adapter?.bondedDevices ?: emptySet()) {
                val level = try { d.javaClass.getMethod("getBatteryLevel").invoke(d) as Int } catch (_: Exception) { -1 }
                if (level < 0) continue
                val on = try { d.javaClass.getMethod("isConnected").invoke(d) as Boolean } catch (_: Exception) { true }
                if (!on) continue
                val name = d.name ?: continue
                if (!seen.add(name.lowercase())) continue
                val major = try { d.bluetoothClass?.majorDeviceClass ?: -1 } catch (_: Exception) { -1 }
                val kind = when (major) {
                    BluetoothClass.Device.Major.AUDIO_VIDEO -> "headphones"
                    BluetoothClass.Device.Major.PERIPHERAL -> "remote"
                    else -> "other"
                }
                out.add(mapOf("name" to name, "level" to level.coerceIn(0, 100), "kind" to kind))
            }
        } catch (_: Exception) { }
        return out
    }
}
