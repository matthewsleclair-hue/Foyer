package com.leclair.leclair_home

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Log
import java.io.File

/**
 * Games on the TV: the Games folder (Foyer/Games on the TV's storage, where other apps can
 * read it too) and opening a game in RetroArch or Dolphin. Both need "all files" access to
 * read that folder; Foyer gives it to itself and to them over the TV's debugging link.
 */
object Games {
    private const val TAG = "FoyerGames"
    private val RETROARCH = listOf("com.retroarch.aarch64", "com.retroarch", "com.retroarch.ra32")
    private val DOLPHIN = listOf("org.dolphinemu.dolphinemu", "org.dolphinemu.dolphinemu.debug")
    private val granted = HashSet<String>()

    private fun installed(c: Context, pkg: String) = try {
        c.packageManager.getPackageInfo(pkg, 0); true
    } catch (e: Exception) { false }

    /** Lets an app (Foyer, RetroArch, Dolphin) read the shared Games folder. Background thread. */
    private fun allowFiles(c: Context, pkg: String) {
        if (Build.VERSION.SDK_INT < 30 || !granted.add(pkg)) return
        try {
            LocalAdb(c.filesDir) { }.run(
                listOf(
                    "appops set $pkg MANAGE_EXTERNAL_STORAGE allow",
                    "pm grant $pkg android.permission.READ_EXTERNAL_STORAGE",
                )
            )
        } catch (e: Exception) {
            granted.remove(pkg)
            Log.d(TAG, "couldn't give $pkg file access: $e")
        }
    }

    /** The Games folder, made if needed. Null if Foyer can't write there. Background thread. */
    fun dir(c: Context): String? {
        if (Build.VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager()) allowFiles(c, c.packageName)
        @Suppress("DEPRECATION")
        val d = File(Environment.getExternalStorageDirectory(), "Foyer/Games")
        try { d.mkdirs() } catch (e: Exception) { }
        return if (d.isDirectory && d.canWrite()) d.absolutePath else null
    }

    fun status(c: Context): Map<String, Any> = mapOf(
        "retroarch" to RETROARCH.any { installed(c, it) },
        "dolphin" to DOLPHIN.any { installed(c, it) },
    )

    /** "ok", "missing:retroarch", "missing:dolphin" or "error". Background thread. */
    fun launch(c: Context, path: String, system: String, core: String): String {
        try {
            if (system == "gc") {
                val pkg = DOLPHIN.firstOrNull { installed(c, it) } ?: return "missing:dolphin"
                allowFiles(c, pkg)
                c.startActivity(
                    Intent(Intent.ACTION_MAIN)
                        .setClassName(pkg, "org.dolphinemu.dolphinemu.ui.main.MainActivity")
                        .putExtra("AutoStartFile", path)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                )
                return "ok"
            }
            val pkg = RETROARCH.firstOrNull { installed(c, it) } ?: return "missing:retroarch"
            allowFiles(c, pkg)
            // RetroArch's own way of being told what to play (the same one other launchers use)
            val coreFile = if (core == "mupen64plus_next") "mupen64plus_next_gles3" else core
            @Suppress("DEPRECATION")
            val sd = Environment.getExternalStorageDirectory().absolutePath
            val i = Intent(Intent.ACTION_MAIN)
                .setClassName(pkg, "com.retroarch.browser.retroactivity.RetroActivityFuture")
                .putExtra("ROM", path)
                .putExtra("LIBRETRO", "/data/data/$pkg/cores/${coreFile}_libretro_android.so")
                .putExtra("CONFIGFILE", "$sd/Android/data/$pkg/files/retroarch.cfg")
                .putExtra("IME", Settings.Secure.getString(c.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD))
                .putExtra("DATADIR", "/data/data/$pkg")
                .putExtra("APK", c.packageManager.getApplicationInfo(pkg, 0).sourceDir)
                .putExtra("SDCARD", sd)
                .putExtra("EXTERNAL", "$sd/Android/data/$pkg/files")
                .putExtra("QUITFOCUS", "")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            c.startActivity(i)
            return "ok"
        } catch (e: Exception) {
            Log.d(TAG, "couldn't start the game: $e")
            return "error"
        }
    }
}
