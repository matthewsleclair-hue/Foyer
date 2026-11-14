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

    private fun corePath(pkg: String, core: String): String {
        val f = if (core == "mupen64plus_next") "mupen64plus_next_gles3" else core
        return "/data/data/$pkg/cores/${f}_libretro_android.so"
    }

    @Suppress("DEPRECATION")
    private fun configPath(pkg: String) =
        "${Environment.getExternalStorageDirectory().absolutePath}/Android/data/$pkg/files/retroarch.cfg"

    private fun q(s: String) = "'" + s.replace("'", "'\\''") + "'"

    /** The launch, as a shell command: force-stop, then the game, core and settings file. */
    private fun retroArchCommand(pkg: String, path: String, core: String) =
        "am start -S -a android.intent.action.VIEW -n $pkg/com.retroarch.browser.retroactivity.RetroActivityFuture" +
            " --es ROM ${q(path)} --es LIBRETRO ${q(corePath(pkg, core))} --es CONFIGFILE ${q(configPath(pkg))}" +
            " --es QUITFOCUS '' -f 0x10008000"

    private fun retroArchIntent(pkg: String, path: String, core: String) =
        Intent(Intent.ACTION_VIEW)
            .setClassName(pkg, "com.retroarch.browser.retroactivity.RetroActivityFuture")
            .putExtra("ROM", path)
            .putExtra("LIBRETRO", corePath(pkg, core))
            .putExtra("CONFIGFILE", configPath(pkg))
            .putExtra("QUITFOCUS", "")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)

    /**
     * Games settings > Check that games work: starts a game the same way, waits, then collects
     * what RetroArch and Android said about it, so a problem can be seen (and fixed).
     * Background thread; takes about 15 seconds.
     */
    fun diagnose(c: Context, path: String, core: String): String {
        val pkg = RETROARCH.firstOrNull { installed(c, it) } ?: return "RetroArch isn't installed."
        allowFiles(c, pkg)
        val path = stage(c, pkg, path)
        val sb = StringBuilder()
        fun section(t: String, s: String) { sb.append("── ").append(t).append(" ──\n").append(s.trim()).append("\n\n") }
        try {
            val adb = LocalAdb(c.filesDir) { }
            adb.run(
                listOf(
                    "dumpsys package $pkg | grep -E 'versionName|targetSdk|MANAGE_EXTERNAL_STORAGE|READ_EXTERNAL_STORAGE' | head -8",
                    "appops get $pkg MANAGE_EXTERNAL_STORAGE",
                    "ls -la ${q(path)}",
                    "ls -la ${q(configPath(pkg))}",
                    "logcat -c",
                    retroArchCommand(pkg, path, core),
                )
            )
            val o = adb.outputs
            section("RetroArch", "$pkg\n${o.getOrElse(0) { "" }}")
            section("All files access", o.getOrElse(1) { "" })
            section("The game file", o.getOrElse(2) { "" })
            section("RetroArch settings file", o.getOrElse(3) { "" })
            section("Starting it", o.getOrElse(5) { "" })
            Thread.sleep(9000)
            val adb2 = LocalAdb(c.filesDir) { }
            adb2.run(
                listOf(
                    "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' | head -3",
                    "logcat -d -v brief | grep -iE 'retroarch|libretro|RetroActivity|ANR|FATAL|mgba|core' | tail -60",
                )
            )
            section("On screen after 9 seconds", adb2.outputs.getOrElse(0) { "" })
            section("What RetroArch said", adb2.outputs.getOrElse(1) { "" })
        } catch (e: Exception) {
            section("Couldn't check", "The TV's debugging link isn't working: $e")
        }
        val report = sb.toString()
        try {
            @Suppress("DEPRECATION")
            File(Environment.getExternalStorageDirectory(), "Foyer/Games/retroarch-check.txt").writeText(report)
        } catch (_: Exception) { }
        // back to Foyer to show what was found
        try {
            c.startActivity(Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
        } catch (_: Exception) { }
        return report
    }

    /**
     * RetroArch from the Play Store isn't allowed to read other folders on the TV (Android's
     * storage rules; it has no "all files" access), so it froze trying to open a game in
     * Foyer/Games. It can always read its own media folder, and Foyer can write there, so the
     * game is copied in first (once; a game that's already there is reused).
     */
    private fun stage(c: Context, pkg: String, path: String): String {
        val src = File(path)
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStorageDirectory(), "Android/media/$pkg/Foyer")
        val dest = File(dir, src.name)
        try {
            if (dest.exists() && dest.length() == src.length()) return dest.absolutePath
            dir.mkdirs()
            src.copyTo(dest, overwrite = true)
            // keep the newest 12 copies; the games themselves stay in Foyer/Games
            dir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(12)?.forEach { it.delete() }
            return dest.absolutePath
        } catch (e: Exception) {
            Log.d(TAG, "couldn't copy the game for RetroArch: $e")
        }
        // the debugging link's shell can write there too
        try {
            LocalAdb(c.filesDir) { }.run(listOf("mkdir -p ${q(dir.absolutePath)} && cp ${q(path)} ${q(dest.absolutePath)}"))
            if (dest.exists()) return dest.absolutePath
        } catch (_: Exception) { }
        return path
    }

    /** Closes an emulator that's still open from before. Background thread. */
    private fun stop(c: Context, pkg: String) {
        try {
            LocalAdb(c.filesDir) { }.run(listOf("am force-stop $pkg"))
        } catch (e: Exception) {
            try {
                (c.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager).killBackgroundProcesses(pkg)
            } catch (_: Exception) { }
        }
        Thread.sleep(400)
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
                stop(c, pkg)
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
            val path = stage(c, pkg, path)
            // Started over the TV's debugging link with "am start -S": RetroArch is closed first
            // (it freezes if it's asked to switch games while open), and this is the exact way
            // other game launchers (ES-DE, Daijisho) hand RetroArch a game.
            try {
                val adb = LocalAdb(c.filesDir) { }
                adb.run(listOf(retroArchCommand(pkg, path, core)))
                val out = adb.outputs.firstOrNull() ?: ""
                if (!out.contains("Error", ignoreCase = true)) return "ok"
                Log.d(TAG, "am start said: $out")
            } catch (e: Exception) {
                Log.d(TAG, "debugging link unavailable, starting RetroArch directly: $e")
            }
            stop(c, pkg)
            c.startActivity(retroArchIntent(pkg, path, core))
            return "ok"
        } catch (e: Exception) {
            Log.d(TAG, "couldn't start the game: $e")
            return "error"
        }
    }
}
