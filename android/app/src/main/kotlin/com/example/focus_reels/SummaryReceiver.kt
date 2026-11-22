package com.example.focus_reels

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Posts the evening summary, and re-arms the daily alarm after a reboot. */
class SummaryReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) {
            Notifier.scheduleSummary(c)
            return
        }
        if (!Store.config(c).optBoolean("summary", true)) return
        val today = Store.today(c)
        val total = today.optInt("total")
        val yesterday = Store.history(c).optInt(Engine.dayKey(System.currentTimeMillis() - 86_400_000L))
        val minutes = today.optLong("watchMs") / 60_000
        val trend = when {
            yesterday == 0 -> ""
            total < yesterday -> " That's ${yesterday - total} fewer than yesterday."
            total > yesterday -> " That's ${total - yesterday} more than yesterday."
            else -> " Same as yesterday."
        }
        val recap = AppUsage.recap(c)
        Notifier.post(
            c, 10, "Today's recap",
            "You watched $total reels (about $minutes min).$trend" + (if (recap != null) "\n$recap" else "")
        )
    }
}
