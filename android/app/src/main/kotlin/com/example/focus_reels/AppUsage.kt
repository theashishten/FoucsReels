package com.example.focus_reels

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import org.json.JSONObject
import java.util.Calendar

/**
 * Screen time for every app, from Android's own usage log (Usage access), so no accessibility events are
 * needed for other apps. Android only keeps about a week of events, so each day is copied into our own
 * "appUsage" store the first time it is complete and then kept permanently.
 */
object AppUsage {
    private const val KEEP_LOOKBACK_DAYS = 8

    private fun dayStart(ms: Long): Long = Calendar.getInstance().apply {
        timeInMillis = ms
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun nextDay(start: Long): Long = Calendar.getInstance().apply {
        timeInMillis = start; add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis

    private var launcherPkg: String? = null
    private fun skip(ctx: Context, pkg: String): Boolean {
        if (launcherPkg == null) {
            val h = ctx.packageManager.resolveActivity(
                android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_HOME), 0)
            launcherPkg = h?.activityInfo?.packageName ?: ""
        }
        return pkg == launcherPkg || pkg == "com.android.systemui" || pkg == ctx.packageName ||
            pkg.contains("inputmethod") || pkg.contains("keyboard")
    }

    private fun label(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg }

    /** Foreground milliseconds per package between [from] and [to]. */
    private fun compute(ctx: Context, from: Long, to: Long): Map<String, Long> {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val ev = usm.queryEvents(from, to)
        val e = UsageEvents.Event()
        val open = HashMap<String, Long>()
        val total = HashMap<String, Long>()
        fun close(p: String, at: Long) {
            val s = open.remove(p) ?: return
            if (at > s) total[p] = (total[p] ?: 0L) + (at - s)
        }
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            val p = e.packageName ?: continue
            @Suppress("DEPRECATION")
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> if (!open.containsKey(p)) open[p] = e.timeStamp
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> close(p, e.timeStamp)
                UsageEvents.Event.SCREEN_NON_INTERACTIVE, UsageEvents.Event.KEYGUARD_SHOWN ->
                    for (k in open.keys.toList()) close(k, e.timeStamp)
            }
        }
        for (k in open.keys.toList()) close(k, to)
        return total.filter { !skip(ctx, it.key) && it.value >= 1000 }
    }

    /** Today's foreground milliseconds for one app, including the session still open right now. */
    fun todayMs(ctx: Context, pkg: String): Long {
        val now = System.currentTimeMillis()
        return compute(ctx, dayStart(now), now)[pkg] ?: 0L
    }

    /** Times the phone was unlocked today (keyguard dismissed). */
    fun unlocksToday(ctx: Context): Int {
        if (!FallbackService.hasUsageAccess(ctx)) return 0
        val now = System.currentTimeMillis()
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val ev = usm.queryEvents(dayStart(now), now)
        val e = UsageEvents.Event()
        var n = 0
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            if (e.eventType == 18 /* KEYGUARD_HIDDEN */) n++
        }
        return n
    }

    /** One line for the evening recap: total screen time, the busiest app and unlocks. */
    fun recap(ctx: Context): String? {
        if (!FallbackService.hasUsageAccess(ctx)) return null
        val now = System.currentTimeMillis()
        val m = compute(ctx, dayStart(now), now)
        if (m.isEmpty()) return null
        val total = m.values.sum()
        val top = m.maxByOrNull { it.value }!!
        fun dur(ms: Long): String {
            val min = (ms / 60000).toInt()
            return if (min < 60) "${min}m" else "${min / 60}h ${min % 60}m"
        }
        return "Screen time ${dur(total)} in ${m.size} apps, most in ${label(ctx, top.key)} (${dur(top.value)}). " +
            "Unlocked ${unlocksToday(ctx)} times."
    }

    /** Copies recent days into the permanent store (today is recomputed each time) and returns everything. */
    fun refresh(ctx: Context): JSONObject {
        val store = Store.obj(ctx, "appUsage", "{}")
        if (!FallbackService.hasUsageAccess(ctx)) return store
        val now = System.currentTimeMillis()
        var start = dayStart(now)
        // Oldest first would be natural, but today and the last week are the only days Android still has.
        for (i in 0 until KEEP_LOOKBACK_DAYS) {
            val end = if (i == 0) now else nextDay(start)
            val key = Engine.dayKey(start)
            val isToday = i == 0
            // A finished day that is already stored never changes, so skip it.
            if (isToday || !store.has(key)) {
                val m = compute(ctx, start, end)
                if (m.isNotEmpty() || isToday) {
                    val day = JSONObject()
                    for ((p, ms) in m) day.put(p, JSONObject().put("label", label(ctx, p)).put("ms", ms))
                    store.put(key, day)
                }
            }
            start = Calendar.getInstance().apply { timeInMillis = start; add(Calendar.DAY_OF_YEAR, -1) }.timeInMillis
        }
        Store.put(ctx, "appUsage", store)
        return store
    }
}
