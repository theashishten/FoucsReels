package com.example.focus_reels

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Notifier.scheduleSummary(this)
        WatchdogReceiver.schedule(this)
        Guard.sync(this)
        // Resume the backup counter if the user turned it on earlier.
        if (Store.config(this).optBoolean("fallback", false) && FallbackService.hasUsageAccess(this)) {
            FallbackService.start(this)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focus_reels")
            .setMethodCallHandler { call, result ->
                val now = System.currentTimeMillis()
                when (call.method) {
                    "getState" -> result.success(
                        JSONObject()
                            .put("config", Store.config(this))
                            .put("today", Store.today(this))
                            .put("history", Store.history(this))
                            .put("daily", Store.obj(this, "daily", "{}"))
                            .put("status", Store.status(this))
                            .put("a11y", Store.a11yEnabled(this))
                            .put("usage", FallbackService.hasUsageAccess(this))
                            .put("social", Store.obj(this, "social", "{}"))
                            .put("agg", Store.obj(this, "agg", "{}"))
                            .put("blockLog", Store.getString(this, "blockLog").ifEmpty { "[]" })
                            .put("screen", Store.obj(this, "screen", "{}"))
                            .put("firstDay", Store.getString(this, "firstDay"))
                            .put("lastEvent", Store.getString(this, "lastEvent"))
                            .put("now", now)
                            .toString()
                    )
                    "getAppUsage" -> Thread {
                        val days = AppUsage.refresh(this)
                        val out = JSONObject().put("days", days).put("access", FallbackService.hasUsageAccess(this))
                            .put("unlocks", AppUsage.unlocksToday(this)).toString()
                        runOnUiThread { result.success(out) }
                    }.start()
                    "setConfig" -> {
                        Store.put(this, "config", JSONObject(call.arguments as String))
                        ReelsAccessibilityService.instance?.applyScope()
                        Guard.sync(this)
                        result.success(null)
                    }
                    "setSocial" -> {
                        Store.put(this, "social", JSONObject(call.arguments as String))
                        result.success(null)
                    }
                    "setFallback" -> {
                        val on = call.argument<Boolean>("on") == true
                        Store.put(this, "config", Store.config(this).put("fallback", on))
                        if (on && FallbackService.hasUsageAccess(this)) FallbackService.start(this)
                        result.success(null)
                    }
                    "openUsageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "testSummary" -> {
                        SummaryReceiver().onReceive(this, Intent("com.example.focus_reels.SUMMARY"))
                        result.success(null)
                    }
                    "syncNow" -> {
                        Sync.push(this, force = true)
                        result.success(null)
                    }
                    "importHistory" -> {
                        Store.put(this, "history", JSONObject(call.arguments as String))
                        result.success(null)
                    }
                    "importDaily" -> {
                        Store.put(this, "daily", JSONObject(call.arguments as String))
                        result.success(null)
                    }
                    "clearBlocks" -> {
                        // Ends cooldowns, pauses and hard blocks. Never touches any counted data.
                        Store.put(this, "status", JSONObject())
                        result.success(null)
                    }
                    "eraseAll" -> {
                        // The only way to delete data, and only after a confirmation in the app.
                        for (k in listOf("today", "history", "daily", "agg", "status")) Store.put(this, k, JSONObject())
                        FocusWidget.refresh(this)
                        result.success(null)
                    }
                    "pause" -> result.success(Engine.pause(this, call.argument<Int>("minutes") ?: 5, now))
                    "forcePause" -> {
                        // Used only after the remote buddy approved: bypasses strict mode for this one pause.
                        val st = Store.status(this)
                        st.put("pausedUntil", now + (call.argument<Int>("minutes") ?: 5) * 60_000L)
                        st.put("blockedUntil", 0)
                        st.put("hardBlockUntil", 0)
                        Store.put(this, "status", st)
                        result.success(null)
                    }
                    "hardBlock" -> {
                        Engine.hardBlock(this, call.argument<Int>("minutes") ?: 30, now)
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "getDetectors" -> result.success(
                        JSONObject()
                            .put("defaults", JSONObject(Engine.DEFAULT_DETECTORS.mapValues { org.json.JSONArray(it.value) }))
                            .put("custom", Store.obj(this, "detectors", "{}"))
                            .put("lastIds", Store.getString(this, "lastIds"))
                            .toString()
                    )
                    "setDetectors" -> {
                        Store.put(this, "detectors", JSONObject(call.arguments as String))
                        result.success(null)
                    }
                    "openAppInfo" -> {
                        // The page where "Allow restricted settings" lives (menu with three dots, top right).
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName"))
                        )
                        result.success(null)
                    }
                    "getAppVersion" -> {
                        val pi = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (android.os.Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
                        result.success(JSONObject().put("name", pi.versionName ?: "").put("code", code).toString())
                    }
                    "getUpdateDir" -> {
                        val dir = java.io.File(cacheDir, "updates").apply { mkdirs() }
                        // Old downloads are not kept.
                        dir.listFiles()?.forEach { it.delete() }
                        result.success(dir.absolutePath)
                    }
                    "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                    "openInstallSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName"))
                        )
                        result.success(null)
                    }
                    "installApk" -> {
                        val f = java.io.File(call.arguments as String)
                        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
                        startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "getGuardInfo" -> {
                        val installed = org.json.JSONArray()
                        Guard.banks(this).forEach { pkg ->
                            try {
                                val ai = packageManager.getApplicationInfo(pkg, 0)
                                installed.put(JSONObject().put("pkg", pkg).put("name", packageManager.getApplicationLabel(ai).toString()))
                            } catch (_: Exception) {}
                        }
                        result.success(
                            JSONObject()
                                .put("secure", AccessSwitch.canWrite(this))
                                .put("usage", FallbackService.hasUsageAccess(this))
                                .put("installed", installed)
                                .put("paused", Guard.pausedFor(this))
                                .put("a11y", Store.a11yEnabled(this))
                                .toString()
                        )
                    }
                    "getPermissions" -> {
                        val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                        val notif = android.os.Build.VERSION.SDK_INT < 33 ||
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                        result.success(
                            JSONObject()
                                .put("accessibility", Store.a11yEnabled(this))
                                .put("overlay", Settings.canDrawOverlays(this))
                                .put("notifications", notif)
                                .put("battery", pm.isIgnoringBatteryOptimizations(packageName))
                                .put("usage", FallbackService.hasUsageAccess(this))
                                .toString()
                        )
                    }
                    "requestNotifications" -> {
                        if (android.os.Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
                        }
                        result.success(null)
                    }
                    "openOverlaySettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:$packageName"))
                        )
                        result.success(null)
                    }
                    "requestBattery" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, android.net.Uri.parse("package:$packageName"))
                            )
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(null)
                    }
                    "getIcons" -> Thread {
                        val out = JSONObject()
                        val pm = packageManager
                        for (p in (call.arguments as List<*>).map { it.toString() }) {
                            try {
                                val d = pm.getApplicationIcon(p)
                                val sz = 96
                                val bmp = android.graphics.Bitmap.createBitmap(sz, sz, android.graphics.Bitmap.Config.ARGB_8888)
                                val c = android.graphics.Canvas(bmp)
                                d.setBounds(0, 0, sz, sz)
                                d.draw(c)
                                val bos = java.io.ByteArrayOutputStream()
                                bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, bos)
                                out.put(p, android.util.Base64.encodeToString(bos.toByteArray(), android.util.Base64.NO_WRAP))
                            } catch (_: Exception) {}
                        }
                        runOnUiThread { result.success(out.toString()) }
                    }.start()
                    "openBatterySettings" -> {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
