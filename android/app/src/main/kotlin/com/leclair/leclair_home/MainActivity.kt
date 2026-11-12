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
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import android.view.KeyEvent
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
    private var navChannel: MethodChannel? = null
    private var phoneChannel: MethodChannel? = null
    private val phoneInput = PhoneInput { text ->
        runOnUiThread { phoneChannel?.invokeMethod("text", text) }
    }
    private var pendingStorage: MethodChannel.Result? = null
    private var tvSystem: TvSystem? = null
    private var sounds: UiSounds? = null

    private val backupName = "Foyer-backup.json"
    private val imageExt = setOf("jpg", "jpeg", "png", "webp")

    override fun onCreate(savedInstanceState: Bundle?) {
        // safety net: if Foyer keeps crashing, the TV's own home takes over for a few minutes
        val stepAside = CrashGuard.onStart(this)
        super.onCreate(savedInstanceState)
        if (stepAside) finish()
    }

    override fun onDestroy() {
        phoneInput.stop()
        tvSystem?.stop()
        sounds?.release()
        sounds = null
        if (DropRemote.activity === this) {
            DropRemote.activity = null
            DropRemote.activityResumed = false
        }
        super.onDestroy()
    }

    override fun onPause() {
        DropRemote.activityResumed = false
        super.onPause()
    }

    /** Home pressed on the phone page's remote while Foyer is already on screen. */
    fun goHomeFromRemote() {
        navChannel?.invokeMethod("goHome", null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Home pressed while Foyer is already open (Google TV sends it straight here,
        // the Fire TV helper adds "goHome"): close settings and menus, show the home screen.
        val homeKey = intent.action == Intent.ACTION_MAIN && intent.hasCategory(Intent.CATEGORY_HOME)
        if (homeKey || intent.getBooleanExtra("goHome", false)) navChannel?.invokeMethod("goHome", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "leclair/launcher")
        channel = ch
        navChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "leclair/nav")
        // load the sounds now so the first one plays on time
        try { if (sounds == null) sounds = UiSounds(this) } catch (e: Exception) { }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "leclair/sound").setMethodCallHandler { call, result ->
            if (call.method == "play") {
                try {
                    val s = sounds ?: UiSounds(this).also { sounds = it }
                    s.play(call.argument<String>("name") ?: "", call.argument<Double>("volume") ?: 0.5)
                } catch (e: Exception) { }
            }
            result.success(null)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "leclair/system").also { sc ->
            val sys = TvSystem(this, sc)
            tvSystem = sys
            sc.setMethodCallHandler { call, result -> sys.handle(call, result) }
        }
        phoneChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "leclair/phone").also { pc ->
            pc.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(
                        phoneInput.start(call.argument<String>("title") ?: "", call.argument<String>("hint") ?: "")
                    )
                    "stop" -> { phoneInput.stop(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
        }
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
                "openUrl" -> result.success(openUrl(call.argument<String>("url")))
                "openLink" -> result.success(
                    try {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url") ?: ""))
                                .setPackage(call.argument<String>("package"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        true
                    } catch (e: Exception) { false }
                )
                "dropConfig" -> {
                    DropRemote.configure(
                        this, call.argument<String>("url") ?: "", call.argument<String>("token") ?: ""
                    )
                    result.success(true)
                }
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
                    RemoteKeys.reload(this)
                    result.success(true)
                }
                "learnKey" -> {
                    if (!HomeKeyService.running) {
                        result.success(mapOf("error" to "helper"))
                    } else {
                        var done = false
                        val timeout = Runnable {
                            if (!done) {
                                done = true
                                RemoteKeys.learn = null
                                result.success(mapOf("error" to "timeout"))
                            }
                        }
                        val h = android.os.Handler(mainLooper)
                        RemoteKeys.learn = { code ->
                            if (!done) {
                                done = true
                                h.removeCallbacks(timeout)
                                result.success(mapOf("code" to code, "name" to (KeyEvent.keyCodeToString(code) ?: "")))
                            }
                        }
                        h.postDelayed(timeout, 15000)
                    }
                }
                "sleepTimer" -> {
                    SleepTimer.start(this, call.argument<Int>("minutes") ?: 0)
                    result.success(SleepTimer.endAt)
                }
                "screenOff" -> result.success(ScreenOff.on(this))
                "watchNext" -> {
                    val max = call.argument<Int>("max") ?: 6
                    val skip = (call.argument<List<String>>("skip") ?: emptyList()).toSet()
                    Thread {
                        val r = WatchNext.list(this, max, skip)
                        runOnUiThread { result.success(r) }
                    }.start()
                }
                "openWatchNext" -> {
                    val id = (call.argument<Number>("id") ?: -1L).toLong()
                    result.success(WatchNext.open(this, id))
                }
                "tvOffSoon" -> {
                    // smart idle on the home screen: off in a minute, any button keeps it on
                    SleepTimer.start(this, 1, "Nobody's been watching: turning the TV off in 1 minute\nPress any button to keep it on")
                    result.success(SleepTimer.endAt)
                }
                "smartIdle" -> {
                    IdleWatch.configure(this, call.argument<Int>("pausedMinutes") ?: 0, call.argument<Boolean>("quiet") ?: false)
                    result.success(true)
                }
                "sleepStatus" -> {
                    SleepTimer.restore(this)
                    result.success(SleepTimer.endAt)
                }
                "alert" -> {
                    @Suppress("UNCHECKED_CAST")
                    Alerts.show(this, (call.arguments as? Map<String, Any?>) ?: emptyMap())
                    result.success(true)
                }
                "qrPng" -> {
                    // a crisp black-on-white QR code as PNG bytes (ZXing)
                    val text = call.argument<String>("text") ?: ""
                    val px = call.argument<Int>("size") ?: 360
                    try {
                        val m = com.google.zxing.qrcode.QRCodeWriter().encode(
                            text, com.google.zxing.BarcodeFormat.QR_CODE, px, px,
                            mapOf(
                                com.google.zxing.EncodeHintType.MARGIN to 1,
                                com.google.zxing.EncodeHintType.ERROR_CORRECTION to
                                    com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.M
                            )
                        )
                        val bmp = Bitmap.createBitmap(m.width, m.height, Bitmap.Config.ARGB_8888)
                        for (y in 0 until m.height) for (x in 0 until m.width) {
                            bmp.setPixel(x, y, if (m.get(x, y)) Color.BLACK else Color.WHITE)
                        }
                        result.success(png(bmp))
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "cancelLearn" -> { RemoteKeys.learn = null; result.success(true) }
                "remoteKeysStatus" -> {
                    RemoteKeys.reload(this)
                    result.success(mapOf("helper" to HomeKeyService.running, "googleHomeOff" to RemoteKeys.googleHomeOff))
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
                "openFireSettings" -> result.success(openFireSettings())
                "openSettings" -> result.success(openSettings(call.argument<String>("page") ?: ""))
                "openAmazonHome" -> result.success(openAmazonHome())
                "readTokenFile" -> Thread {
                    val t = readTokenFile()
                    runOnUiThread { result.success(t) }
                }.start()
                "appVersion" -> result.success(mapOf("name" to versionName(), "code" to versionCode()))
                "deviceInfo" -> result.success(
                    mapOf(
                        "fireTv" to isFireTv(),
                        "model" to (Build.MODEL ?: ""),
                        "maker" to (Build.MANUFACTURER ?: ""),
                        "defaultHome" to isDefaultHome()
                    )
                )
                "updatePath" -> result.success(File(appDir(), "update.apk").absolutePath)
                "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
                "appInfo" -> result.success(appInfo(call.argument<String>("package")))
                "uninstall" -> result.success(uninstall(call.argument<String>("package")))
                "killApp" -> result.success(killApp(call.argument<String>("package")))
                "closeAllApps" -> result.success(closeAllApps())
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
                            val adb = LocalAdb(filesDir) { line -> runOnUiThread { ch.invokeMethod("adbLog", line) } }
                            adb.run(cmds)
                            mapOf("ok" to true, "outputs" to adb.outputs.toList())
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

    /** Opens Amazon's own home screen (Foyer's redirect is paused for a few seconds). */
    private fun openAmazonHome(): Boolean {
        HomeKeyService.allowAmazonUntil = System.currentTimeMillis() + 8000
        return try {
            startActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                    .setPackage(HomeKeyService.AMAZON_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            )
            true
        } catch (e: Exception) { false }
    }

    /** Opens the stock Fire TV settings app. Tries a few ways because Fire OS builds differ. */
    /** Opens one page of the TV's own settings (used by setup on Google TV / Android TV boxes). */
    private fun openSettings(page: String): Boolean {
        // give the person time in Settings without the Home button service pulling them back
        HomeKeyService.allowAmazonUntil = System.currentTimeMillis() + 120000
        val action = when (page) {
            "developer" -> Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS
            "about" -> Settings.ACTION_DEVICE_INFO_SETTINGS
            "accessibility" -> Settings.ACTION_ACCESSIBILITY_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        for (a in listOf(action, Settings.ACTION_SETTINGS)) {
            try {
                startActivity(Intent(a).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: Exception) { }
        }
        return false
    }

    private fun openFireSettings(): String {
        // pause Foyer's Home redirect so Amazon's settings are not pulled back to Foyer
        HomeKeyService.allowAmazonUntil = System.currentTimeMillis() + 15000
        val tries = listOf<() -> Intent?>(
            { launchIntent("com.amazon.tv.settings.v2") },
            { Intent(Settings.ACTION_SETTINGS) },
            { launchIntent("com.amazon.tv.settings") }
        )
        for (t in tries) {
            try {
                val i = t() ?: continue
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                return "ok"
            } catch (e: Exception) { }
        }
        return "failed"
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

    /** Amazon's Fire TV devices need the Home button workaround; other Android TV boxes do not. */
    private fun isFireTv(): Boolean =
        packageManager.hasSystemFeature("amazon.hardware.fire_tv") ||
            (Build.MANUFACTURER ?: "").equals("Amazon", ignoreCase = true)

    /** True when pressing Home lands on Foyer without any help (the stock launcher is off). */
    private fun isDefaultHome(): Boolean = try {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        packageManager.resolveActivity(i, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName == packageName
    } catch (e: Exception) { false }

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

    /** Asks Android to close every other launchable app (used by Goodnight). Returns how many were asked. */
    private fun closeAllApps(): Int {
        var n = 0
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val seen = HashSet<String>()
            for (cat in listOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER)) {
                for (ri in packageManager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(cat), 0)) {
                    val pkg = ri.activityInfo.packageName
                    if (pkg == packageName || pkg.startsWith("com.amazon.tv.") || !seen.add(pkg)) continue
                    try { am.killBackgroundProcesses(pkg); n++ } catch (e: Exception) { }
                }
            }
        } catch (e: Exception) { }
        return n
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
        // Google TV: install through the TV's debugging link. No "Update?" box, and Foyer
        // becomes the installer of record, so later updates can skip the box too.
        if (!isFireTv()) {
            Thread {
                val ok = try {
                    val adb = LocalAdb(filesDir) { }
                    adb.run(listOf("pm install -r -i $packageName \"${f.absolutePath}\""))
                    adb.outputs.firstOrNull()?.contains("Success") == true
                } catch (e: Exception) {
                    // the install replaces Foyer, which can cut the link just as it succeeds
                    e is java.io.EOFException ||
                        (e is java.net.SocketException && e !is java.net.ConnectException)
                }
                if (!ok) runOnUiThread { sessionInstall(f) }
            }.start()
            return "started"
        }
        return sessionInstall(f)
    }

    private fun sessionInstall(f: File): String {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (e: Exception) { }
            return "needsPermission"
        }
        // Android's session installer: unlike the old "open this APK" way, it doesn't mark
        // Foyer as restricted, which would stop the remote helper from being switched on.
        try {
            val pi = packageManager.packageInstaller
            val params = android.content.pm.PackageInstaller.SessionParams(
                android.content.pm.PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            params.setAppPackageName(packageName)
            if (Build.VERSION.SDK_INT >= 31) {
                params.setRequireUserAction(android.content.pm.PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
            val id = pi.createSession(params)
            pi.openSession(id).use { s ->
                s.openWrite("foyer.apk", 0, f.length()).use { out ->
                    f.inputStream().use { it.copyTo(out) }
                    s.fsync(out)
                }
                val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= 31) android.app.PendingIntent.FLAG_MUTABLE else 0)
                val done = android.app.PendingIntent.getBroadcast(
                    this, id, Intent(this, InstallReceiver::class.java), flags
                )
                s.commit(done.intentSender)
            }
            return "started"
        } catch (e: Exception) { }
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

    /** After an update the service is listed as on but not running: switch it off and on again. */
    private fun ensureHomeKey() {
        try {
            if (!canWriteSecure()) return
            if (homeKeyEnabled() && !prefs.contains("homeKeyWanted")) prefs.edit().putBoolean("homeKeyWanted", true).apply()
            if (!prefs.getBoolean("homeKeyWanted", false) || HomeKeyService.running) return
            if (!isFireTv() && !liftTried) {
                // An update made the old way marks Foyer "restricted", which keeps the helper off.
                // Lift it through the TV's debugging link (already allowed), then switch it on.
                liftTried = true
                Thread {
                    try {
                        LocalAdb(filesDir) { }.run(listOf("appops set $packageName ACCESS_RESTRICTED_SETTINGS allow"))
                    } catch (e: Exception) { }
                    runOnUiThread { restartHomeKey() }
                }.start()
                return
            }
            restartHomeKey()
        } catch (e: Exception) { }
    }

    private var liftTried = false

    private fun restartHomeKey() {
        try {
            if (HomeKeyService.running) return
            val others = enabledServices().filter { !isOurs(it) }
            Settings.Secure.putString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, others.joinToString(":"))
            Settings.Secure.putString(
                contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                (others + service.flattenToString()).joinToString(":")
            )
            Settings.Secure.putInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
        } catch (e: Exception) { }
    }

    override fun onResume() {
        super.onResume()
        DropRemote.activity = this
        DropRemote.activityResumed = true
        DropRemote.ensure(this)
        ensureHomeKey()
    }

    private fun homeKeyEnabled(): Boolean = enabledServices().any { isOurs(it) }

    private fun canWriteSecure(): Boolean =
        checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    private fun setHomeKey(on: Boolean): Boolean {
        if (!canWriteSecure()) return false
        prefs.edit().putBoolean("homeKeyWanted", on).apply()
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

    /** Opens a web link sent from the phone. YouTube links go to the YouTube app when it is installed. */
    private fun openUrl(url: String?): Boolean {
        val uri = try { android.net.Uri.parse(url ?: return false) } catch (e: Exception) { return false }
        if (uri.scheme != "http" && uri.scheme != "https") return false
        val host = (uri.host ?: "").lowercase()
        val tries = ArrayList<Intent>()
        if (host.endsWith("youtube.com") || host.endsWith("youtu.be")) {
            for (p in listOf("com.amazon.firetv.youtube", "com.google.android.youtube.tv")) {
                tries.add(Intent(Intent.ACTION_VIEW, uri).setPackage(p))
            }
        }
        tries.add(Intent(Intent.ACTION_VIEW, uri))
        for (i in tries) {
            try {
                startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: Exception) { }
        }
        return false
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
