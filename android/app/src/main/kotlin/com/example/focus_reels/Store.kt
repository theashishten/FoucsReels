package com.example.focus_reels

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** All app state lives in one SharedPreferences file as small JSON blobs. */
object Store {
    private const val PREFS = "focus_reels"
    const val DEFAULT_CONFIG =
        """{"trackOnly":true,"blockEnabled":true,"dailyLimit":100,"windowMinutes":5,"windowAllowed":0,"cooldownMinutes":30,"strict":false,"schedules":[],"apps":{}}"""

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun obj(c: Context, k: String, d: String): JSONObject =
        try { JSONObject(prefs(c).getString(k, null) ?: d) } catch (e: Exception) { JSONObject(d) }

    fun put(c: Context, k: String, o: JSONObject) { prefs(c).edit().putString(k, o.toString()).apply() }

    fun config(c: Context) = obj(c, "config", DEFAULT_CONFIG)
    fun status(c: Context) = obj(c, "status", "{}")
    fun history(c: Context) = obj(c, "history", "{}")

    /** True when our Accessibility service is switched on in system settings. */
    fun a11yEnabled(c: Context): Boolean {
        val enabled = android.provider.Settings.Secure.getString(
            c.contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: ""
        val me = android.content.ComponentName(c, ReelsAccessibilityService::class.java).flattenToString()
        return enabled.split(':').any { it.equals(me, true) }
    }

    fun getString(c: Context, k: String): String = prefs(c).getString(k, "") ?: ""
    fun putString(c: Context, k: String, v: String) { prefs(c).edit().putString(k, v).apply() }

    /** Returns today's counters, rolling the previous day into history when the date changes. */
    fun today(c: Context): JSONObject {
        val t = obj(c, "today", "{}")
        val key = Engine.dayKey(System.currentTimeMillis())
        if (getString(c, "firstDay").isEmpty()) putString(c, "firstDay", key)
        if (t.optString("day") == key) return t
        if (t.has("day") && t.optInt("total") > 0) {
            // Days are kept forever: nothing is pruned, so daily/weekly/monthly/yearly analysis keeps working.
            val h = history(c)
            h.put(t.getString("day"), t.getInt("total"))
            put(c, "history", h)
            // Rich per-day record (per-app, per-hour, watch time) for the analysis screens.
            val d = obj(c, "daily", "{}")
            d.put(t.getString("day"), JSONObject()
                .put("total", t.optInt("total"))
                .put("perApp", t.optJSONObject("perApp") ?: JSONObject())
                .put("hourly", t.optJSONArray("hourly") ?: JSONArray(List(24) { 0 }))
                .put("watchMs", t.optLong("watchMs"))
                .put("skimmed", t.optInt("skimmed"))
                .put("blocks", t.optInt("blocks"))
                .put("estimated", t.optInt("estimated")))
            put(c, "daily", d)
        }
        val n = JSONObject().put("day", key).put("total", 0)
            .put("perApp", JSONObject()).put("hourly", JSONArray(List(24) { 0 }))
        put(c, "today", n)
        return n
    }
}
