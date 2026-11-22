package com.example.focus_reels

import android.content.Context
import android.content.Intent
import org.json.JSONObject

/**
 * Per-app foreground time and scroll bursts for every app, kept as simple totals.
 * Only the package name and event type are used; nothing on screen is read for apps that are not
 * reel apps. Today's record lives in "screen"; finished days are archived (top apps only) in "screenDaily".
 */
object ScreenTime {
    private const val MAX_APPS_PER_DAY = 25

    private var launcherPkg: String? = null

    /** Packages that never count as "an app you were using". */
    fun ignored(ctx: Context, pkg: String): Boolean {
        if (pkg == ctx.packageName || pkg == "com.android.systemui") return true
        if (pkg.contains("inputmethod") || pkg.contains("keyboard")) return true
        return false
    }

    fun isLauncher(ctx: Context, pkg: String): Boolean {
        if (launcherPkg == null) {
            val home = ctx.packageManager.resolveActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0)
            launcherPkg = home?.activityInfo?.packageName ?: ""
        }
        return pkg == launcherPkg
    }

    private fun label(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg }

    /** Today's record, rolling yesterday into the archive when the date changes. */
    private fun record(ctx: Context): JSONObject {
        val key = Engine.dayKey(System.currentTimeMillis())
        val r = Store.obj(ctx, "screen", "{}")
        if (r.optString("day") == key) return r
        if (r.has("day")) {
            val apps = r.optJSONObject("apps") ?: JSONObject()
            val top = apps.keys().asSequence().map { it to apps.getJSONObject(it) }
                .sortedByDescending { it.second.optLong("ms") }.take(MAX_APPS_PER_DAY).toList()
            if (top.isNotEmpty()) {
                val slim = JSONObject()
                for ((p, v) in top) slim.put(p, v)
                val arch = Store.obj(ctx, "screenDaily", "{}")
                arch.put(r.getString("day"), slim)
                Store.put(ctx, "screenDaily", arch)
            }
        }
        val n = JSONObject().put("day", key).put("apps", JSONObject())
        Store.put(ctx, "screen", n)
        return n
    }

    private fun entry(ctx: Context, r: JSONObject, pkg: String): JSONObject {
        val apps = r.getJSONObject("apps")
        val e = apps.optJSONObject(pkg) ?: JSONObject().put("label", pkg).put("ms", 0L).put("scrolls", 0)
            .also { apps.put(pkg, it) }
        // Resolve the readable name (again, if an earlier lookup only found the package id).
        if (e.optString("label") == pkg) e.put("label", label(ctx, pkg))
        return e
    }

    fun addTime(ctx: Context, pkg: String, ms: Long) {
        val r = record(ctx)
        val e = entry(ctx, r, pkg)
        e.put("ms", e.optLong("ms") + ms)
        Store.put(ctx, "screen", r)
    }

    fun addScroll(ctx: Context, pkg: String) {
        val r = record(ctx)
        val e = entry(ctx, r, pkg)
        e.put("scrolls", e.optInt("scrolls") + 1)
        Store.put(ctx, "screen", r)
    }
}
