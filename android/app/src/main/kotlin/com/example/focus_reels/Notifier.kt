package com.example.focus_reels

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar

/** Nudge notifications. Silently does nothing when the permission is missing or the OS is too old. */
object Notifier {
    private const val CHANNEL = "nudges"

    fun post(ctx: Context, id: Int, title: String, text: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Reel nudges", NotificationManager.IMPORTANCE_DEFAULT)
        )
        val open = PendingIntent.getActivity(
            ctx, id, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        nm.notify(
            id,
            Notification.Builder(ctx, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        )
    }

    /** Called after each counted reel. Fires at 80% and at 100% of the daily limit, once each per day. */
    fun checkNudges(ctx: Context) {
        val cfg = Store.config(ctx)
        if (Engine.trackOnly(cfg)) return
        val limit = cfg.optInt("dailyLimit", 0)
        if (limit <= 0) return
        val t = Store.today(ctx)
        val total = t.optInt("total")
        if (total >= limit && !t.optBoolean("nudge100")) {
            t.put("nudge100", true)
            Store.put(ctx, "today", t)
            post(ctx, 2, "Daily limit reached", "You've watched $total reels today. Time to stop.")
        } else if (total * 100 >= limit * 80 && !t.optBoolean("nudge80")) {
            t.put("nudge80", true)
            Store.put(ctx, "today", t)
            post(ctx, 1, "Almost at your limit", "$total of $limit reels used today.")
        }
    }

    /** Schedules the daily summary at 21:00 local time. Safe to call repeatedly. */
    fun scheduleSummary(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val at = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 21); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }.timeInMillis
        val pi = PendingIntent.getBroadcast(
            ctx, 77, Intent(ctx, SummaryReceiver::class.java).setAction("com.example.focus_reels.SUMMARY"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.setInexactRepeating(AlarmManager.RTC_WAKEUP, at, AlarmManager.INTERVAL_DAY, pi)
    }
}
