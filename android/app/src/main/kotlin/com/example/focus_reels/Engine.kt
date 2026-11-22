package com.example.focus_reels

import android.content.Context
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** Rule engine: decides whether reels are blocked and records counted reels. */
object Engine {
    val TARGETS = listOf(
        "com.instagram.android", "com.google.android.youtube",
        "com.zhiliaoapp.musically", "com.ss.android.ugc.trill",
        "com.snapchat.android", "com.facebook.katana", "com.netflix.mediaclient",
    )

    /** Default "this is a reel screen" view ids per app; the user can add more under Detection rules. */
    val DEFAULT_DETECTORS: Map<String, List<String>> = mapOf(
        "com.instagram.android" to listOf("clips_viewer_view_pager", "clips_swipe_refresh_container"),
        "com.google.android.youtube" to listOf("reel_recycler", "reel_player_page_container"),
        "com.snapchat.android" to listOf("favorite"),
    )

    /** Browsers whose address bar is read (only when "Block Shorts in browsers" is on) and the id of that bar. */
    val BROWSERS: Map<String, List<String>> = mapOf(
        "com.android.chrome" to listOf("url_bar"),
        "com.sec.android.app.sbrowser" to listOf("location_bar_edit_text"),
        "com.brave.browser" to listOf("url_bar"),
        "com.microsoft.emmx" to listOf("url_bar"),
        "org.mozilla.firefox" to listOf("mozac_browser_toolbar_url_view", "url_bar_title"),
        "com.opera.browser" to listOf("url_field"),
    )

    fun dayKey(now: Long): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))

    private fun cal(now: Long) = Calendar.getInstance().apply { timeInMillis = now }

    fun inSchedule(cfg: JSONObject, now: Long): Boolean {
        val arr = cfg.optJSONArray("schedules") ?: return false
        val c = cal(now)
        val m = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        val dayBit = 1 shl (c.get(Calendar.DAY_OF_WEEK) - 1)
        for (i in 0 until arr.length()) {
            val s = arr.getJSONObject(i)
            if (!s.optBoolean("on", true)) continue
            if (s.optInt("days", 127) and dayBit == 0) continue
            val a = s.optInt("start")
            val b = s.optInt("end")
            if (if (a <= b) m in a until b else (m >= a || m < b)) return true
        }
        return false
    }

    /** Track-only is the default: Focus Reels counts reels and does nothing else until the user sets a limit. */
    fun trackOnly(cfg: JSONObject): Boolean = cfg.optBoolean("trackOnly", true)

    fun appEnabled(cfg: JSONObject, pkg: String): Boolean =
        cfg.optJSONObject("apps")?.optJSONObject(pkg)?.optBoolean("enabled", true) ?: true

    fun appFlag(cfg: JSONObject, pkg: String, key: String): Boolean =
        cfg.optJSONObject("apps")?.optJSONObject(pkg)?.optBoolean(key, false) ?: false

    private fun appLimit(cfg: JSONObject, pkg: String): Int =
        cfg.optJSONObject("apps")?.optJSONObject(pkg)?.optInt("limit", 0) ?: 0

    /** Reason a reel would be blocked right now, or null if allowed. */
    fun blockReason(ctx: Context, pkg: String, now: Long): String? {
        val cfg = Store.config(ctx)
        if (!cfg.optBoolean("blockEnabled", true)) return null
        val st = Store.status(ctx)
        val strict = cfg.optBoolean("strict", false)
        // "Always block reels" is an explicit per-app choice, so it applies in every mode and cannot be paused.
        if (appFlag(cfg, pkg, "alwaysBlock")) return "always"
        if (st.optLong("hardBlockUntil") > now) return "hard"
        // Track-only mode never limits or blocks on its own; only a hard block you start yourself applies.
        if (trackOnly(cfg)) return null
        val plan = cfg.optString("plan", "none")
        if (plan == "paused") return null
        if (plan == "blockAll") return "plan"
        if (!strict && st.optLong("pausedUntil") > now) return null
        if (st.optLong("blockedUntil") > now) return "cooldown"
        if (plan == "curious") {
            val start = st.optLong("curiousStart")
            if (start > 0) {
                if (now - st.optLong("curiousLast") >= 10 * 60_000L) {
                    // Gone for a while: the "on" time starts fresh with the next reel.
                    st.put("curiousStart", 0); Store.put(ctx, "status", st)
                } else if (now >= start + cfg.optInt("curiousOn", 5) * 60_000L) {
                    st.put("blockedUntil", now + cfg.optInt("curiousOff", 30) * 60_000L)
                    st.put("curiousStart", 0)
                    Store.put(ctx, "status", st)
                    return "cooldown"
                }
            }
        }
        if (inSchedule(cfg, now)) return "schedule"
        // A plan (One reel, Curious) replaces the daily and per-app limits; those only apply to "My limits".
        if (plan == "oneReel" || plan == "curious") return null
        val today = Store.today(ctx)
        val limit = cfg.optInt("dailyLimit", 0)
        if (limit > 0 && today.optInt("total") >= limit) return "limit"
        val al = appLimit(cfg, pkg)
        if (al > 0 && (today.optJSONObject("perApp")?.optInt(pkg) ?: 0) >= al) return "applimit"
        return null
    }

    /** What to do when a block fires: "back" (default), "home" or "lock". Per-app choice, else the global one. */
    fun blockAction(cfg: JSONObject, pkg: String): String {
        val per = cfg.optJSONObject("apps")?.optJSONObject(pkg)?.optString("blockAction", "") ?: ""
        if (per.isNotEmpty()) return per
        return cfg.optString("blockAction", "back").ifEmpty { "back" }
    }

    /** Count one reel. May start a cooldown when the window allowance is exceeded. */
    fun registerReel(ctx: Context, pkg: String, now: Long, estimated: Boolean = false) {
        val t = Store.today(ctx)
        t.put("total", t.optInt("total") + 1)
        if (estimated) t.put("estimated", t.optInt("estimated") + 1)
        val per = t.optJSONObject("perApp") ?: JSONObject().also { t.put("perApp", it) }
        per.put(pkg, per.optInt(pkg) + 1)
        val hr = cal(now).get(Calendar.HOUR_OF_DAY)
        t.optJSONArray("hourly")?.let { it.put(hr, it.optInt(hr) + 1) }

        // Dwell time between consecutive reels: watch time, plus "skimmed" for swipes under 2 seconds.
        val last = t.optLong("lastReelAt")
        if (last > 0) {
            val gap = now - last
            if (gap < 120_000) {
                t.put("watchMs", t.optLong("watchMs") + gap)
                if (gap < 2_000) t.put("skimmed", t.optInt("skimmed") + 1)
            }
        }
        t.put("lastReelAt", now)
        Store.put(ctx, "today", t)

        // All-time hour-of-day totals for the peak-hours chart.
        val agg = Store.obj(ctx, "agg", "{}")
        val hours = agg.optJSONArray("hours") ?: org.json.JSONArray(List(24) { 0 })
        hours.put(hr, hours.optInt(hr) + 1)
        agg.put("hours", hours)
        Store.put(ctx, "agg", agg)

        Notifier.checkNudges(ctx)
        FocusWidget.refresh(ctx)
        Sync.push(ctx)

        val cfg = Store.config(ctx)
        if (!trackOnly(cfg)) planAfterReel(ctx, cfg, now, last)
        val allowed = cfg.optInt("windowAllowed", 0)
        if (allowed <= 0 || trackOnly(cfg)) return
        val st = Store.status(ctx)
        val windowMs = cfg.optInt("windowMinutes", 5) * 60_000L
        if (now - st.optLong("windowStart") > windowMs) {
            st.put("windowStart", now)
            st.put("windowCount", 0)
        }
        st.put("windowCount", st.optInt("windowCount") + 1)
        if (st.optInt("windowCount") > allowed) {
            st.put("blockedUntil", now + cfg.optInt("cooldownMinutes", 30) * 60_000L)
            st.put("windowStart", 0)
            st.put("windowCount", 0)
        }
        Store.put(ctx, "status", st)
    }

    /** Plan bookkeeping after each counted reel: "one reel" starts a cooldown, "curious" starts its on-timer. */
    private fun planAfterReel(ctx: Context, cfg: JSONObject, now: Long, lastReelAt: Long) {
        val plan = cfg.optString("plan", "none")
        if (plan != "oneReel" && plan != "curious") return
        val st = Store.status(ctx)
        if (plan == "oneReel") {
            // The first reel is the one you get; the swipe to the next one that this counts ends the session.
            st.put("blockedUntil", now + cfg.optInt("planCooldown", 30) * 60_000L)
        } else {
            val idle = lastReelAt <= 0 || now - lastReelAt > 10 * 60_000L
            if (st.optLong("curiousStart") == 0L || idle) st.put("curiousStart", now)
            st.put("curiousLast", now)
        }
        Store.put(ctx, "status", st)
    }

    /** Count one time the block screen stopped a reel session, and keep a log of why (newest last, capped). */
    fun noteBlock(ctx: Context, pkg: String = "", reason: String = "", action: String = "") {
        val t = Store.today(ctx)
        t.put("blocks", t.optInt("blocks") + 1)
        Store.put(ctx, "today", t)
        val raw = Store.getString(ctx, "blockLog")
        val log = try { org.json.JSONArray(if (raw.isEmpty()) "[]" else raw) } catch (_: Exception) { org.json.JSONArray() }
        log.put(JSONObject().put("t", System.currentTimeMillis()).put("pkg", pkg).put("why", reason).put("act", action))
        // Keep the newest 400 entries.
        val trimmed = org.json.JSONArray()
        for (i in maxOf(0, log.length() - 400) until log.length()) trimmed.put(log.get(i))
        Store.putString(ctx, "blockLog", trimmed.toString())
    }

    fun pause(ctx: Context, minutes: Int, now: Long): Boolean {
        if (Store.config(ctx).optBoolean("strict", false)) return false
        val st = Store.status(ctx)
        if (st.optLong("hardBlockUntil") > now) return false
        st.put("pausedUntil", now + minutes * 60_000L)
        st.put("blockedUntil", 0)
        Store.put(ctx, "status", st)
        return true
    }

    fun hardBlock(ctx: Context, minutes: Int, now: Long) {
        val st = Store.status(ctx)
        st.put("hardBlockUntil", now + minutes * 60_000L)
        st.put("pausedUntil", 0)
        Store.put(ctx, "status", st)
    }
}
