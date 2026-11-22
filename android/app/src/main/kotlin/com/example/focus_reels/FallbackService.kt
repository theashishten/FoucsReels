package com.example.focus_reels

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.app.Notification

/**
 * Backup counter for when the Accessibility service is off. It cannot see which reel is showing, so it
 * estimates: while a reel app is in the foreground and audio is playing, every N seconds counts as one reel.
 * It never blocks (blocking needs Accessibility) and it stands down whenever Accessibility is on.
 */
class FallbackService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var foreground: String? = null
    private var lastQuery = 0L
    private val accumulated = HashMap<String, Long>()

    private val tick = object : Runnable {
        override fun run() {
            if (!Store.config(this@FallbackService).optBoolean("fallback", false)) {
                stopSelf()
                return
            }
            step()
            handler.postDelayed(this, STEP_MS)
        }
    }

    override fun onBind(i: Intent?): IBinder? = null

    override fun onStartCommand(i: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun startAsForeground() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel("fallback", "Backup counter", NotificationManager.IMPORTANCE_LOW)
        )
        val n = Notification.Builder(this, "fallback")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Focus Reels backup counter")
            .setContentText("Estimates reels only while Accessibility is off")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun step() {
        if (Store.a11yEnabled(this)) return // Accessibility is exact; do not double count.
        if (!hasUsageAccess(this)) return
        updateForeground()
        val pkg = foreground ?: return
        val cfg = Store.config(this)
        if (pkg !in Engine.TARGETS || !Engine.appEnabled(cfg, pkg)) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (!power.isInteractive || !audio.isMusicActive) return

        val perReelMs = cfg.optInt("estSeconds", 25) * 1000L
        val total = (accumulated[pkg] ?: 0L) + STEP_MS
        if (total >= perReelMs) {
            accumulated[pkg] = total - perReelMs
            Engine.registerReel(this, pkg, System.currentTimeMillis(), estimated = true)
        } else {
            accumulated[pkg] = total
        }
    }

    /** Tracks which app is in front from the system's usage events. */
    private fun updateForeground() {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val from = if (lastQuery == 0L) now - 120_000 else lastQuery
        lastQuery = now
        val ev = usm.queryEvents(from, now)
        val e = UsageEvents.Event()
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            @Suppress("DEPRECATION")
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> foreground = e.packageName
                UsageEvents.Event.ACTIVITY_PAUSED -> if (e.packageName == foreground) foreground = null
            }
        }
    }

    companion object {
        private const val STEP_MS = 5_000L
        private const val NOTIF_ID = 77

        fun hasUsageAccess(ctx: Context): Boolean {
            val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            @Suppress("DEPRECATION")
            val mode = ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), ctx.packageName
            )
            return mode == AppOpsManager.MODE_ALLOWED
        }

        fun start(ctx: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(Intent(ctx, FallbackService::class.java))
            }
        }
    }
}
