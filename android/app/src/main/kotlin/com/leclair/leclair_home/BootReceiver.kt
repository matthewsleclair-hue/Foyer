package com.leclair.leclair_home

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

/** Opens Foyer when the stick finishes starting up (if "Start on boot" is on). */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action
        if (a != Intent.ACTION_BOOT_COMPLETED && a != "android.intent.action.QUICKBOOT_POWERON") return
        val raw = context.getSharedPreferences("leclair_home", Context.MODE_PRIVATE)
            .getString("json", "") ?: ""
        val on = try { if (raw.isEmpty()) true else JSONObject(raw).optBoolean("autoStart", true) } catch (e: Exception) { true }
        if (!on) return
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            )
        } catch (e: Exception) { }
    }
}
