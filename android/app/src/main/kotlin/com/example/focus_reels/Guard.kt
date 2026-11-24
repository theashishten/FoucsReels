package com.example.focus_reels

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import org.json.JSONArray

/** Switches this app's Accessibility service on or off. Needs WRITE_SECURE_SETTINGS, granted once over adb. */
object AccessSwitch {
    fun canWrite(c: Context) = c.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    fun isOn(c: Context) = Store.a11yEnabled(c)

    fun set(c: Context, on: Boolean): Boolean {
        if (!canWrite(c)) return false
        return try {
            val me = ComponentName(c, ReelsAccessibilityService::class.java).flattenToString()
            val cur = Settings.Secure.getString(c.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
            val list = cur.split(':').filter { it.isNotEmpty() && !it.equals(me, true) }.toMutableList()
            if (on) list.add(me)
            Settings.Secure.putString(c.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, list.joinToString(":"))
            if (on) Settings.Secure.putInt(c.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            true
        } catch (_: Exception) {
            false
        }
    }
}

/**
 * Banking apps refuse to open while a non-system Accessibility service is on. When the option is switched on, we turn
 * ours off while one of these apps is in front and back on a moment after you leave it.
 */
object Guard {
    val DEFAULT_BANKS = listOf(
        "com.axis.mobile", "com.upi.axispay", "com.phonepe.app", "com.sbi.lotusintouch", "com.sbi.SBIFreedomPlus",
        "com.google.android.apps.nbu.paisa.user", "net.one97.paytm", "in.org.npci.upiapp", "com.dreamplug.androidapp",
        "com.csam.icici.bank.imobile", "com.snapwork.hdfc", "com.msf.kbank.mobile", "com.infra.boiupi",
    )

    fun enabled(c: Context) = Store.config(c).optBoolean("bankGuard", false)

    fun banks(c: Context): Set<String> {
        val extra = Store.config(c).optJSONArray("bankExtra") ?: JSONArray()
        return (DEFAULT_BANKS + (0 until extra.length()).map { extra.optString(it) }).filter { it.isNotEmpty() }.toSet()
    }

    fun pausedFor(c: Context) = Store.getString(c, "guardPaused")

    /** Called from the accessibility service the moment a bank app's window shows up. */
    fun pauseNow(c: Context, pkg: String) {
        if (pausedFor(c).isEmpty() && AccessSwitch.isOn(c) && AccessSwitch.set(c, false)) {
            Store.putString(c, "guardPaused", pkg)
        }
        ensureRunning(c)
    }

    fun release(c: Context) {
        if (pausedFor(c).isNotEmpty()) {
            Store.putString(c, "guardPaused", "")
            AccessSwitch.set(c, true)
        }
    }

    fun ensureRunning(c: Context) {
        if (!enabled(c) || !AccessSwitch.canWrite(c) || !FallbackService.hasUsageAccess(c)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) c.startForegroundService(Intent(c, GuardService::class.java))
    }

    /** Applies a change of the setting: start watching, or hand Accessibility back. */
    fun sync(c: Context) {
        if (enabled(c)) ensureRunning(c) else release(c)
    }
}

class GuardService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var foreground: String? = null
    private var lastQuery = 0L
    private var leftAt = 0L
    private var shownText = ""

    private val tick = object : Runnable {
        override fun run() {
            if (!Guard.enabled(this@GuardService) || !AccessSwitch.canWrite(this@GuardService)) {
                Guard.release(this@GuardService)
                stopSelf()
                return
            }
            step()
            handler.postDelayed(this, STEP_MS)
        }
    }

    override fun onBind(i: Intent?): IBinder? = null

    override fun onStartCommand(i: Intent?, flags: Int, startId: Int): Int {
        post("Watching for banking apps")
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        // Never leave counting switched off behind us.
        Guard.release(this)
        super.onDestroy()
    }

    private fun step() {
        updateForeground()
        val fg = foreground
        val bank = fg != null && fg in Guard.banks(this)
        val paused = Guard.pausedFor(this)
        if (bank) {
            leftAt = 0L
            if (paused.isEmpty() && AccessSwitch.isOn(this)) Guard.pauseNow(this, fg!!)
            post("Counting paused while you use a banking app")
        } else if (paused.isNotEmpty()) {
            val now = System.currentTimeMillis()
            if (leftAt == 0L) leftAt = now
            // A short gap between two screens of the same bank app should not switch counting back on.
            if (now - leftAt > 2_000L) {
                Guard.release(this)
                leftAt = 0L
                post("Watching for banking apps")
            }
        } else {
            post("Watching for banking apps")
        }
    }

    private fun updateForeground() {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val from = if (lastQuery == 0L) now - 60_000 else lastQuery - 1_000
        lastQuery = now
        val ev = usm.queryEvents(from, now)
        val e = UsageEvents.Event()
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            @Suppress("DEPRECATION")
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> foreground = e.packageName
                UsageEvents.Event.ACTIVITY_PAUSED -> if (e.packageName == foreground) foreground = null
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> foreground = null
            }
        }
    }

    private fun post(text: String) {
        if (text == shownText) return
        shownText = text
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("guard", "Banking guard", NotificationManager.IMPORTANCE_MIN))
        val n = Notification.Builder(this, "guard")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Focus Reels banking guard")
            .setContentText(text)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NOTIF_ID, n)
    }

    companion object {
        private const val STEP_MS = 400L
        private const val NOTIF_ID = 79
    }
}
