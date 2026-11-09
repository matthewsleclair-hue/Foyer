package com.leclair.leclair_home

import android.Manifest
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

class MainActivity : FlutterActivity() {
    private val prefs by lazy { getSharedPreferences("leclair_home", Context.MODE_PRIVATE) }
    private val service by lazy { ComponentName(this, HomeKeyService::class.java) }
    private var channel: MethodChannel? = null
    private var pendingStorage: MethodChannel.Result? = null

    private val backupName = "Foyer-backup.json"
    private val imageExt = setOf("jpg", "jpeg", "png", "webp")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "leclair/launcher")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getApps" -> {
                    val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                    Thread {
                        val apps = pkgs.mapNotNull { info(it) }
                        runOnUiThread { result.success(apps) }
                    }.start()
                }
                "listApps" -> Thread {
                    val apps = listApps()
                    runOnUiThread { result.success(apps) }
                }.start()
                "launch" -> result.success(launch(call.argument<String>("package")))
                "loadSettings" -> result.success(
                    mapOf(
                        "json" to (prefs.getString("json", "") ?: ""),
                        // settings saved by older versions
                        "setupDone" to prefs.getBoolean("setupDone", false),
                        "name" to (prefs.getString("name", "Home") ?: "Home"),
                        "liquid" to prefs.getBoolean("liquid", false),
                        "clock24" to prefs.getBoolean("clock24", false),
                        "pinned" to (prefs.getString("pinned", "") ?: ""),
                        "plexToken" to (prefs.getString("plexToken", "") ?: ""),
                        "plexUrl" to (prefs.getString("plexUrl", "") ?: ""),
                        "plexName" to (prefs.getString("plexName", "") ?: ""),
                        "clientId" to (prefs.getString("clientId", "") ?: "")
                    )
                )
                "saveSettings" -> {
                    prefs.edit().putString("json", call.argument<String>("json") ?: "").apply()
                    result.success(true)
                }
                "homeKeyStatus" -> result.success(
                    mapOf("enabled" to homeKeyEnabled(), "canEnable" to canWriteSecure())
                )
                "setHomeKey" -> result.success(setHomeKey(call.argument<Boolean>("enabled") ?: false))
                "requestStorage" -> requestStorage(result)
                "listWallpapers" -> Thread {
                    val m = listWallpapers()
                    runOnUiThread { result.success(m) }
                }.start()
                "exportBackup" -> {
                    val json = call.arguments as? String
                    if (json == null) result.success(emptyList<String>())
                    else Thread {
                        val r = exportBackup(json)
                        runOnUiThread { result.success(r) }
                    }.start()
                }
                "importBackup" -> Thread {
                    val r = importBackup()
                    runOnUiThread { result.success(r) }
                }.start()
                "saveReport" -> {
                    val text = call.arguments as? String ?: ""
                    Thread {
                        val r = writeShared("Foyer-report.txt", text)
                        runOnUiThread { result.success(r) }
                    }.start()
                }
                "readTokenFile" -> Thread {
                    val t = readTokenFile()
                    runOnUiThread { result.success(t) }
                }.start()
                "appVersion" -> result.success(mapOf("name" to versionName(), "code" to versionCode()))
                "updatePath" -> result.success(File(appDir(), "update.apk").absolutePath)
                "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
                "appInfo" -> result.success(appInfo(call.argument<String>("package")))
                "uninstall" -> result.success(uninstall(call.argument<String>("package")))
                "killApp" -> result.success(killApp(call.argument<String>("package")))
                "diagnostics" -> {
                    val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                    Thread {
                        val r = diagnostics(pkgs)
                        runOnUiThread { result.success(r) }
                    }.start()
                }
                "adbRun" -> {
                    val cmds = call.argument<List<String>>("commands") ?: emptyList()
                    Thread {
                        val out: Map<String, Any?> = try {
                            LocalAdb(filesDir) { line -> runOnUiThread { ch.invokeMethod("adbLog", line) } }.run(cmds)
                            mapOf("ok" to true)
                        } catch (e: Exception) {
                            mapOf("ok" to false, "error" to "${e.javaClass.simpleName}: ${e.message}")
                        }
                        runOnUiThread { result.success(out) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── storage, wallpapers, backup ──

    private fun hasStorage(): Boolean =
        Build.VERSION.SDK_INT < 23 ||
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    private fun requestStorage(result: MethodChannel.Result) {
        if (hasStorage() || Build.VERSION.SDK_INT >= 33) {
            result.success(true)
            return
        }
        pendingStorage?.success(false)
        pendingStorage = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE),
            4711
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4711) {
            pendingStorage?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingStorage = null
        }
    }

    private fun appDir(sub: String? = null): File {
        val base = getExternalFilesDir(sub) ?: File(filesDir, sub ?: "")
        base.mkdirs()
        return base
    }

    private fun scanImages(dir: File, depth: Int, out: MutableList<File>) {
        val list = try { dir.listFiles() } catch (e: Exception) { null } ?: return
        for (f in list) {
            if (f.isDirectory) {
                if (depth > 0 && !f.name.startsWith(".")) scanImages(f, depth - 1, out)
            } else if (f.extension.lowercase() in imageExt && f.length() in 20_000..30_000_000) {
                out.add(f)
            }
        }
    }

    private fun listWallpapers(): Map<String, Any> {
        val found = ArrayList<File>()
        val own = appDir("wallpapers")
        scanImages(own, 1, found)
        if (hasStorage()) {
            @Suppress("DEPRECATION")
            val ext = Environment.getExternalStorageDirectory()
            for (d in listOf(
                File(ext, "Pictures"), File(ext, "DCIM"), File(ext, "Download"), File(ext, "Wallpapers")
            )) scanImages(d, 2, found)
        }
        val files = found.distinctBy { it.absolutePath }
            .sortedByDescending { it.lastModified() }
            .take(60)
            .map { it.absolutePath }
        return mapOf("dir" to own.absolutePath, "files" to files)
    }

    private fun backupTargets(): List<File> {
        val out = ArrayList<File>()
        out.add(File(appDir(), backupName))
        if (hasStorage()) {
            try {
                @Suppress("DEPRECATION")
                val dl = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                dl.mkdirs()
                out.add(File(dl, backupName))
            } catch (e: Exception) { }
        }
        return out
    }

    private fun exportBackup(json: String): List<String> {
        val written = ArrayList<String>()
        for (f in backupTargets()) {
            try {
                f.writeText(json)
                written.add(f.absolutePath)
            } catch (e: Exception) { }
        }
        return written
    }

    private fun importBackup(): Map<String, Any>? {
        val best = backupTargets().filter { it.isFile && it.length() > 0 }
            .maxByOrNull { it.lastModified() } ?: return null
        return try {
            mapOf("json" to best.readText(), "path" to best.absolutePath)
        } catch (e: Exception) { null }
    }

    private fun writeShared(name: String, text: String): List<String> {
        val written = ArrayList<String>()
        val dirs = ArrayList<File>()
        dirs.add(appDir())
        if (hasStorage()) {
            try {
                @Suppress("DEPRECATION")
                val dl = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                dl.mkdirs()
                dirs.add(dl)
            } catch (e: Exception) { }
        }
        for (d in dirs) {
            try {
                val f = File(d, name)
                f.writeText(text)
                written.add(f.absolutePath)
            } catch (e: Exception) { }
        }
        return written
    }

    /** Reads (then deletes) foyer-token.txt from the app folder or Download. */
    private fun readTokenFile(): String? {
        val files = ArrayList<File>()
        files.add(File(appDir(), "foyer-token.txt"))
        if (hasStorage()) {
            try {
                @Suppress("DEPRECATION")
                files.add(File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "foyer-token.txt"))
            } catch (e: Exception) { }
        }
        for (f in files) {
            try {
                if (f.isFile && f.length() in 1..2000) {
                    val t = f.readText().trim()
                    try { f.delete() } catch (e: Exception) { }
                    if (t.isNotEmpty()) return t
                }
            } catch (e: Exception) { }
        }
        return null
    }

    // ── version, app options, updates ──

    private fun versionName(): String = try {
        packageManager.getPackageInfo(packageName, 0).versionName ?: "?"
    } catch (e: Exception) { "?" }

    @Suppress("DEPRECATION")
    private fun versionCode(): Long = try {
        val pi = packageManager.getPackageInfo(packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
    } catch (e: Exception) { 0L }

    private fun appInfo(pkg: String?): Boolean {
        if (pkg == null) return false
        return try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (e: Exception) { false }
    }

    private fun uninstall(pkg: String?): Boolean {
        if (pkg == null) return false
        return try {
            startActivity(
                Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (e: Exception) { false }
    }

    private fun killApp(pkg: String?): Boolean {
        if (pkg == null) return false
        return try {
            (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).killBackgroundProcesses(pkg)
            true
        } catch (e: Exception) { false }
    }

    private fun installApk(path: String): String {
        val f = File(path)
        if (!f.exists() || f.length() == 0L) return "error"
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (e: Exception) { }
            return "needsPermission"
        }
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            "started"
        } catch (e: Exception) { "error" }
    }

    // ── tune-up diagnostics ──

    private fun diagnostics(pkgs: List<String>): Map<String, Any> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        val states = HashMap<String, Int>()
        for (p in pkgs) {
            states[p] = try {
                if (packageManager.getApplicationInfo(p, 0).enabled) 1 else 2
            } catch (e: Exception) { 0 }
        }
        val freeMb = try {
            val st = StatFs(filesDir.absolutePath)
            st.availableBytes / (1024 * 1024)
        } catch (e: Exception) { 0L }
        val adbEnabled = try {
            Settings.Global.getInt(contentResolver, Settings.Global.ADB_ENABLED, 0) == 1
        } catch (e: Exception) { false }
        val port = try {
            Socket().use { it.connect(InetSocketAddress("127.0.0.1", 5555), 600); true }
        } catch (e: Exception) { false }
        return mapOf(
            "version" to "${versionName()} (${versionCode()})",
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "ramTotalMb" to (mi.totalMem / (1024 * 1024)).toInt(),
            "ramFreeMb" to (mi.availMem / (1024 * 1024)).toInt(),
            "storageFreeMb" to freeMb.toInt(),
            "adbEnabled" to adbEnabled,
            "adbPort" to port,
            "homeKey" to homeKeyEnabled(),
            "states" to states
        )
    }

    // ── Home button service ──

    private fun enabledServices(): List<String> =
        (Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: "")
            .split(':').filter { it.isNotBlank() }

    private fun isOurs(s: String) = ComponentName.unflattenFromString(s) == service

    private fun homeKeyEnabled(): Boolean = enabledServices().any { isOurs(it) }

    private fun canWriteSecure(): Boolean =
        checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    private fun setHomeKey(on: Boolean): Boolean {
        if (!canWriteSecure()) return false
        val others = enabledServices().filter { !isOurs(it) }
        val list = if (on) others + service.flattenToString() else others
        Settings.Secure.putString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, list.joinToString(":"))
        if (on) Settings.Secure.putInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
        return true
    }

    // ── apps ──

    private fun launchIntent(pkg: String): Intent? =
        packageManager.getLeanbackLaunchIntentForPackage(pkg)
            ?: packageManager.getLaunchIntentForPackage(pkg)

    /** Every launchable app (except this one), with a small icon, sorted by name. */
    private fun listApps(): List<Map<String, Any>> {
        val pm = packageManager
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, Any>>()
        for (cat in listOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER)) {
            val i = Intent(Intent.ACTION_MAIN).addCategory(cat)
            for (ri in pm.queryIntentActivities(i, 0)) {
                val pkg = ri.activityInfo.packageName
                if (pkg == packageName || !seen.add(pkg)) continue
                try {
                    out.add(
                        mapOf(
                            "package" to pkg,
                            "label" to ri.loadLabel(pm).toString(),
                            "icon" to png(render(ri.loadIcon(pm), 96, 96))
                        )
                    )
                } catch (e: Exception) { }
            }
        }
        return out.sortedBy { (it["label"] as String).lowercase() }
    }

    private fun info(pkg: String): Map<String, Any>? {
        val intent = launchIntent(pkg) ?: return null
        return try {
            val pm = packageManager
            val label = pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            // Prefer the 16:9 TV banner; fall back to the icon.
            val banner: Drawable? = try {
                pm.getActivityBanner(intent) ?: pm.getApplicationBanner(pkg)
            } catch (e: Exception) { null }
            val wide = banner != null
            val bmp = if (wide) render(banner!!, 480, 270) else render(pm.getApplicationIcon(pkg), 256, 256)
            mapOf(
                "package" to pkg,
                "label" to label,
                "image" to png(bmp),
                "wide" to wide,
                "color" to dominant(bmp)
            )
        } catch (e: Exception) { null }
    }

    private fun launch(pkg: String?): Boolean {
        val i = pkg?.let { launchIntent(it) } ?: return false
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(i)
        return true
    }

    private fun render(d: Drawable, w: Int, h: Int): Bitmap {
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, w, h)
        d.draw(Canvas(b))
        return b
    }

    private fun png(b: Bitmap): ByteArray {
        val o = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.PNG, 100, o)
        return o.toByteArray()
    }

    /** Average color of the artwork, weighted toward vivid pixels. */
    private fun dominant(b: Bitmap): Int {
        val s = Bitmap.createScaledBitmap(b, 16, 16, true)
        val hsv = FloatArray(3)
        var r = 0.0; var g = 0.0; var bl = 0.0; var wsum = 0.0
        for (x in 0 until 16) for (y in 0 until 16) {
            val p = s.getPixel(x, y)
            if (Color.alpha(p) < 128) continue
            Color.colorToHSV(p, hsv)
            val w = (hsv[1] * hsv[2]).toDouble() + 0.02
            r += Color.red(p) * w; g += Color.green(p) * w; bl += Color.blue(p) * w; wsum += w
        }
        if (wsum == 0.0) return 0xFF3B5BDB.toInt()
        return Color.rgb((r / wsum).toInt(), (g / wsum).toInt(), (bl / wsum).toInt())
    }
}
