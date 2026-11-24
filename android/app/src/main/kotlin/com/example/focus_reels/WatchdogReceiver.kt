package com.example.focus_reels

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Hourly check that the accessibility service is still on. Phones and battery savers sometimes switch it off
 * silently, which stops all counting and blocking, so a notification asks you to turn it back on (at most twice a day).
 */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) {
            schedule(c)
            Guard.sync(c)
            return
        }
        if (Store.a11yEnabled(c)) return
        // Only nag once the app has been used, and not more than every 12 hours.
        if (Store.getString(c, "firstDay").isEmpty()) return
        val last = Store.getString(c, "watchdogAt").toLongOrNull() ?: 0L
        val now = System.currentTimeMillis()
        if (now - last < 12 * 3_600_000L) return
        Store.putString(c, "watchdogAt", now.toString())
        Notifier.post(
            c, 20, "Tracking is off",
            "Focus Reels cannot count or block reels while its Accessibility service is off. Tap to turn it back on."
        )
    }

    companion object {
        fun schedule(ctx: Context) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = PendingIntent.getBroadcast(
                ctx, 78, Intent(ctx, WatchdogReceiver::class.java).setAction("com.example.focus_reels.WATCHDOG"),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.setInexactRepeating(
                AlarmManager.RTC, System.currentTimeMillis() + 3_600_000L, AlarmManager.INTERVAL_HOUR, pi
            )
        }
    }
}
